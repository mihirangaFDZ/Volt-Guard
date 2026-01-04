from typing import Optional

from fastapi import APIRouter, Depends, Query

from app.models.energy_model import EnergyReading
from database import energy_col
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/energy",
    tags=["Energy"],
    dependencies=[Depends(get_current_user)],
)

@router.post("/")
def add_energy(data: EnergyReading):
    """Store incoming current/energy telemetry."""
    energy_col.insert_one(data.dict(exclude_none=True))
    return {"message": "Energy data stored"}


def _timestamp_sort_fields():
    return [
        ("received_at", -1),
        ("receivedAt", -1),
        ("timestamp", -1),
        ("created_at", -1),
        ("_id", -1),
    ]


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
    return list(cursor)


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

    return list(energy_col.aggregate(pipeline))
