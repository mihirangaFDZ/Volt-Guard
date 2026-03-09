from typing import Optional, List, Dict
from datetime import datetime, timedelta
import logging

from fastapi import APIRouter, BackgroundTasks, Depends, Query, HTTPException
import pandas as pd

from app.models.energy_model import EnergyReading
from database import energy_col, anomaly_col, devices_col
from utils.jwt_handler import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/energy",
    tags=["Energy"],
    dependencies=[Depends(get_current_user)],
)

# ------------------------------------------------------------------
# Lazy-loaded ML services for real-time anomaly detection
# ------------------------------------------------------------------
_ml_service = None
_ae_service = None

def _get_ml_service():
    global _ml_service
    if _ml_service is None:
        from app.services.ml_service import EnergyMLService
        _ml_service = EnergyMLService(model_dir='models')
        _ml_service.load_models()
    return _ml_service if _ml_service.is_trained else None

def _get_ae_service():
    global _ae_service
    if _ae_service is None:
        from app.services.autoencoder_service import AutoencoderAnomalyDetector
        _ae_service = AutoencoderAnomalyDetector(model_dir='models')
        _ae_service.load_model()
    return _ae_service if _ae_service.is_trained else None


def _realtime_anomaly_check(reading_dict: dict):
    """
    Background task: check the latest batch of readings for the same
    location/module against the trained anomaly-detection models.

    If an anomaly is found, insert an alert into ``anomaly_col``.
    """
    try:
        location = reading_dict.get("location")
        module = reading_dict.get("module")
        if not location and not module:
            return

        # Fetch last 60 readings (~30 min at 30-second intervals)
        query = {}
        if module:
            query["module"] = module
        elif location:
            query["location"] = location

        cursor = (
            energy_col
            .find(query, {"_id": 0})
            .sort([("received_at", -1)])
            .limit(60)
        )
        rows = list(cursor)
        if len(rows) < 5:
            return  # Not enough data yet

        # Build a small DataFrame
        data = []
        for doc in rows:
            ts = doc.get("received_at")
            if isinstance(ts, dict) and "$date" in ts:
                ts = datetime.fromisoformat(ts["$date"].replace("Z", "+00:00"))
            elif not isinstance(ts, datetime):
                continue

            current_a = doc.get("current_a", 0) or 0
            data.append({
                "module": doc.get("module"),
                "location": doc.get("location", location),
                "current_a": current_a,
                "current_ma": doc.get("current_ma", current_a * 1000),
                "vref": doc.get("vref", 3.3),
                "wifi_rssi": doc.get("wifi_rssi", -50),
                "received_at": ts,
                "power_w": current_a * 230,
            })

        if len(data) < 5:
            return

        df = pd.DataFrame(data).sort_values("received_at")

        # ---- Simple statistical check first ----
        latest_power = df.iloc[-1]["power_w"]
        avg_power = df["power_w"].mean()
        std_power = df["power_w"].std()

        # If latest reading is more than 3 standard deviations above mean
        # and the absolute power is non-trivial (>10W), flag it
        is_statistical_anomaly = (
            std_power > 0
            and latest_power > (avg_power + 3 * std_power)
            and latest_power > 10
        )

        # ---- Add time features for ML models ----
        df["hour"] = df["received_at"].dt.hour
        df["day_of_week"] = df["received_at"].dt.dayofweek
        import numpy as np
        df["hour_sin"] = np.sin(2 * np.pi * df["hour"] / 24)
        df["hour_cos"] = np.cos(2 * np.pi * df["hour"] / 24)
        df["day_sin"] = np.sin(2 * np.pi * df["day_of_week"] / 7)
        df["day_cos"] = np.cos(2 * np.pi * df["day_of_week"] / 7)
        df["is_weekend"] = (df["day_of_week"] >= 5).astype(int)

        # Rolling features
        df["current_a_rolling_mean_1h"] = df["current_a"].rolling(12, min_periods=1).mean()
        df["current_a_rolling_std_1h"] = df["current_a"].rolling(12, min_periods=1).std().fillna(0)
        df["power_w_rolling_mean_1h"] = df["power_w"].rolling(12, min_periods=1).mean()
        df["power_w_rolling_std_1h"] = df["power_w"].rolling(12, min_periods=1).std().fillna(0)

        # Lag features
        df["current_a_lag_1"] = df["current_a"].shift(1).fillna(df["current_a"].iloc[0])
        df["current_a_lag_2"] = df["current_a"].shift(2).fillna(df["current_a"].iloc[0])
        df["power_w_lag_1"] = df["power_w"].shift(1).fillna(df["power_w"].iloc[0])
        df["power_w_lag_2"] = df["power_w"].shift(2).fillna(df["power_w"].iloc[0])

        df = df.fillna(0)

        ml_anomaly = False
        anomaly_score = 0.0
        detection_method = "statistical"

        # ---- Try Isolation Forest ----
        ml_service = _get_ml_service()
        if ml_service is not None:
            try:
                result_df = ml_service.detect_anomalies(df.copy())
                latest_row = result_df.iloc[-1]
                if latest_row.get("is_anomaly", 0) == 1 and latest_row.get("anomaly_score", 0) >= 0.5:
                    ml_anomaly = True
                    anomaly_score = float(latest_row["anomaly_score"])
                    detection_method = "isolation_forest"
            except Exception as e:
                logger.debug(f"IF detection skipped: {e}")

        # ---- Try Autoencoder ----
        ae_service = _get_ae_service()
        if ae_service is not None:
            try:
                ae_df = ae_service.detect_anomalies(df.copy())
                latest_row = ae_df.iloc[-1]
                ae_score = float(latest_row.get("anomaly_score_ae", 0))
                if latest_row.get("is_anomaly_ae", 0) == 1 and ae_score >= 0.5:
                    # Use autoencoder result if it has a higher score
                    if ae_score > anomaly_score:
                        ml_anomaly = True
                        anomaly_score = ae_score
                        detection_method = "autoencoder"
            except Exception as e:
                logger.debug(f"AE detection skipped: {e}")

        # ---- Decide whether to create an alert ----
        should_alert = ml_anomaly or is_statistical_anomaly

        if not should_alert:
            return

        # Avoid duplicate alerts within 5 minutes for same location
        five_min_ago = datetime.utcnow() - timedelta(minutes=5)
        existing = anomaly_col.find_one({
            "location": location or module,
            "detected_at": {"$gte": five_min_ago.isoformat()},
        })
        if existing:
            return

        # Determine severity
        if anomaly_score > 0.7 or latest_power > (avg_power + 4 * std_power if std_power > 0 else avg_power * 2):
            severity = "High"
        elif anomaly_score > 0.5 or is_statistical_anomaly:
            severity = "Medium"
        else:
            severity = "Low"

        # Resolve device from DB so anomaly is stored with real device_id and device_name
        device_info = None
        if module:
            device_info = devices_col.find_one({"module_id": module}) or devices_col.find_one({"module": module})
        if not device_info and location:
            device_info = devices_col.find_one({"location": location})
        device_name = (device_info.get("device_name") if device_info else None) or (location or module or "Unknown")
        device_id = (device_info.get("device_id") if device_info else None) or (location or module or "unknown")

        description = (
            f"Abnormal energy usage detected on {device_name}: "
            f"{latest_power:.1f}W (avg: {avg_power:.1f}W)"
        )

        alert_doc = {
            "device_id": device_id,
            "device_name": device_name,
            "device_type": (device_info.get("device_type") if device_info else None) or "",
            "anomaly_type": "energy_consumption",
            "severity": severity,
            "description": description,
            "detected_at": datetime.utcnow().isoformat(),
            "anomaly_score": anomaly_score if ml_anomaly else 0.0,
            "power_w": float(latest_power),
            "avg_power_w": float(avg_power),
            "current_a": float(df.iloc[-1]["current_a"]),
            "location": location or "",
            "module": module or "",
            "detection_method": detection_method,
            "status": "active",
        }
        anomaly_col.insert_one(alert_doc)
        logger.info(f"Real-time anomaly alert: {severity} - {description}")

    except Exception as e:
        logger.error(f"Real-time anomaly check failed: {e}")


