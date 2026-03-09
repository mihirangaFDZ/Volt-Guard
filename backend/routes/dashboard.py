from datetime import datetime, timedelta
from typing import Dict, List, Optional

from fastapi import APIRouter, Query
from pymongo.errors import NetworkTimeout, ServerSelectionTimeoutError

from database import energy_col, prediction_col, anomaly_col, devices_col, analytics_col, bills_col
from routes.analytics import _derive_recommendations

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


VOLTAGE = 230.0  # Sri Lanka standard voltage

# ── Sri Lankan CEB domestic tariff (30-day billing cycle) ──────────
# Ref: Official tariff table – Domestic 0–60 kWh and above 60 kWh tiers
# Energy charges (LKR/kWh) and fixed charges (LKR/month) by block

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
    """
    Apply CEB domestic tariff (30-day cycle) to monthly kWh; return LKR.
    Two-tier: 0–60 kWh (blocks 0–30 @ 4.50, 31–60 @ 8.00; fixed 80/210);
    above 60 kWh (blocks 0–60 @ 12.75, 61–90 @ 18.50, 91–120 @ 24.00,
    121–180 @ 41.00, >180 @ 61.00; fixed 400/1000/1500/2100 by highest block).
    """
    if monthly_kwh <= 0:
        return 0.0
    energy_cost = 0.0
    fixed_lkr = 0.0

    if monthly_kwh <= 60:
        # Tier 1: 0–60 kWh
        u1 = min(monthly_kwh, 30.0)
        u2 = max(monthly_kwh - 30.0, 0.0)
        energy_cost = u1 * 4.50 + u2 * 8.00
        fixed_lkr = 80.0 if monthly_kwh <= 30 else 210.0
    else:
        # Tier 2: above 60 kWh
        remaining = monthly_kwh
        energy_cost += min(remaining, 60.0) * 12.75
        remaining -= 60.0
        if remaining > 0:
            energy_cost += min(remaining, 30.0) * 18.50
            remaining -= 30.0
        if remaining > 0:
            energy_cost += min(remaining, 30.0) * 24.00
            remaining -= 30.0
        if remaining > 0:
            energy_cost += min(remaining, 60.0) * 41.00
            remaining -= 60.0
        if remaining > 0:
            energy_cost += remaining * 61.00
        if monthly_kwh <= 90:
            fixed_lkr = 400.0
        elif monthly_kwh <= 120:
            fixed_lkr = 1000.0
        elif monthly_kwh <= 180:
            fixed_lkr = 1500.0
        else:
            fixed_lkr = 2100.0

    return round(energy_cost + fixed_lkr, 2)


def _kwh_to_lkr(kwh: float, period_days: float) -> float:
    """Convert kWh consumed over *period_days* to approximate LKR cost."""
    if kwh <= 0 or period_days <= 0:
        return 0.0
    monthly_kwh = kwh * (30.0 / period_days)
    monthly_cost = _calculate_monthly_lkr(monthly_kwh)
    return round(monthly_cost * (period_days / 30.0), 2)


# ── Timestamp helpers ───────────────────────────────────────────────

def _parse_ts(raw) -> Optional[datetime]:
    """Parse timestamp from various DB formats: datetime, ISO string, $date dict, Unix seconds/ms."""
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw
    if isinstance(raw, str):
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except Exception:
            return None
    if isinstance(raw, dict) and "$date" in raw:
        d = raw["$date"]
        if isinstance(d, datetime):
            return d
        if isinstance(d, str):
            try:
                return datetime.fromisoformat(d.replace("Z", "+00:00"))
            except Exception:
                return None
    if isinstance(raw, (int, float)):
        try:
            secs = float(raw)
            if secs > 1e12:
                secs /= 1000.0
            return datetime.utcfromtimestamp(secs)
        except (ValueError, OSError):
            return None
    return None


def _get_timestamp(doc: dict) -> Optional[datetime]:
    """Extract first available timestamp from a document (any common field name)."""
    for field in ("received_at", "receivedAt", "timestamp", "created_at", "time", "date"):
        val = doc.get(field)
        if val is not None:
            parsed = _parse_ts(val)
            if parsed is not None:
                return parsed
    return None


def _doc_has_timestamp_in_range(doc: dict, start: datetime) -> bool:
    """True if document has any timestamp >= start."""
    ts = _get_timestamp(doc)
    return ts is not None and ts >= start


