from typing import Optional

from fastapi import APIRouter, Depends, Query

from database import devices_col
from app.models.device_model import Device
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/devices",
    tags=["Devices"],
    dependencies=[Depends(get_current_user)],
)

@router.post("/")
def add_device(device: Device):
    if devices_col.find_one({"device_id": device.device_id}):
        return {"message": "Device with this id already exists"}

    devices_col.insert_one(device.dict())
    return {"message": "Device added successfully"}

@router.get("/")
def get_devices(location: Optional[str] = Query(None, description="Filter devices by location")):
    query = {"location": location} if location else {}
    return list(devices_col.find(query, {"_id": 0}))

@router.get("/{device_id}")
def get_device(device_id: str):
    return devices_col.find_one({"device_id": device_id}, {"_id": 0})
@router.delete("/{device_id}")
def delete_device(device_id: str):
    devices_col.delete_one({"device_id": device_id})
    return {"message": "Device removed"}