# ------------------------------------------------------------------
# Endpoints
# ------------------------------------------------------------------

@router.post("/")
def add_energy(data: EnergyReading, background_tasks: BackgroundTasks):
    """Store incoming current/energy telemetry and run real-time anomaly check."""
    doc = data.dict(exclude_none=True)
    energy_col.insert_one(doc)
    # Trigger anomaly detection in the background so the response is instant
    background_tasks.add_task(_realtime_anomaly_check, doc)
    return {"message": "Energy data stored"}


def _timestamp_sort_fields():
    return [
        ("received_at", -1),
        ("receivedAt", -1),
        ("timestamp", -1),
        ("created_at", -1),
        ("_id", -1),
    ]


def _parse_ts(raw) -> Optional[datetime]:
    if isinstance(raw, datetime):
        return raw
    if isinstance(raw, str):
        try:
            # Allow basic ISO strings with or without trailing Z
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except Exception:
            return None
    return None


def _serialize_doc_timestamps(doc: dict) -> dict:
    """Ensure received_at (and similar timestamps) are ISO strings with Z (UTC) for frontend."""
    out = dict(doc)
    for key in ("received_at", "receivedAt", "timestamp", "created_at"):
        val = out.get(key)
        if isinstance(val, datetime):
            out[key] = val.isoformat() + "Z" if val.tzinfo is None else val.isoformat()
    return out