def _extract_current_a(doc: dict) -> float:
    """Extract current in Amperes from energy reading (current_a, current_ma, rms_a, or power_w)."""
    if isinstance(doc.get("current_a"), (int, float)):
        return float(doc["current_a"])
    if isinstance(doc.get("current_ma"), (int, float)):
        return float(doc["current_ma"]) / 1000.0
    if isinstance(doc.get("rms_a"), (int, float)):
        return float(doc["rms_a"])
    voltage = float(doc.get("voltage") or VOLTAGE) if isinstance(doc.get("voltage"), (int, float)) else VOLTAGE
    if isinstance(doc.get("power_w"), (int, float)) and float(doc["power_w"]) != 0 and voltage > 0:
        return float(doc["power_w"]) / voltage
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
    if kwh == 0.0 and len(points) == 1:
        # Single reading: estimate kWh for 1 hour so we display real data
        avg_power_w_single = points[0]["power_w"]
        kwh = (avg_power_w_single * 1.0) / 1000.0  # 1 hour
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


def _query_readings_since(start: datetime, limit: int = 10000, sort_newest_first: bool = False) -> List[dict]:
    """
    Fetch energy readings from DB with timestamp >= start.
    Tries MongoDB date query first; if no results, falls back to fetching recent docs
    and filtering in Python (handles string dates or different field names).
    If sort_newest_first=True, returns newest readings first (so limit keeps most recent); used for live today total.
    """
    # Primary: query by date on any of the common timestamp fields
    query = {
        "$or": [
            {"received_at": {"$gte": start}},
            {"receivedAt": {"$gte": start}},
            {"timestamp": {"$gte": start}},
            {"created_at": {"$gte": start}},
        ]
    }
    cursor = energy_col.find(query, {"_id": 0})
    if sort_newest_first:
        cursor = cursor.sort("_id", -1)
    readings = list(cursor.limit(limit))
    if readings:
        return readings
    # Fallback: fetch most recent documents and filter in Python (handles string dates / type mismatch)
    cursor = energy_col.find({}, {"_id": 0}).sort("_id", -1).limit(limit * 2)
    all_recent = list(cursor)
    filtered = [r for r in all_recent if _doc_has_timestamp_in_range(r, start)]
    return filtered[:limit]


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

def _upsert_daily_bill(date_str: str, total_kwh: float, total_bill_lkr: float, readings_count: int) -> dict:
    """Save or update daily bill in bills collection. Returns the saved bill doc (for API)."""
    now = datetime.utcnow()
    doc = {
        "date": date_str,
        "period_type": "daily",
        "total_kwh": round(total_kwh, 2),
        "total_bill_lkr": round(total_bill_lkr, 2),
        "readings_count": readings_count,
        "updated_at": now,
    }
    bills_col.update_one(
        {"date": date_str, "period_type": "daily"},
        {"$set": doc},
        upsert=True,
    )
    return {**doc, "saved_at": now.isoformat()}


def _summary_fallback(date_str: str) -> dict:
    """Return a minimal valid summary when MongoDB times out."""
    empty_energy = {
        "total_kwh": 0.0,
        "estimated_cost_lkr": 0.0,
        "avg_power_w": 0.0,
        "peak_hour": "N/A",
        "readings_count": 0,
    }
    return {
        "today_energy": empty_energy,
        "total_bill": {
            "date": date_str,
            "period_type": "daily",
            "total_kwh": 0.0,
            "total_bill_lkr": 0.0,
            "readings_count": 0,
            "saved_at": datetime.utcnow().isoformat(),
        },
        "prediction": {
            "total_predicted_kwh": 0.0,
            "estimated_cost_lkr": 0.0,
            "change_percent": 0.0,
            "avg_confidence": 0.0,
        },
        "anomalies": [],
        "recommendations": [],
        "devices": [],
        "top_anomaly_device": None,
        "database_timeout": True,
    }


def _get_live_data(date_str: str, today_start: datetime):
    """
    Compute today_energy, total_bill, devices (with current usage), top_anomaly_device.
    Used by /summary and /live so live updates don't need full summary.
    Uses sort_newest_first so the 5000 limit keeps the most recent readings and new ones are included.
    """
    today_readings = _query_readings_since(today_start, limit=5000, sort_newest_first=True)
    today_energy = _compute_today_energy(today_readings)
    total_bill = _upsert_daily_bill(
        date_str,
        today_energy["total_kwh"],
        today_energy["estimated_cost_lkr"],
        today_energy.get("readings_count", 0),
    )
    devices = list(devices_col.find({}, {"_id": 0}))
    device_usage = []
    for d in devices:
        module_id = d.get("module_id")
        location = d.get("location")
        current_a = 0.0
        latest = None
        if module_id:
            latest = energy_col.find_one(
                {"module": module_id}, {"_id": 0},
                sort=[("received_at", -1), ("receivedAt", -1), ("timestamp", -1), ("_id", -1)],
            )
            if latest is None:
                latest = energy_col.find_one(
                    {"module_id": module_id}, {"_id": 0},
                    sort=[("received_at", -1), ("timestamp", -1), ("_id", -1)],
                )
        if latest is None and location:
            latest = energy_col.find_one(
                {"location": location}, {"_id": 0},
                sort=[("received_at", -1), ("receivedAt", -1), ("timestamp", -1), ("_id", -1)],
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
        "total_bill": total_bill,
        "devices": device_usage,
        "top_anomaly_device": top_device,
    }


