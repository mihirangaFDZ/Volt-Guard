from datetime import datetime, timedelta
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, Query

from database import energy_col, prediction_col, anomalies_col, devices_col, analytics_col
from routes.analytics import _derive_recommendations
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"],
    dependencies=[Depends(get_current_user)],
)

VOLTAGE = 230.0  # Sri Lanka standard voltage

# ── Sri Lankan CEB domestic block tariff (2024 revision) ────────────
# Monthly consumption tiers + fixed charge
CEB_BLOCKS = [
    (30, 8),    # 0-30   units: LKR 8/unit
    (30, 10),   # 31-60  units: LKR 10/unit
    (30, 16),   # 61-90  units: LKR 16/unit
    (30, 50),   # 91-120 units: LKR 50/unit
    (60, 75),   # 121-180 units: LKR 75/unit
]
CEB_ABOVE_180_RATE = 75   # LKR/unit for >180 units
CEB_FIXED_CHARGE = 400.0  # LKR/month

# Typical daily runtime hours per device type without smart management
TYPICAL_DAILY_HOURS: Dict[str, float] = {
    "ac": 10, "air conditioner": 10,
    "refrigerator": 24, "fridge": 24,
    "water heater": 4, "heater": 4,
    "washing machine": 2,
    "light": 8, "lighting": 8,
    "fan": 12,
}
DEFAULT_DAILY_HOURS = 8.0


def _calculate_monthly_lkr(monthly_kwh: float) -> float:
    """Apply CEB domestic block tariff to monthly kWh and return LKR."""
    if monthly_kwh <= 0:
        return 0.0
    cost = 0.0
    remaining = monthly_kwh
    for block_size, rate in CEB_BLOCKS:
        if remaining <= 0:
            break
        units = min(remaining, block_size)
        cost += units * rate
        remaining -= units
    if remaining > 0:
        cost += remaining * CEB_ABOVE_180_RATE
    cost += CEB_FIXED_CHARGE
    return round(cost, 2)


def _kwh_to_lkr(kwh: float, period_days: float) -> float:
    """Convert kWh consumed over *period_days* to approximate LKR cost."""
    if kwh <= 0 or period_days <= 0:
        return 0.0
    monthly_kwh = kwh * (30.0 / period_days)
    monthly_cost = _calculate_monthly_lkr(monthly_kwh)
    return round(monthly_cost * (period_days / 30.0), 2)


# ── Timestamp helpers ───────────────────────────────────────────────

def _parse_ts(raw) -> Optional[datetime]:
    if isinstance(raw, datetime):
        return raw
    if isinstance(raw, str):
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except Exception:
            return None
    return None


def _get_timestamp(doc: dict) -> Optional[datetime]:
    for field in ("received_at", "receivedAt", "timestamp", "created_at"):
        val = doc.get(field)
        if val is not None:
            parsed = _parse_ts(val)
            if parsed is not None:
                return parsed
    return None


def _extract_current_a(doc: dict) -> float:
    if isinstance(doc.get("current_a"), (int, float)):
        return float(doc["current_a"])
    if isinstance(doc.get("current_ma"), (int, float)):
        return float(doc["current_ma"]) / 1000.0
    return 0.0


# ── Trapezoidal integration for a list of (ts, current_a) points ────

def _integrate_kwh(points: List[dict]) -> float:
    """Return kWh from sorted list of {"ts": datetime, "current": float}."""
    if len(points) < 2:
        return 0.0
    kwh = 0.0
    for i in range(1, len(points)):
        dt_s = (points[i]["ts"] - points[i - 1]["ts"]).total_seconds()
        if dt_s <= 0:
            continue
        capped = min(dt_s, 900)  # cap gaps to 15 min
        avg_a = (points[i - 1]["current"] + points[i]["current"]) / 2.0
        kwh += (avg_a * VOLTAGE) * (capped / 3600.0) / 1000.0
    return kwh


# ── Compute today's energy (used by /summary) ──────────────────────