def _integrate_energy_kwh(readings: List[Dict]) -> Dict[str, Dict]:
    """Compute approximate energy (kWh) per location using trapezoidal integration over current/voltage."""
    per_loc_points: Dict[str, List[Dict]] = {}
    for r in readings:
        loc = r.get("location")
        if not loc:
            continue
        ts = _parse_ts(
            r.get("received_at")
            or r.get("receivedAt")
            or r.get("timestamp")
            or r.get("created_at")
        )
        if ts is None:
            continue
        current = 0.0
        if isinstance(r.get("current_a"), (int, float)):
            current = float(r["current_a"])
        elif isinstance(r.get("current_ma"), (int, float)):
            current = float(r["current_ma"]) / 1000.0
        voltage = float(r.get("voltage", 230.0)) if isinstance(r.get("voltage"), (int, float)) else 230.0

        per_loc_points.setdefault(loc, []).append({"ts": ts, "current": current, "voltage": voltage})

    results: Dict[str, Dict] = {}
    for loc, points in per_loc_points.items():
        if not points:
            continue
        points.sort(key=lambda x: x["ts"])
        kwh = 0.0
        for i in range(1, len(points)):
            prev = points[i - 1]
            cur = points[i]
            dt_seconds = int((cur["ts"] - prev["ts"]).total_seconds())
            if dt_seconds <= 0:
                continue
            # cap huge gaps to avoid over-estimation on stale data
            capped = min(dt_seconds, 900)
            avg_current = (prev["current"] + cur["current"]) / 2.0
            voltage = cur["voltage"]  # assume voltage relatively stable
            kwh += (avg_current * voltage) * (capped / 3600.0) / 1000.0

        results[loc] = {
            "location": loc,
            "energy_kwh": kwh,
            "samples": len(points),
            "start": points[0]["ts"],
            "end": points[-1]["ts"],
        }

    return results


@router.get("/latest")
def get_latest_energy(
    limit: int = Query(50, ge=1, le=500),
    module: Optional[str] = None,
    location: Optional[str] = None,
):
    """Return the most recent energy/current readings, newest first."""
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location

    cursor = (
        energy_col
        .find(query, {"_id": 0})
        .sort(_timestamp_sort_fields())
        .limit(limit)
    )
    return [_serialize_doc_timestamps(d) for d in cursor]


@router.get("/by-location")
def get_latest_energy_by_location(module: Optional[str] = None):
    """Return the latest reading per location (one row per location)."""
    match = {}
    if module:
        match["module"] = module

    pipeline = []
    if match:
        pipeline.append({"$match": match})

    pipeline.extend(
        [
          {"$sort": {f: -1 for f, _ in _timestamp_sort_fields()}},
          {"$group": {"_id": "$location", "doc": {"$first": "$$ROOT"}}},
          {"$replaceRoot": {"newRoot": "$doc"}},
          {"$project": {"_id": 0}},
        ]
    )

    return [_serialize_doc_timestamps(d) for d in energy_col.aggregate(pipeline)]


@router.get("/usage")
def get_energy_usage(
    limit: int = Query(2000, ge=10, le=20000),
    module: Optional[str] = None,
    location: Optional[str] = None,
):
    """Return approximate cumulative energy (kWh) per location over the fetched readings."""
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location

    cursor = (
        energy_col
        .find(query, {"_id": 0})
        .sort(_timestamp_sort_fields())
        .limit(limit)
    )
    readings = list(cursor)
    if not readings:
        return {"usage": [], "count": 0}

    results = _integrate_energy_kwh(readings)
    return {
        "usage": list(results.values()),
        "count": len(readings),
    }
