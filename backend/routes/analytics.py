from typing import Optional, List
from datetime import datetime
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
            doc["receivedAt"] = ts
        normalized.append(doc)

    return normalized


def _to_datetime(value):
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(str(value))
    except Exception:
        return None


def _derive_recommendations(docs: List[dict]) -> List[Recommendation]:
    if not docs:
        return []

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

    rcwl = latest.get("rcwl")
    pir = latest.get("pir")
    if rcwl == 1 and pir == 0:
        recs.append(
            Recommendation(
                title="Align motion sensing",
                detail="RCWL often 1 while PIR 0. Reposition sensor to reduce false motion.",
                cta="Inspect",
                severity=RecommendationSeverity.medium,
            )
        )

    if rssi_label != "Strong":
        recs.append(
            Recommendation(
                title="Check link quality",
                detail=f"RSSI {rssi_label}. Move gateway or adjust antenna.",
                cta="Check Link",
                severity=RecommendationSeverity.medium,
            )
        )

    if isinstance(temp_val, (int, float)):
        recs.append(
            Recommendation(
                title="Comfort guardrails",
                detail="Keep 24-27°C occupied; allow 29-30°C when vacant to save energy.",
                cta="Apply",
                severity=RecommendationSeverity.low,
            )
        )

    if avg_temp is not None and avg_hum is not None:
        recs.append(
            Recommendation(
                title="Review comfort drift",
                detail=f"Avg {avg_temp:.1f}°C / {avg_hum:.0f}% RH over last {len(docs)} readings.",
                cta="Review",
                severity=RecommendationSeverity.low,
            )
        )

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