def _compute_today_energy(readings: List[dict]) -> dict:
    if not readings:
        return {
            "total_kwh": 0.0, "estimated_cost_lkr": 0.0,
            "avg_power_w": 0.0, "peak_hour": "N/A", "readings_count": 0,
        }

    points = []
    hourly_power: Dict[int, List[float]] = {}
    for r in readings:
        ts = _get_timestamp(r)
        if ts is None:
            continue
        current_a = _extract_current_a(r)
        power_w = current_a * VOLTAGE
        points.append({"ts": ts, "current": current_a, "power_w": power_w})
        hourly_power.setdefault(ts.hour, []).append(power_w)

    if not points:
        return {
            "total_kwh": 0.0, "estimated_cost_lkr": 0.0,
            "avg_power_w": 0.0, "peak_hour": "N/A", "readings_count": 0,
        }

    points.sort(key=lambda x: x["ts"])
    kwh = _integrate_kwh(points)
    avg_power_w = sum(p["power_w"] for p in points) / len(points)

    peak_hour = "N/A"
    if hourly_power:
        peak_h = max(hourly_power, key=lambda h: sum(hourly_power[h]) / len(hourly_power[h]))
        end_h = (peak_h + 2) % 24

        def _fmt(h: int) -> str:
            if h == 0:
                return "12 AM"
            if h < 12:
                return f"{h} AM"
            if h == 12:
                return "12 PM"
            return f"{h - 12} PM"

        peak_hour = f"{_fmt(peak_h)} - {_fmt(end_h)}"

    return {
        "total_kwh": round(kwh, 2),
        "estimated_cost_lkr": _kwh_to_lkr(kwh, 1),
        "avg_power_w": round(avg_power_w, 1),
        "peak_hour": peak_hour,
        "readings_count": len(points),
    }


# ── Period helpers ──────────────────────────────────────────────────

def _period_range(period: str):
    """Return (start_dt, days_in_period, bucket_fmt)."""
    now = datetime.utcnow()
    if period == "week":
        start = (now - timedelta(days=7)).replace(hour=0, minute=0, second=0, microsecond=0)
        return start, 7, "day"
    if period == "month":
        start = (now - timedelta(days=30)).replace(hour=0, minute=0, second=0, microsecond=0)
        return start, 30, "day"
    # default = day
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return start, 1, "hour"


def _query_readings_since(start: datetime, limit: int = 10000) -> List[dict]:
    query = {
        "$or": [
            {"received_at": {"$gte": start}},
            {"receivedAt": {"$gte": start}},
            {"timestamp": {"$gte": start}},
        ]
    }
    return list(energy_col.find(query, {"_id": 0}).limit(limit))


def _bucket_key(ts: datetime, bucket_type: str) -> str:
    if bucket_type == "hour":
        return ts.strftime("%H")
    return ts.strftime("%Y-%m-%d")


def _bucket_label(key: str, bucket_type: str) -> str:
    if bucket_type == "hour":
        h = int(key)
        if h == 0:
            return "12AM"
        if h < 12:
            return f"{h}AM"
        if h == 12:
            return "12PM"
        return f"{h - 12}PM"
    # day label: "Mar 5"
    try:
        dt = datetime.strptime(key, "%Y-%m-%d")
        return dt.strftime("%b %d")
    except Exception:
        return key


# ── Baseline calculation ────────────────────────────────────────────

def _daily_baseline_kwh() -> float:
    """Sum of (rated_power × typical_hours / 1000) for every registered device."""
    devices = list(devices_col.find({}, {"_id": 0, "rated_power_watts": 1, "device_type": 1}))
    total = 0.0
    for d in devices:
        rated = d.get("rated_power_watts", 0)
        dtype = (d.get("device_type") or "").lower()
        hours = TYPICAL_DAILY_HOURS.get(dtype, DEFAULT_DAILY_HOURS)
        total += (rated * hours) / 1000.0
    return total


# ═══════════════════════════════════════════════════════════════════
# ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

