from typing import Optional, List
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends
from database import analytics_col
from utils.jwt_handler import get_current_user
from app.models.analytics_model import (
    Recommendation,
    RecommendationSeverity,
    RecommendationsResponse,
)

router = APIRouter(
    prefix="/analytics",
    tags=["Analytics"],
    dependencies=[Depends(get_current_user)],
)

# Sri Lankan timezone (UTC+5:30)
SRI_LANKA_TZ = timezone(timedelta(hours=5, minutes=30))


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


@router.get("/latest")
def get_latest_readings(limit: int = 50, module: Optional[str] = None, location: Optional[str] = None):
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

    normalized = []
    for doc in cursor:
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
