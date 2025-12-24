from fastapi import APIRouter
from database import devices_col
from app.models.device_model import Device
router = APIRouter(prefix="/devices", tags=["Devices"])

@router.post("/")
def add_device(device: Device):
    devices_col.insert_one(device.dict())
    return {"message": "Device added successfully"}

@router.get("/")
def get_devices():
    return list(devices_col.find({}, {"_id": 0}))

@router.get("/{device_id}")
def get_device(device_id: str):
    return devices_col.find_one({"device_id": device_id}, {"_id": 0})
@router.delete("/{device_id}")
def delete_device(device_id: str):
    devices_col.delete_one({"device_id": device_id})
    return {"message": "Device removed"}