@router.get("/summary")
def get_dashboard_summary():
    """Aggregated dashboard data for the mobile app."""

    # --- 1. Today's Energy ---
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    today_readings = _query_readings_since(today_start, limit=5000)
    today_energy = _compute_today_energy(today_readings)

    # --- 2. Predictions ---
    predictions = list(prediction_col.find({"prediction_type": "daily"}, {"_id": 0}))
    total_predicted_kwh = sum(p.get("predicted_energy_kwh", 0) for p in predictions)
    avg_confidence = (
        sum(p.get("confidence_score", 0) for p in predictions) / len(predictions)
        if predictions else 0
    )
    change_percent = 0.0
    if today_energy["total_kwh"] > 0:
        change_percent = round(
            ((total_predicted_kwh - today_energy["total_kwh"]) / today_energy["total_kwh"]) * 100, 1
        )

    prediction_data = {
        "total_predicted_kwh": round(total_predicted_kwh, 2),
        "estimated_cost_lkr": _kwh_to_lkr(total_predicted_kwh, 1),
        "change_percent": change_percent,
        "avg_confidence": round(avg_confidence, 2),
    }

    # --- 3. Active Anomalies ---
    anomalies_raw = list(anomalies_col.find({}, {"_id": 0}).sort("detected_at", -1).limit(10))
    anomalies = []
    for a in anomalies_raw:
        device = devices_col.find_one({"device_id": a.get("device_id")}, {"_id": 0})
        a["device_name"] = device.get("device_name", "Unknown") if device else "Unknown"
        a["device_type"] = device.get("device_type", "") if device else ""
        if isinstance(a.get("detected_at"), datetime):
            a["detected_at"] = a["detected_at"].isoformat()
        anomalies.append(a)

    # --- 4. Recommendations ---
    analytics_docs = list(
        analytics_col.find({}, {"_id": 0}).sort([("received_at", -1), ("_id", -1)]).limit(50)
    )
    recommendations = [r.dict() for r in _derive_recommendations(analytics_docs)]

    # --- 5. Devices with current usage ---
    devices = list(devices_col.find({}, {"_id": 0}))
    device_usage = []
    for d in devices:
        module_id = d.get("module_id")
        current_a = 0.0
        if module_id:
            latest = energy_col.find_one(
                {"module": module_id}, {"_id": 0},
                sort=[("received_at", -1), ("_id", -1)],
            )
            if latest:
                current_a = _extract_current_a(latest)
        current_power_w = current_a * VOLTAGE
        rated = d.get("rated_power_watts", 0)
        usage_pct = min((current_power_w / rated) if rated > 0 else 0.0, 1.0)

        if current_power_w > rated * 0.7 and rated > 0:
            status = "High"
        elif current_power_w > rated * 0.3 and rated > 0:
            status = "Medium"
        elif current_power_w > 0:
            status = "Normal"
        else:
            status = "Off"

        device_usage.append({
            "device_id": d.get("device_id"),
            "device_name": d.get("device_name"),
            "device_type": d.get("device_type"),
            "location": d.get("location"),
            "rated_power_watts": rated,
            "current_power_w": round(current_power_w, 1),
            "current_a": round(current_a, 4),
            "relay_state": d.get("relay_state", "OFF"),
            "usage_percentage": round(usage_pct, 2),
            "status": status,
        })
    device_usage.sort(key=lambda x: x["current_power_w"], reverse=True)

    # --- 6. Top device for behaviour comparison ---
    top_device = None
    active_devices = [d for d in device_usage if d["current_power_w"] > 0]
    if active_devices:
        top = max(active_devices, key=lambda d: d["usage_percentage"])
        rated_w = top["rated_power_watts"]
        current_w = top["current_power_w"]
        top_device = {
            "device_name": top["device_name"],
            "rated_power_w": rated_w,
            "current_power_w": current_w,
            "difference_percent": round(((current_w / rated_w) * 100), 0) if rated_w > 0 else 0,
        }

    return {
        "today_energy": today_energy,
        "prediction": prediction_data,
        "anomalies": anomalies,
        "recommendations": recommendations,
        "devices": device_usage,
        "top_anomaly_device": top_device,
    }


# ── Energy Chart Endpoint ───────────────────────────────────────────

