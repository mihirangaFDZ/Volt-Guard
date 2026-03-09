from typing import Optional, List, Any
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, Body
from pydantic import BaseModel
from bson.objectid import ObjectId
from database import analytics_col, energy_col, devices_col, energy_advice_history_col
from app.services.current_energy_recommendation_model import CurrentEnergyRecommendationModel
from app.services.occupancy_telemetry_recommendation_model import OccupancyTelemetryRecommendationModel
from utils.jwt_handler import get_current_user_optional
from app.models.analytics_model import (
    Recommendation,
    RecommendationSeverity,
    RecommendationsResponse,
)

router = APIRouter(
    prefix="/analytics",
    tags=["Analytics"],
    dependencies=[Depends(get_current_user_optional)],
)

# Sri Lankan timezone (UTC+5:30)
SRI_LANKA_TZ = timezone(timedelta(hours=5, minutes=30))

# Threshold for considering sensor as "turned off" (1 hour)
SENSOR_OFFLINE_THRESHOLD_MINUTES = 60


@router.get("/filters")
def get_available_filters():
    """
    Get available locations and modules from occupancy_telemetry table.
    Returns distinct values for filtering.
    """
    # Get distinct locations
    locations = analytics_col.distinct("location")
    locations = [loc for loc in locations if loc]  # Filter out None/empty values
    locations.sort()
    
    # Get distinct modules
    modules = analytics_col.distinct("module")
    modules = [mod for mod in modules if mod]  # Filter out None/empty values
    modules.sort()
    
    return {
        "locations": locations,
        "modules": modules
    }


@router.get("/device-filters")
def get_device_filters():
    """
    Get available devices from devices table.
    Returns all devices with their details for filtering.
    """
    devices = list(devices_col.find({}, {"_id": 0}))
    devices.sort(key=lambda x: x.get("device_name", ""))
    return {"devices": devices}


def _apply_device_filter(query: dict, device_id: Optional[str]) -> None:
    """
    Resolve selected device to module_id and apply to analytics/energy query.
    """
    if not device_id:
        return

    device = devices_col.find_one({"device_id": device_id}, {"_id": 0})
    module_id = device.get("module_id") if device else None
    if module_id:
        query["module"] = module_id


@router.get("/occupancy-stats")
def get_occupancy_stats(
    limit: int = 50, 
    module: Optional[str] = None, 
    location: Optional[str] = None,
    device_id: Optional[str] = None
):
    """
    Get occupancy statistics from occupancy_telemetry table.
    Returns statistics about occupied vs vacant periods.
    If the latest reading is older than threshold, sensor is considered "turned off"
    and values are set to 0 with vacant occupancy.
    """
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location
    
    _apply_device_filter(query, device_id)

    cursor = (
        analytics_col
        .find(query, {"_id": 0})
        .sort([
            ("received_at", -1),
            ("receivedAt", -1),
            ("timestamp", -1),
            ("_id", -1),
        ])
        .limit(limit)
    )

    docs = list(cursor)
    if not docs:
        return {
            "total_readings": 0,
            "occupied_count": 0,
            "vacant_count": 0,
            "occupied_percentage": 0.0,
            "vacant_percentage": 0.0,
            "is_currently_occupied": False,
        }

    # Check if latest reading indicates sensor is turned off
    latest = docs[0]
    latest_ts = latest.get("received_at") or latest.get("receivedAt") or latest.get("timestamp")
    latest_time = _to_datetime(latest_ts) if latest_ts else None
    
    sensor_turned_off = _is_sensor_turned_off(latest_time) if latest_time else True
    
    # If sensor is turned off, modify the latest reading to show 0 values and vacant
    if sensor_turned_off:
        latest = dict(latest)  # Create a copy to avoid modifying original
        _set_reading_to_offline(latest)
        docs[0] = latest

    # Count occupied and vacant readings (after potential modification)
    occupied_count = sum(1 for d in docs if d.get("pir") == 1 or d.get("rcwl") == 1)
    vacant_count = len(docs) - occupied_count
    total_readings = len(docs)
    
    # Latest reading to determine current status
    is_currently_occupied = latest.get("pir") == 1 or latest.get("rcwl") == 1

    return {
        "total_readings": total_readings,
        "occupied_count": occupied_count,
        "vacant_count": vacant_count,
        "occupied_percentage": round((occupied_count / total_readings * 100), 1) if total_readings > 0 else 0.0,
        "vacant_percentage": round((vacant_count / total_readings * 100), 1) if total_readings > 0 else 0.0,
        "is_currently_occupied": is_currently_occupied,
    }


