from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from app.models.device_model import Device
from app.models.zone_model import ZoneDetail, ZoneSummary
from database import analytics_col, devices_col, energy_col
from utils.jwt_handler import get_current_user
import os

router = APIRouter(
    prefix="/zones",
    tags=["Zones"],
    dependencies=[Depends(get_current_user)],
)


def _get_timestamp(doc: Dict[str, Any]):
    """Return the best available timestamp field from a telemetry row."""
    return doc.get("received_at") or doc.get("receivedAt") or doc.get("timestamp") or doc.get("created_at")


def _get_energy_timestamp(doc: Dict[str, Any]):
    return doc.get("received_at") or doc.get("receivedAt") or doc.get("timestamp") or doc.get("created_at")


def _to_energy_map(match: Dict[str, Any]):
    """Return a map of location -> latest energy row."""
    pipeline = []
    if match:
        pipeline.append({"$match": match})

    pipeline.extend(
        [
            {"$sort": {"received_at": -1, "receivedAt": -1, "timestamp": -1, "created_at": -1, "_id": -1}},
            {"$group": {"_id": "$location", "doc": {"$first": "$$ROOT"}}},
        ]
    )

    energy_map: Dict[str, Dict[str, Any]] = {}
    for row in energy_col.aggregate(pipeline):
        loc = row.get("_id")
        doc = row.get("doc")
        if loc and doc:
            energy_map[loc] = doc
    return energy_map


def _derive_power_w(row: Dict[str, Any]):
    current_a = row.get("current_a")
    if current_a is None:
        return None
    voltage = row.get("voltage") or float(os.getenv("ENERGY_VOLTAGE_DEFAULT", "230"))
    try:
        return float(current_a) * float(voltage)
    except Exception:
        return None


def _to_summary(doc: Dict[str, Any], energy: Optional[Dict[str, Any]] = None) -> ZoneSummary:
    timestamp = _get_timestamp(doc)
    if timestamp is None:
        raise HTTPException(status_code=500, detail="Telemetry row missing timestamp")

    current_a = None
    current_ma = None
    power_w = None
    energy_ts = None
    if energy:
        current_a = energy.get("current_a") or (energy.get("current_ma") / 1000 if energy.get("current_ma") else None)
        current_ma = energy.get("current_ma")
        power_w = energy.get("power_w") or _derive_power_w({"current_a": current_a, "voltage": energy.get("voltage")})
        energy_ts = _get_energy_timestamp(energy)

    return ZoneSummary(
        location=doc.get("location", "unknown"),
        module=doc.get("module"),
        occupancy=bool(doc.get("rcwl", 0) or doc.get("pir", 0)),
        rcwl=int(doc.get("rcwl", 0)),
        pir=int(doc.get("pir", 0)),
        temperature=doc.get("temperature"),
        humidity=doc.get("humidity"),
        last_seen=timestamp,
        source=doc.get("source"),
        current_a=current_a,
        current_ma=current_ma,
        power_w=power_w,
        energy_received_at=energy_ts,
    )


@router.post("/{location}/devices")
def add_device_to_zone(location: str, device: Device):
    """Attach a device to a zone (location), ensuring device_id uniqueness."""
    if device.location and device.location != location:
        raise HTTPException(status_code=400, detail="Device location mismatch with path")

    if devices_col.find_one({"device_id": device.device_id}):
        raise HTTPException(status_code=409, detail="Device with this id already exists")

    if device.rated_power_watts is None:
        raise HTTPException(status_code=400, detail="rated_power_watts is required")

    doc = device.dict(exclude_unset=True)
    doc["location"] = location
    devices_col.insert_one(doc)
    return {"message": "Device added to zone", "device_id": device.device_id, "location": location}


@router.get("/", response_model=List[ZoneSummary])
def list_zones(module: Optional[str] = None):
    """Return one consolidated row per location from occupancy_telemetry."""
    match: Dict[str, Any] = {}
    if module:
        match["module"] = module

    energy_map = _to_energy_map(match if module else {})

    pipeline = []
    if match:
        pipeline.append({"$match": match})

    pipeline.extend(
        [
            {"$sort": {"received_at": -1, "receivedAt": -1, "timestamp": -1, "_id": -1}},
            {"$group": {"_id": "$location", "doc": {"$first": "$$ROOT"}}},
        ]
    )

    results = analytics_col.aggregate(pipeline)
    summaries: List[ZoneSummary] = []
    for row in results:
        doc = row.get("doc") or {}
        loc = doc.get("location")
        energy = energy_map.get(loc)
        summaries.append(_to_summary(doc, energy))

    return summaries


@router.get("/{location}", response_model=ZoneDetail)
def get_zone_detail(
    location: str,
    module: Optional[str] = None,
    limit: int = Query(50, ge=1, le=500, description="Number of history rows to return"),
):
    """Return latest reading and recent history for a specific location."""
    query: Dict[str, Any] = {"location": location}
    if module:
        query["module"] = module

    latest_cursor = (
        analytics_col
        .find(query)
        .sort([("received_at", -1), ("receivedAt", -1), ("timestamp", -1), ("_id", -1)])
        .limit(1)
    )
    latest = next(latest_cursor, None)

    if latest is None:
        raise HTTPException(status_code=404, detail="Location not found")

    history_cursor = (
        analytics_col
        .find(query, {"_id": 0})
        .sort([("received_at", -1), ("receivedAt", -1), ("timestamp", -1), ("_id", -1)])
        .limit(limit)
    )

    history = list(history_cursor)

    energy_query: Dict[str, Any] = {"location": location}
    if module:
        energy_query["module"] = module

    energy_latest_cursor = (
        energy_col
        .find(energy_query)
        .sort([("received_at", -1), ("receivedAt", -1), ("timestamp", -1), ("created_at", -1), ("_id", -1)])
        .limit(1)
    )
    latest_energy = next(energy_latest_cursor, None)

    energy_history_cursor = (
        energy_col
        .find(energy_query, {"_id": 0})
        .sort([("received_at", -1), ("receivedAt", -1), ("timestamp", -1), ("created_at", -1), ("_id", -1)])
        .limit(limit)
    )
    energy_history = list(energy_history_cursor)

    return ZoneDetail(
        latest=_to_summary(latest, latest_energy),
        history=history,
        latest_energy=latest_energy,
        energy_history=energy_history,
    )

