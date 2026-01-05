from datetime import datetime
from typing import Optional, List, Dict

from fastapi import APIRouter, Depends, Query, HTTPException

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
