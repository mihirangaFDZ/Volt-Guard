from typing import Optional
from fastapi import APIRouter, Depends
from database import analytics_col
from utils.jwt_handler import get_current_user

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