@router.get("/latest")
def get_latest_readings(
    limit: int = 50, 
    module: Optional[str] = None, 
    location: Optional[str] = None,
    device_id: Optional[str] = None
):
    """
    Get latest sensor readings.
    If the latest reading is older than threshold, sensor is considered
    "turned off" and values are set to 0 with vacant occupancy.
    """
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location

    _apply_device_filter(query, device_id)

    cursor = (
        analytics_col
        .find(query, {"_id": 0})
        .sort([
            ("received_at", -1),
            ("receivedAt", -1),
            ("timestamp", -1),
            ("_id", -1),
        ])
        .limit(limit)
    )   

    normalized = []
    docs_list = list(cursor)
    
    # Check if the latest reading (first in sorted list) indicates sensor is turned off
    if docs_list:
        latest = docs_list[0]
        latest_ts = latest.get("received_at") or latest.get("receivedAt") or latest.get("timestamp")
        latest_time = _to_datetime(latest_ts) if latest_ts else None
        sensor_turned_off = _is_sensor_turned_off(latest_time) if latest_time else True
        
        if sensor_turned_off:
            # Create a copy and modify it
            latest = dict(latest)
            _set_reading_to_offline(latest)
            docs_list[0] = latest
    
    for doc in docs_list:
        ts = doc.get("received_at") or doc.get("receivedAt") or doc.get("timestamp")
        if ts is not None:
            dt = _to_datetime(ts)
            if dt is not None:
                # Convert to Sri Lankan time and return as ISO string
                doc["receivedAt"] = dt.isoformat()
            else:
                doc["receivedAt"] = ts
        normalized.append(doc)

    return normalized


def _to_datetime(value):
    if isinstance(value, datetime):
        dt = value
    else:
        try:
            dt = datetime.fromisoformat(str(value))
        except Exception:
            return None
    
    # Ensure timezone-aware datetime (assume UTC if naive)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    
    # Convert to Sri Lankan time
    return dt.astimezone(SRI_LANKA_TZ)


def _is_sensor_turned_off(reading_time: datetime) -> bool:
    """
    Check if sensor is turned off based on reading timestamp.
    Sensor is considered "turned off" if the reading is older than threshold.
    """
    if reading_time is None:
        return True
    
    now = datetime.now(SRI_LANKA_TZ)
    time_diff = (now - reading_time).total_seconds() / 60  # Convert to minutes
    return time_diff > SENSOR_OFFLINE_THRESHOLD_MINUTES


def _set_reading_to_offline(doc: dict):
    """
    Set sensor reading values to 0 and occupancy to vacant when sensor is turned off.
    """
    doc["temperature"] = 0.0
    doc["humidity"] = 0.0
    doc["pir"] = 0
    doc["rcwl"] = 0
    return doc


