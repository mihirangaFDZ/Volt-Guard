from datetime import datetime, timedelta
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from database import devices_col, energy_col, anomaly_col
from app.models.device_model import Device, RelayStateUpdate
from utils.jwt_handler import get_current_user

router = APIRouter(prefix="/devices", tags=["Devices"])


@router.post("/")
def add_device(device: Device, current_user: dict = Depends(get_current_user)):
    # Validate module_id exists in energy_readings if provided
    if device.module_id:
        module_exists = energy_col.find_one({"module": device.module_id})
        if module_exists:
            raise HTTPException(
                status_code=400, 
                detail=f"Module {device.module_id} is in use by another device."
            )
    
    device_payload = device.dict()
    # Always bind devices to the authenticated user.
    device_payload["user_id"] = current_user["user_id"]
    devices_col.insert_one(device_payload)
    return {"message": "Device added successfully"}


@router.get("/")
def get_devices(
    location: Optional[str] = Query(None, description="Filter devices by location"),
    current_user: dict = Depends(get_current_user),
):
    query = {"user_id": current_user["user_id"]}
    if location:
        query["location"] = location
    return list(devices_col.find(query, {"_id": 0}))

@router.get("/{device_id}")
def get_device(device_id: str, current_user: dict = Depends(get_current_user)):
    return devices_col.find_one(
        {"device_id": device_id, "user_id": current_user["user_id"]},
        {"_id": 0},
    )

@router.get("/{device_id}/energy-readings")
def get_device_energy_readings(
    device_id: str, 
    limit: int = Query(1000, ge=1, le=10000),
    hours: Optional[int] = Query(None, ge=1, le=168),
    current_user: dict = Depends(get_current_user),
):
    """
    Get energy readings for a device through module_id relationship.
    Optionally filter by time range (hours parameter).
    """
    device = devices_col.find_one(
        {"device_id": device_id, "user_id": current_user["user_id"]},
        {"_id": 0},
    )
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
def update_device_module(
    device_id: str, module_id: str, current_user: dict = Depends(get_current_user)
):
    """
    Update or assign module_id to a device
    """
    device = devices_col.find_one(
        {"device_id": device_id, "user_id": current_user["user_id"]}
    )
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
        {"device_id": device_id, "user_id": current_user["user_id"]},
        {"$set": {"module_id": module_id}}
    )
    
    return {"message": f"Module {module_id} assigned to device {device_id}"}

@router.delete("/{device_id}")
def delete_device(device_id: str, current_user: dict = Depends(get_current_user)):
    devices_col.delete_one({"device_id": device_id, "user_id": current_user["user_id"]})
    return {"message": "Device removed"}


@router.put("/{device_id}/relay")
def update_relay_state(
    device_id: str, payload: RelayStateUpdate, current_user: dict = Depends(get_current_user)
):
    """
    Update the desired relay state for a device.
    Called by the Flutter app when user toggles the switch.
    """
    if payload.relay_state not in ("ON", "OFF"):
        raise HTTPException(status_code=400, detail="relay_state must be 'ON' or 'OFF'")

    device = devices_col.find_one(
        {"device_id": device_id, "user_id": current_user["user_id"]}
    )
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    devices_col.update_one(
        {"device_id": device_id, "user_id": current_user["user_id"]},
        {"$set": {"relay_state": payload.relay_state}}
    )

    return {
        "message": f"Relay state updated to {payload.relay_state}",
        "device_id": device_id,
        "relay_state": payload.relay_state,
    }


@router.get("/{device_id}/relay")
def get_relay_state(device_id: str, current_user: dict = Depends(get_current_user)):
    """
    Get the current desired relay state for a device.
    """
    device = devices_col.find_one(
        {"device_id": device_id, "user_id": current_user["user_id"]},
        {"_id": 0},
    )
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    return {
        "device_id": device_id,
        "relay_state": device.get("relay_state", "OFF"),
    }


# ---------------------------------------------------------------------------
# Anomaly-based auto shutoff (only when model detects abnormal power)
# ---------------------------------------------------------------------------

# Minimum anomaly score to allow auto shutoff (conservative: only clear anomalies)
ANOMALY_SHUTOFF_MIN_SCORE = 0.6
# Only consider anomalies detected in the last N minutes
ANOMALY_SHUTOFF_WINDOW_MINUTES = 10


@router.post("/{device_id}/check-anomaly-shutoff")
def check_anomaly_shutoff(device_id: str, current_user: dict = Depends(get_current_user)):
    """
    If the model has detected abnormal power consumption (High severity, score >= 0.6)
    for this device in the last 10 minutes, turn the relay OFF to protect the circuit.
    Returns whether auto-shutoff was performed. Does nothing if no anomaly or relay already OFF.
    """
    device = devices_col.find_one(
        {"device_id": device_id, "user_id": current_user["user_id"]},
        {"_id": 0},
    )
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    current_relay = device.get("relay_state", "OFF")
    if current_relay != "ON":
        return {"auto_shutoff": False, "reason": "Device is already OFF"}

    module_id = device.get("module_id") or ""
    cutoff = datetime.utcnow() - timedelta(minutes=ANOMALY_SHUTOFF_WINDOW_MINUTES)
    cutoff_iso = cutoff.isoformat()

    # Anomalies may be stored with device_id or location (module_id)
    query = {
        "$or": [
            {"device_id": device_id},
            {"location": device_id},
            {"location": module_id},
        ],
        "detected_at": {"$gte": cutoff_iso},
        "severity": "High",
    }
    recent = list(
        anomaly_col.find(query, {"anomaly_score": 1, "detected_at": 1}).sort(
            "detected_at", -1
        )
    )

    for doc in recent:
        score = doc.get("anomaly_score") or 0
        if score >= ANOMALY_SHUTOFF_MIN_SCORE:
            devices_col.update_one(
                {"device_id": device_id, "user_id": current_user["user_id"]},
                {"$set": {"relay_state": "OFF"}},
            )
            return {
                "auto_shutoff": True,
                "reason": "Abnormal power consumption detected by model",
                "anomaly_score": round(score, 3),
                "detected_at": doc.get("detected_at"),
            }

    return {"auto_shutoff": False, "reason": "No qualifying anomaly in window"}


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
