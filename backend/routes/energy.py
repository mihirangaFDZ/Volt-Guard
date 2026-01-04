from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from database import energy_col
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/energy",
    tags=["Energy"],
    dependencies=[Depends(get_current_user)],
)


def _normalize_reading(doc: Dict[str, Any]) -> Dict[str, Any]:
    """Ensure consistent field names and types for frontend consumption."""
    result = dict(doc)

    # Convert ObjectId to string for JSON compatibility
    if result.get("_id") is not None:
        result["_id"] = str(result["_id"])

    # Standardize timestamps
    result["received_at"] = (
        result.get("received_at")
        or result.get("receivedAt")
        or result.get("timestamp")
        or result.get("created_at")
    )

    # Normalize current fields
    current_a = result.get("current_a")
    current_ma = result.get("current_ma")

    if current_a is None and current_ma is not None:
        try:
            current_a = float(current_ma) / 1000.0
        except (TypeError, ValueError):
            current_a = None

    if current_a is not None:
        try:
            result["current_a"] = float(current_a)
        except (TypeError, ValueError):
            result["current_a"] = None

    return result


@router.post("/")
def add_energy(data: Dict[str, Any]):
    """Store an energy reading as-is (accepts flexible payloads)."""
    insert_result = energy_col.insert_one(data)
    return {"message": "Energy data stored", "id": str(insert_result.inserted_id)}


@router.get("/readings")
def get_energy_readings(
    location: Optional[str] = Query(None, description="Filter by location"),
    module: Optional[str] = Query(None, description="Filter by module"),
    limit: int = Query(50, ge=1, le=500, description="Number of rows to return"),
):
    """Return energy readings filtered by location/module, newest first."""
    query: Dict[str, Any] = {}
    if location:
        query["location"] = location
    if module:
        query["module"] = module

    cursor = (
        energy_col
        .find(query)
        .sort([("received_at", -1), ("timestamp", -1), ("_id", -1)])
        .limit(limit)
    )

    return [_normalize_reading(doc) for doc in cursor]


@router.get("/current-power")
def get_current_power():
    """Return the latest current reading per location/module pair."""
    pipeline = [
        {"$sort": {"received_at": -1, "timestamp": -1, "_id": -1}},
        {"$group": {"_id": {"location": "$location", "module": "$module"}, "doc": {"$first": "$$ROOT"}}},
    ]

    results: List[Dict[str, Any]] = []
    for row in energy_col.aggregate(pipeline):
        doc = _normalize_reading(row.get("doc", {}))
        results.append(
            {
                "location": doc.get("location"),
                "module": doc.get("module"),
                "current_a": doc.get("current_a"),
                "current_ma": doc.get("current_ma"),
                "received_at": doc.get("received_at"),
                "sensor": doc.get("sensor"),
                "source": doc.get("source"),
            }
        )

    return results


@router.get("/locations")
def get_energy_locations():
    """List distinct locations that have energy readings."""
    locations = [loc for loc in energy_col.distinct("location") if loc]
    return sorted(locations)


@router.get("/latest")
def get_latest_energy(limit: int = Query(10, ge=1, le=200)):
    """Return the latest raw readings (legacy endpoint)."""
    cursor = (
        energy_col
        .find({}, {"_id": 0})
        .sort([("received_at", -1), ("timestamp", -1), ("_id", -1)])
        .limit(limit)
    )
    return list(cursor)