def _derive_recommendations(docs: List[dict]) -> List[Recommendation]:
    """
    Derive actionable recommendations from sensor readings.
    Analyzes patterns across multiple readings to provide intelligent recommendations.
    """
    if not docs:
        return []

    # Sort by timestamp (most recent first)
    latest = docs[0]
    temps = [d.get("temperature") for d in docs if isinstance(d.get("temperature"), (int, float))]
    hums = [d.get("humidity") for d in docs if isinstance(d.get("humidity"), (int, float))]
    avg_temp = sum(temps) / len(temps) if temps else None
    avg_hum = sum(hums) / len(hums) if hums else None

    latest_time = _to_datetime(latest.get("received_at") or latest.get("receivedAt") or latest.get("timestamp"))
    last_occ = next((d for d in docs if d.get("pir") == 1 or d.get("rcwl") == 1), None)
    last_occ_time = _to_datetime(
        last_occ.get("received_at") or last_occ.get("receivedAt") or last_occ.get("timestamp")
    ) if last_occ else None
    vacancy_minutes = 0
    if latest_time and last_occ_time:
        vacancy_minutes = int(max((latest_time - last_occ_time).total_seconds() // 60, 0))

    rssi = latest.get("rssi") if isinstance(latest.get("rssi"), int) else None
    if rssi is not None:
        if rssi >= -60:
            rssi_label = "Strong"
        elif rssi >= -75:
            rssi_label = "Fair"
        else:
            rssi_label = "Weak"
    else:
        rssi_label = "Unknown"

    recs: List[Recommendation] = []

    # Recommendation 1: Turn off AC in vacant room (High priority)
    temp_val = latest.get("temperature")
    if (latest.get("pir") == 0 and latest.get("rcwl") == 0) and isinstance(temp_val, (int, float)):
        if temp_val > 31 and vacancy_minutes >= 30:
            recs.append(
                Recommendation(
                    title="Turn off AC in vacant room",
                    detail=f"Vacant for {vacancy_minutes} min at {temp_val:.1f}°C.",
                    cta="Send Alert",
                    severity=RecommendationSeverity.high,
                )
            )

    # Recommendation 2: Align motion sensing (check pattern across recent readings)
    # Check if there's a pattern of RCWL=1 while PIR=0 in recent readings
    recent_readings = docs[:10]  # Check last 10 readings
    rcwl_pir_mismatch_count = sum(
        1 for d in recent_readings
        if d.get("rcwl") == 1 and d.get("pir") == 0
    )
    if rcwl_pir_mismatch_count > 0:
        recs.append(
            Recommendation(
                title="Align motion sensing",
                detail=f"RCWL detected motion while PIR didn't in {rcwl_pir_mismatch_count} of last {len(recent_readings)} readings. Reposition sensor to reduce false motion.",
                cta="Inspect",
                severity=RecommendationSeverity.medium,
            )
        )

    # Recommendation 3: Check link quality (Medium priority)
    if rssi_label != "Strong":
        rssi_detail = f"RSSI {rssi_label}"
        if rssi is not None:
            rssi_detail += f" ({rssi} dBm)"
        rssi_detail += ". Move gateway or adjust antenna."
        recs.append(
            Recommendation(
                title="Check link quality",
                detail=rssi_detail,
                cta="Check Link",
                severity=RecommendationSeverity.medium,
            )
        )

    # Recommendation 4: Comfort guardrails (Low priority - informational)
    if isinstance(temp_val, (int, float)):
        recs.append(
            Recommendation(
                title="Comfort guardrails",
                detail="Keep 24-27°C occupied; allow 29-30°C when vacant to save energy.",
                cta="Apply",
                severity=RecommendationSeverity.low,
            )
        )

    # Recommendation 5: Review comfort drift (Low priority - informational)
    if avg_temp is not None and avg_hum is not None:
        recs.append(
            Recommendation(
                title="Review comfort drift",
                detail=f"Avg {avg_temp:.1f}°C / {avg_hum:.0f}% RH over last {len(docs)} readings.",
                cta="Review",
                severity=RecommendationSeverity.low,
            )
        )

    # Sort by severity: high -> medium -> low
    severity_order = {RecommendationSeverity.high: 0, RecommendationSeverity.medium: 1, RecommendationSeverity.low: 2}
    recs.sort(key=lambda r: severity_order.get(r.severity, 3))

    return recs


@router.get("/recommendations", response_model=RecommendationsResponse)
def get_recommendations(limit: int = 50, module: Optional[str] = None, location: Optional[str] = None):
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location

    cursor = (
        analytics_col
        .find(query, {"_id": 0})
        .sort([
            ("received_at", -1),
            ("receivedAt", -1),
            ("timestamp", -1),
            ("_id", -1),
        ])
        .limit(limit)
    )

    docs = list(cursor)
    if not docs:
        return RecommendationsResponse(recommendations=[], count=0)

    recs = _derive_recommendations(docs)
    return RecommendationsResponse(recommendations=recs, count=len(recs))


# ------------------------------------------------------------------
# Environment recommendations (occupancy_telemetry + trained model)
# ------------------------------------------------------------------


@router.get("/environment-recommendations")
def get_environment_recommendations(
    module: Optional[str] = None,
    location: Optional[str] = None,
    device_id: Optional[str] = None,
):
    """
    Get actionable environment recommendations from occupancy_telemetry table.
    Uses the latest reading (temperature, humidity, rcwl, pir, rssi) and the
    model trained on occupancy_telemetry_recommendations_dataset.csv (1500 rows).
    Returns accurate, user-understandable advice for the Environment section.
    """
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location
    _apply_device_filter(query, device_id)

    cursor = (
        analytics_col
        .find(query, {"_id": 0, "temperature": 1, "humidity": 1, "rcwl": 1, "pir": 1, "rssi": 1})
        .sort([
            ("received_at", -1),
            ("receivedAt", -1),
            ("timestamp", -1),
            ("_id", -1),
        ])
        .limit(1)
    )
    latest = next(cursor, None)
    if not latest:
        return {"recommendations": [], "message": "No occupancy telemetry data."}

    temperature = latest.get("temperature")
    humidity = latest.get("humidity")
    rcwl = latest.get("rcwl", 0)
    pir = latest.get("pir", 0)
    rssi = latest.get("rssi")

    if temperature is None or not isinstance(temperature, (int, float)):
        temperature = 25.0
    if humidity is None or not isinstance(humidity, (int, float)):
        humidity = 50.0
    if not isinstance(rcwl, int):
        rcwl = 0
    if not isinstance(pir, int):
        pir = 0
    if rssi is not None and not isinstance(rssi, int):
        rssi = -70

    model = OccupancyTelemetryRecommendationModel()
    if not model.load_model():
        # Fallback: derive from docs (same as /recommendations)
        docs_cursor = (
            analytics_col
            .find(query, {"_id": 0})
            .sort([("received_at", -1), ("receivedAt", -1), ("timestamp", -1), ("_id", -1)])
            .limit(50)
        )
        docs = list(docs_cursor)
        recs = _derive_recommendations(docs)
        return {
            "recommendations": [
                {"title": r.title, "message": r.detail, "severity": r.severity.value, "advice": None, "mitigation": None}
                for r in recs
            ],
            "message": "Model not trained. Run scripts/train_occupancy_telemetry_recommendation_model.py",
        }

    recs = model.predict(
        temperature=float(temperature),
        humidity=float(humidity),
        rcwl=int(rcwl),
        pir=int(pir),
        rssi=int(rssi) if rssi is not None else None,
    )
    return {"recommendations": recs}


# ------------------------------------------------------------------
# Current Energy Analytics Endpoints
# ------------------------------------------------------------------

@router.get("/energy-filters")
def get_energy_filters():
    """
    Get available locations and modules from energy_readings table.
    Returns distinct values for filtering current energy analytics.
    """
    # Get distinct locations
    locations = energy_col.distinct("location")
    locations = [loc for loc in locations if loc]  # Filter out None/empty values
    locations.sort()
    
    # Get distinct modules
    modules = energy_col.distinct("module")
    modules = [mod for mod in modules if mod]  # Filter out None/empty values
    modules.sort()
    
    return {
        "locations": locations,
        "modules": modules
    }


@router.get("/current-energy-stats")
def get_current_energy_stats(
    limit: int = 120,
    module: Optional[str] = None,
    location: Optional[str] = None,
    device_id: Optional[str] = None
):
    """
    Get aggregated current energy statistics from energy_readings table.
    Returns live data with computed metrics for analytics dashboard.
    """
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location

    _apply_device_filter(query, device_id)

    cursor = (
        energy_col
        .find(query, {"_id": 0})
        .sort([
            ("received_at", -1),
            ("receivedAt", -1),
            ("timestamp", -1),
            ("_id", -1),
        ])
        .limit(limit)
    )

    docs = list(cursor)
    if not docs:
        return {
            "total_readings": 0,
            "latest": None,
            "readings": [],
            "current_a": {
                "latest": 0.0,
                "avg": 0.0,
                "min": 0.0,
                "max": 0.0,
            },
            "current_ma": {
                "latest": 0.0,
                "avg": 0.0,
                "min": 0.0,
                "max": 0.0,
            },
            "power_w": {
                "latest": 0.0,
                "avg": 0.0,
            },
            "estimated_energy_kwh": 0.0,
            "trend": {
                "direction": "stable",
                "percent_change": 0.0,
            },
            "signal": {
                "latest_rssi": None,
                "quality": "unknown",
            },
            "time_window_minutes": 0,
        }

    # Extract current values
    current_a_values = [
        float(d.get("current_a", 0) or 0)
        for d in docs
        if d.get("current_a") is not None
    ]
    current_ma_values = [
        float(d.get("current_ma", 0) or 0)
        for d in docs
        if d.get("current_ma") is not None
    ]

    if not current_a_values:
        current_a_values = [0.0]
    if not current_ma_values:
        current_ma_values = [0.0]

    # Latest reading
    latest = docs[0]
    latest_current_a = float(latest.get("current_a", 0) or 0)
    latest_current_ma = float(latest.get("current_ma", 0) or 0)
    latest_power_w = latest_current_a * 230.0  # Assuming 230V

    # Compute statistics
    avg_current_a = sum(current_a_values) / len(current_a_values)
    min_current_a = min(current_a_values)
    max_current_a = max(current_a_values)

    avg_current_ma = sum(current_ma_values) / len(current_ma_values)
    min_current_ma = min(current_ma_values)
    max_current_ma = max(current_ma_values)

    avg_power_w = avg_current_a * 230.0

    # Compute trend (compare recent vs baseline)
    recent_window = min(3, len(current_a_values))
    baseline_window = min(6, len(current_a_values))

    recent_values = current_a_values[:recent_window]
    baseline_values = current_a_values[:baseline_window]

    recent_avg = sum(recent_values) / len(recent_values) if recent_values else 0
    baseline_avg = sum(baseline_values) / len(baseline_values) if baseline_values else 0

    if baseline_avg == 0:
        percent_change = 0.0
        trend_direction = "stable"
    else:
        percent_change = ((recent_avg - baseline_avg) / baseline_avg) * 100

        if abs(percent_change) < 5:
            trend_direction = "stable"
        elif percent_change > 0:
            trend_direction = "rising"
        else:
            trend_direction = "falling"

    # Signal quality
    latest_rssi = latest.get("wifi_rssi")
    if latest_rssi is None:
        signal_quality = "unknown"
    elif latest_rssi >= -60:
        signal_quality = "strong"
    elif latest_rssi >= -75:
        signal_quality = "fair"
    else:
        signal_quality = "weak"

    # Time window
    first_ts = _to_datetime(
        docs[-1].get("received_at")
        or docs[-1].get("receivedAt")
        or docs[-1].get("timestamp")
    )
    last_ts = _to_datetime(
        docs[0].get("received_at")
        or docs[0].get("receivedAt")
        or docs[0].get("timestamp")
    )

    time_window_minutes = 0
    if first_ts and last_ts:
        time_window_minutes = int((last_ts - first_ts).total_seconds() / 60)

    # Expose recent readings for frontend (when devices are connected)
    readings_for_client = []
    for d in docs[:50]:
        doc_copy = dict(d)
        # Ensure received_at is ISO string for JSON
        ra = doc_copy.get("received_at") or doc_copy.get("receivedAt") or doc_copy.get("timestamp")
        if hasattr(ra, "isoformat"):
            doc_copy["received_at"] = ra.isoformat()
        readings_for_client.append(doc_copy)

    # Estimate energy (simple integration)
    estimated_kwh = 0.0
    for i in range(1, len(docs)):
        prev = docs[i]
        curr = docs[i - 1]

        prev_ts = _to_datetime(
            prev.get("received_at")
            or prev.get("receivedAt")
            or prev.get("timestamp")
        )
        curr_ts = _to_datetime(
            curr.get("received_at")
            or curr.get("receivedAt")
            or curr.get("timestamp")
        )

        if not prev_ts or not curr_ts:
            continue

        dt_seconds = (curr_ts - prev_ts).total_seconds()
        if dt_seconds <= 0:
            continue

        # Cap to avoid over-estimation
        dt_seconds = min(dt_seconds, 900)

        prev_current = float(prev.get("current_a", 0) or 0)
        curr_current = float(curr.get("current_a", 0) or 0)
        avg_current = (prev_current + curr_current) / 2.0

        # kWh = (current * voltage * time_hours) / 1000
        estimated_kwh += (avg_current * 230.0 * (dt_seconds / 3600.0)) / 1000.0

    return {
        "total_readings": len(docs),
        "latest": latest,
        "readings": readings_for_client,
        "current_a": {
            "latest": round(latest_current_a, 6),
            "avg": round(avg_current_a, 6),
            "min": round(min_current_a, 6),
            "max": round(max_current_a, 6),
        },
        "current_ma": {
            "latest": round(latest_current_ma, 2),
            "avg": round(avg_current_ma, 2),
            "min": round(min_current_ma, 2),
            "max": round(max_current_ma, 2),
        },
        "power_w": {
            "latest": round(latest_power_w, 2),
            "avg": round(avg_power_w, 2),
        },
        "estimated_energy_kwh": round(estimated_kwh, 6),
        "trend": {
            "direction": trend_direction,
            "percent_change": round(percent_change, 2),
        },
        "signal": {
            "latest_rssi": latest_rssi,
            "quality": signal_quality,
        },
        "time_window_minutes": time_window_minutes,
    }


# ------------------------------------------------------------------
# Current energy recommendations (trained model from CSV dataset)
# ------------------------------------------------------------------


@router.get("/current-energy-recommendations")
def get_current_energy_recommendations(
    current_a: float,
    current_ma: Optional[float] = None,
    power_w: Optional[float] = None,
    trend_direction: Optional[str] = "stable",
    trend_percent_change: Optional[float] = 0.0,
    signal_quality: Optional[str] = "unknown",
):
    """
    Get recommendations for current energy analysis using the trained model.
    Model is trained on the current_energy_recommendations_dataset.csv (2000 rows).
    Returns accurate, user-understandable advice, savings, waste, and mitigation.
    """
    model = CurrentEnergyRecommendationModel()
    if not model.load_model():
        return {"recommendations": [], "message": "Model not trained. Run scripts/train_current_energy_recommendation_model.py"}
    recs = model.predict(
        current_a=current_a,
        current_ma=current_ma,
        power_w=power_w,
        trend_direction=trend_direction or "stable",
        trend_percent_change=trend_percent_change or 0.0,
        signal_quality=signal_quality or "unknown",
    )
    return {"recommendations": recs}


# ------------------------------------------------------------------
# Energy advice & recommendations history (save and list)
# ------------------------------------------------------------------


class ReadingSnapshot(BaseModel):
    """Snapshot of readings when recommendations were generated."""
    current_a: float
    current_ma: Optional[float] = None
    power_w: Optional[float] = None
    trend_direction: Optional[str] = "stable"
    trend_percent_change: Optional[float] = 0.0
    signal_quality: Optional[str] = None
    location: Optional[str] = None
    module: Optional[str] = None


class RecommendationItem(BaseModel):
    title: str
    message: str
    severity: str
    advice: Optional[str] = None
    mitigation: Optional[str] = None
    estimated_savings_kwh_per_day: Optional[float] = None
    energy_wasted_kwh_per_day: Optional[float] = None


class EnergyAdviceHistoryPayload(BaseModel):
    readings_snapshot: ReadingSnapshot
    recommendations: List[RecommendationItem]


@router.post("/energy-advice-history")
def save_energy_advice_history(payload: EnergyAdviceHistoryPayload = Body(...)):
    """
    Save current energy advice and recommendations with readings snapshot to history table.
    """
    doc = {
        "created_at": datetime.utcnow(),
        "readings_snapshot": payload.readings_snapshot.model_dump(),
        "recommendations": [r.model_dump() for r in payload.recommendations],
    }
    result = energy_advice_history_col.insert_one(doc)
    return {"ok": True, "id": str(result.inserted_id)}


@router.get("/energy-advice-history")
def get_energy_advice_history(
    limit: int = 50,
    since: Optional[str] = None,
    before: Optional[str] = None,
):
    """
    Get history of energy advice and recommendations with readings (newest first).
    Optional: since / before as ISO datetime strings for filtering.
    """
    query = {}
    if since:
        try:
            since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
            query["created_at"] = {"$gte": since_dt}
        except ValueError:
            pass
    if before:
        try:
            before_dt = datetime.fromisoformat(before.replace("Z", "+00:00"))
            query.setdefault("created_at", {})["$lt"] = before_dt
        except ValueError:
            pass

    cursor = (
        energy_advice_history_col
        .find(query)
        .sort("created_at", -1)
        .limit(limit)
    )
    items = []
    for d in cursor:
        d = dict(d)
        d["id"] = str(d.pop("_id", ""))
        created = d.get("created_at")
        if hasattr(created, "isoformat"):
            d["created_at"] = created.isoformat() + ("Z" if created.tzinfo is None else "")
        items.append(d)
    return {"items": items, "count": len(items)}


class EnergyAdviceHistoryDeletePayload(BaseModel):
    ids: List[str]


@router.delete("/energy-advice-history")
def delete_energy_advice_history(payload: EnergyAdviceHistoryDeletePayload = Body(...)):
    """
    Delete selected energy advice history entries by id.
    """
    if not payload.ids:
        return {"ok": True, "deleted_count": 0}
    object_ids = []
    for oid in payload.ids:
        try:
            object_ids.append(ObjectId(oid))
        except Exception:
            continue
    if not object_ids:
        return {"ok": True, "deleted_count": 0}
    result = energy_advice_history_col.delete_many({"_id": {"$in": object_ids}})
    return {"ok": True, "deleted_count": result.deleted_count}