@router.get("/energy-chart")
def get_energy_chart(
    period: str = Query("day", pattern="^(day|week|month)$"),
):
    """
    Time-series energy consumption data for charting.
    Returns bucketed actual kWh and the baseline comparison.
    """
    start, days, bucket_type = _period_range(period)
    raw_readings = _query_readings_since(start)

    # Parse into (ts, current_a) and assign to buckets
    buckets: Dict[str, List[dict]] = {}
    for r in raw_readings:
        ts = _get_timestamp(r)
        if ts is None or ts < start:
            continue
        current_a = _extract_current_a(r)
        key = _bucket_key(ts, bucket_type)
        buckets.setdefault(key, []).append({"ts": ts, "current": current_a})

    # Build all expected bucket keys
    all_keys = []
    if bucket_type == "hour":
        all_keys = [f"{h:02d}" for h in range(24)]
    else:
        d = start
        now = datetime.utcnow()
        while d <= now:
            all_keys.append(d.strftime("%Y-%m-%d"))
            d += timedelta(days=1)

    # Calculate kWh per bucket
    daily_baseline = _daily_baseline_kwh()
    chart_points = []
    for key in all_keys:
        pts = buckets.get(key, [])
        pts.sort(key=lambda p: p["ts"])
        actual_kwh = _integrate_kwh(pts) if len(pts) >= 2 else 0.0

        # Baseline per bucket
        if bucket_type == "hour":
            baseline_kwh = daily_baseline / 24.0
        else:
            baseline_kwh = daily_baseline

        chart_points.append({
            "key": key,
            "label": _bucket_label(key, bucket_type),
            "actual_kwh": round(actual_kwh, 3),
            "baseline_kwh": round(baseline_kwh, 3),
        })

    total_actual = sum(p["actual_kwh"] for p in chart_points)
    total_baseline = daily_baseline * days

    return {
        "period": period,
        "days": days,
        "points": chart_points,
        "total_actual_kwh": round(total_actual, 2),
        "total_baseline_kwh": round(total_baseline, 2),
    }


# ── Savings Endpoint ────────────────────────────────────────────────

@router.get("/savings")
def get_savings(
    period: str = Query("day", pattern="^(day|week|month)$"),
):
    """
    Compare baseline consumption (without smart management) vs actual,
    and return energy + monetary savings in LKR.
    """
    start, days, _ = _period_range(period)
    raw_readings = _query_readings_since(start)

    # Actual kWh
    points = []
    for r in raw_readings:
        ts = _get_timestamp(r)
        if ts is None or ts < start:
            continue
        points.append({"ts": ts, "current": _extract_current_a(r)})
    points.sort(key=lambda p: p["ts"])
    actual_kwh = _integrate_kwh(points)

    # Baseline kWh
    baseline_kwh = _daily_baseline_kwh() * days

    saved_kwh = max(baseline_kwh - actual_kwh, 0.0)

    baseline_lkr = _kwh_to_lkr(baseline_kwh, days)
    actual_lkr = _kwh_to_lkr(actual_kwh, days)
    saved_lkr = max(baseline_lkr - actual_lkr, 0.0)

    savings_pct = round((saved_kwh / baseline_kwh) * 100, 1) if baseline_kwh > 0 else 0.0

    # Tariff breakdown for transparency
    monthly_est = actual_kwh * (30.0 / days) if days > 0 else 0.0
    tier_label = "0-30"
    if monthly_est > 180:
        tier_label = ">180"
    elif monthly_est > 120:
        tier_label = "121-180"
    elif monthly_est > 90:
        tier_label = "91-120"
    elif monthly_est > 60:
        tier_label = "61-90"
    elif monthly_est > 30:
        tier_label = "31-60"

    return {
        "period": period,
        "days": days,
        "baseline_kwh": round(baseline_kwh, 2),
        "actual_kwh": round(actual_kwh, 2),
        "saved_kwh": round(saved_kwh, 2),
        "baseline_lkr": round(baseline_lkr, 2),
        "actual_lkr": round(actual_lkr, 2),
        "saved_lkr": round(saved_lkr, 2),
        "savings_percent": savings_pct,
        "monthly_estimate_kwh": round(monthly_est, 1),
        "current_tariff_tier": tier_label,
    }