@router.get("/summary")
def get_dashboard_summary():
    """Aggregated dashboard data for the mobile app."""
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    date_str = today_start.strftime("%Y-%m-%d")

    try:
        live = _get_live_data(date_str, today_start)
        today_energy = live["today_energy"]
        total_bill = live["total_bill"]
        device_usage = live["devices"]
        top_device = live["top_anomaly_device"]

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

        # --- 3. Active Anomalies (from DB, enriched with device name/type by device_id, location, or module) ---
        anomalies_raw = list(anomaly_col.find({}, {"_id": 0}).sort("detected_at", -1).limit(10))
        anomalies = []
        for a in anomalies_raw:
            device = devices_col.find_one({"device_id": a.get("device_id")}, {"_id": 0})
            if not device and a.get("location"):
                device = devices_col.find_one({"location": a["location"]})
            if not device and a.get("module"):
                device = devices_col.find_one({"module_id": a["module"]}) or devices_col.find_one({"module": a["module"]})
            a["device_name"] = (device.get("device_name") if device else None) or a.get("device_name") or "Unknown"
            a["device_type"] = (device.get("device_type") if device else None) or a.get("device_type") or ""
            if isinstance(a.get("detected_at"), datetime):
                a["detected_at"] = a["detected_at"].isoformat()
            anomalies.append(a)

        # --- 4. Recommendations ---
        analytics_docs = list(
            analytics_col.find({}, {"_id": 0}).sort([("received_at", -1), ("_id", -1)]).limit(50)
        )
        recommendations = [r.dict() for r in _derive_recommendations(analytics_docs)]

        return {
            "today_energy": today_energy,
            "total_bill": total_bill,
            "prediction": prediction_data,
            "anomalies": anomalies,
            "recommendations": recommendations,
            "devices": device_usage,
            "top_anomaly_device": top_device,
        }
    except (NetworkTimeout, ServerSelectionTimeoutError):
        return _summary_fallback(date_str)


@router.get("/live")
def get_dashboard_live():
    """
    Lightweight live data: today_energy, total_bill, devices (with current usage), top_anomaly_device.
    Poll this for live updates without reloading charts/anomalies/recommendations.
    """
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    date_str = today_start.strftime("%Y-%m-%d")
    try:
        return _get_live_data(date_str, today_start)
    except (NetworkTimeout, ServerSelectionTimeoutError):
        return {
            "today_energy": {
                "total_kwh": 0.0,
                "estimated_cost_lkr": 0.0,
                "avg_power_w": 0.0,
                "peak_hour": "N/A",
                "readings_count": 0,
            },
            "total_bill": {
                "date": date_str,
                "period_type": "daily",
                "total_kwh": 0.0,
                "total_bill_lkr": 0.0,
                "readings_count": 0,
                "saved_at": datetime.utcnow().isoformat(),
            },
            "devices": [],
            "top_anomaly_device": None,
        }


# ── Energy Chart Endpoint ───────────────────────────────────────────

@router.get("/energy-chart")
def get_energy_chart(
    period: str = Query("day", pattern="^(day|week|month)$"),
):
    """
    Time-series energy consumption data for charting.
    Returns bucketed actual kWh from real readings and the baseline comparison.
    Uses newest-first so the chart includes the latest consumption data.
    """
    start, days, bucket_type = _period_range(period)
    raw_readings = _query_readings_since(start, limit=15000, sort_newest_first=True)

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

    # Calculate kWh per bucket (use integration when ≥2 points; else estimate from single reading)
    daily_baseline = _daily_baseline_kwh()
    chart_points = []
    bucket_hours = 1.0 / 24.0 if bucket_type == "hour" else 1.0
    for key in all_keys:
        pts = buckets.get(key, [])
        pts.sort(key=lambda p: p["ts"])
        if len(pts) >= 2:
            actual_kwh = _integrate_kwh(pts)
        elif len(pts) == 1:
            # Single reading: estimate kWh = power * bucket_duration (assumes constant over bucket)
            avg_a = pts[0]["current"]
            power_w = avg_a * VOLTAGE
            actual_kwh = (power_w * bucket_hours * 3600) / 3600.0 / 1000.0  # kWh
        else:
            actual_kwh = 0.0

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
