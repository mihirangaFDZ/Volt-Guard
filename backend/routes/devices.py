from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from database import devices_col, energy_col
from app.models.device_model import Device
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/devices",
    tags=["Devices"],
    dependencies=[Depends(get_current_user)],
)

@router.post("/")
def add_device(device: Device):
    # Validate module_id exists in energy_readings if provided
    if device.module_id:
        module_exists = energy_col.find_one({"module": device.module_id})
        if module_exists:
            raise HTTPException(
                status_code=400, 
                detail=f"Module {device.module_id} is in use by another device."
            )
    
    devices_col.insert_one(device.dict())
    return {"message": "Device added successfully"}


@router.get("/")
def get_devices():
    return list(devices_col.find({}, {"_id": 0}))

@router.get("/{device_id}")
def get_device(device_id: str):
    return devices_col.find_one({"device_id": device_id}, {"_id": 0})

@router.get("/{device_id}/energy-readings")
def get_device_energy_readings(
    device_id: str, 
    limit: int = Query(1000, ge=1, le=10000),
    hours: Optional[int] = Query(None, ge=1, le=168)
):
    """
    Get energy readings for a device through module_id relationship.
    Optionally filter by time range (hours parameter).
    """
    device = devices_col.find_one({"device_id": device_id}, {"_id": 0})
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    
    module_id = device.get("module_id")
    if not module_id:
        return {"message": "Device has no module_id assigned", "readings": []}
    
    # Build query
    query = {"module": module_id}
    
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
def update_device_module(device_id: str, module_id: str):
    """
    Update or assign module_id to a device
    """
    device = devices_col.find_one({"device_id": device_id})
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    
    # Validate module exists
    module_exists = energy_col.find_one({"module": module_id})
    if not module_exists:
        raise HTTPException(  # pyright: ignore[reportUndefinedVariable]
            status_code=400,
            detail=f"Module {module_id} not found in energy_readings"
        )
    
    devices_col.update_one(
        {"device_id": device_id},
        {"$set": {"module_id": module_id}}
    )
    
    return {"message": f"Module {module_id} assigned to device {device_id}"}

@router.delete("/{device_id}")
def delete_device(device_id: str):
    devices_col.delete_one({"device_id": device_id})
    return {"message": "Device removed"}
