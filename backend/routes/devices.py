from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pymongo.errors import DuplicateKeyError
from database import devices_col, energy_col
from app.models.device_model import Device, RelayStateUpdate
from utils.jwt_handler import get_current_user
from app.services.ownership import get_owner_user_id

router = APIRouter(
    prefix="/devices",
    tags=["Devices"],
    dependencies=[Depends(get_current_user)],
)

@router.post("/")
def add_device(device: Device, current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)

    if devices_col.find_one({"owner_user_id": owner_user_id, "device_id": device.device_id}):
        raise HTTPException(status_code=409, detail="Device ID already exists for this user")

    doc = device.dict(exclude_none=True)
    doc["owner_user_id"] = owner_user_id

    try:
        devices_col.insert_one(doc)
    except DuplicateKeyError as exc:
        raise HTTPException(status_code=409, detail="Device already exists") from exc

    return {"message": "Device added successfully"}


@router.get("/")
def get_devices(
    location: Optional[str] = Query(None, description="Filter devices by location"),
    current_user=Depends(get_current_user),
):
    owner_user_id = get_owner_user_id(current_user)
    query = {"owner_user_id": owner_user_id}
    if location:
        query["location"] = location
    return list(devices_col.find(query, {"_id": 0}))

@router.get("/{device_id}")
def get_device(device_id: str, current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)
    device = devices_col.find_one({"device_id": device_id, "owner_user_id": owner_user_id}, {"_id": 0})
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    return device

@router.get("/{device_id}/energy-readings")
def get_device_energy_readings(
    device_id: str, 
    limit: int = Query(1000, ge=1, le=10000),
    hours: Optional[int] = Query(None, ge=1, le=168),
    current_user=Depends(get_current_user),
):
    """
    Get energy readings for a device through module_id relationship.
    Optionally filter by time range (hours parameter).
    """
    owner_user_id = get_owner_user_id(current_user)
    device = devices_col.find_one({"device_id": device_id, "owner_user_id": owner_user_id}, {"_id": 0})
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    
    module_id = device.get("module_id")
    if not module_id:
        return {"message": "Device has no module_id assigned", "readings": []}
    
    # Build query
    query = {"module": module_id, "owner_user_id": owner_user_id}
    
    # Add time range filter if hours is provided
    if hours is not None:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        query["received_at"] = {"$gte": start_time, "$lte": end_time}
    
    # Query energy_readings by module
    readings = list(
        energy_col.find(
            query,
            {"_id": 0}
        ).sort("received_at", -1).limit(limit)
    )
    
    return {
        "device_id": device_id,
        "module_id": module_id,
        "readings": readings,
        "count": len(readings)
    }

@router.put("/{device_id}/module")
def update_device_module(device_id: str, module_id: str, current_user=Depends(get_current_user)):
    """
    Update or assign module_id to a device
    """
    owner_user_id = get_owner_user_id(current_user)
    device = devices_col.find_one({"device_id": device_id, "owner_user_id": owner_user_id})
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    devices_col.update_one(
        {"device_id": device_id, "owner_user_id": owner_user_id},
        {"$set": {"module_id": module_id}}
    )
    
    return {"message": f"Module {module_id} assigned to device {device_id}"}

@router.delete("/{device_id}")
def delete_device(device_id: str, current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)
    result = devices_col.delete_one({"device_id": device_id, "owner_user_id": owner_user_id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Device not found")
    return {"message": "Device removed"}


@router.put("/{device_id}/relay")
def update_relay_state(device_id: str, payload: RelayStateUpdate, current_user=Depends(get_current_user)):
    """
    Update the desired relay state for a device.
    Called by the Flutter app when user toggles the switch.
    """
    if payload.relay_state not in ("ON", "OFF"):
        raise HTTPException(status_code=400, detail="relay_state must be 'ON' or 'OFF'")

    owner_user_id = get_owner_user_id(current_user)
    device = devices_col.find_one({"device_id": device_id, "owner_user_id": owner_user_id})
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    devices_col.update_one(
        {"device_id": device_id, "owner_user_id": owner_user_id},
        {"$set": {"relay_state": payload.relay_state}}
    )

    return {
        "message": f"Relay state updated to {payload.relay_state}",
        "device_id": device_id,
        "relay_state": payload.relay_state,
    }


@router.get("/{device_id}/relay")
def get_relay_state(device_id: str, current_user=Depends(get_current_user)):
    """
    Get the current desired relay state for a device.
    """
    owner_user_id = get_owner_user_id(current_user)
    device = devices_col.find_one({"device_id": device_id, "owner_user_id": owner_user_id}, {"_id": 0})
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    return {
        "device_id": device_id,
        "relay_state": device.get("relay_state", "OFF"),
    }


# ── ESP32 public router (no JWT auth) ──────────────────────────────────
esp32_router = APIRouter(
    prefix="/esp32",
    tags=["ESP32"],
)


@esp32_router.get("/relay-status/{module_id}")
def get_relay_status_by_module(module_id: str):
    """
    ESP32 polls this endpoint to get the desired relay state by module_id.
    No authentication required.
    """
    device = devices_col.find_one({"module_id": module_id}, {"_id": 0})
    if not device:
        raise HTTPException(status_code=404, detail="No device found with this module_id")

    return {
        "module_id": module_id,
        "device_id": device.get("device_id"),
        "relay_state": device.get("relay_state", "OFF"),
    }
