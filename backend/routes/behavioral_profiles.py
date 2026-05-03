# backend/routes/behavioral_profiles.py
"""
API endpoints for device behavioral profiling and energy vampire detection.
"""
from fastapi import APIRouter, Depends, Query, HTTPException
from typing import Optional
from utils.jwt_handler import get_current_user
import sys
from pathlib import Path

# Add backend directory to path
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from app.services.behavioral_profile_service import BehavioralProfileService

router = APIRouter(
    prefix="/behavioral-profiles",
    tags=["Behavioral Profiles"],
    dependencies=[Depends(get_current_user)],
)

# Lazy-loaded service
_service = None

def get_service():
    global _service
    if _service is None:
        _service = BehavioralProfileService()
    return _service


@router.get("/")
def get_all_profiles(
    hours_back: int = Query(168, ge=1, le=720, description="Analysis window in hours (default 7 days)"),
    location: Optional[str] = Query(None, description="Filter by location"),
):
    """
    Build and return behavioral profiles for all registered devices.

    Each profile includes occupied vs vacant power consumption,
    hourly usage breakdown, energy waste estimate, and energy vampire flag.
    """
    try:
        service = get_service()
        profiles = service.build_all_profiles(hours_back=hours_back, location=location)

        return {
            "total_devices": len(profiles),
            "analysis_period_hours": hours_back,
            "location": location,
            "profiles": profiles,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to build profiles: {str(e)}")


@router.get("/energy-vampires")
def get_energy_vampires(
    hours_back: int = Query(168, ge=1, le=720, description="Analysis window in hours (default 7 days)"),
    location: Optional[str] = Query(None, description="Filter by location"),
):
    """
    Return devices flagged as energy vampires.

    An energy vampire is a device that:
    - Draws more than 5W when the room is vacant
    - Has a standby ratio above 10% of its rated power

    Severity levels:
    - High: standby ratio > 30%
    - Medium: standby ratio > 10%
    """
    try:
        service = get_service()
        vampires = service.get_energy_vampires(hours_back=hours_back, location=location)

        total_waste = sum(v["energy_waste_kwh"] for v in vampires)

        return {
            "total_vampires": len(vampires),
            "total_energy_waste_kwh": round(total_waste, 4),
            "analysis_period_hours": hours_back,
            "location": location,
            "vampires": vampires,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to detect energy vampires: {str(e)}")


@router.get("/{device_id}")
def get_device_profile(
    device_id: str,
    hours_back: int = Query(168, ge=1, le=720, description="Analysis window in hours (default 7 days)"),
):
    """
    Build and return the behavioral profile for a single device.
    """
    try:
        service = get_service()
        profile = service.build_profile(device_id=device_id, hours_back=hours_back)

        if profile is None:
            raise HTTPException(
                status_code=404,
                detail=f"No profile could be built for device '{device_id}'. "
                       "Ensure the device exists, has a module assigned, and has recent energy data."
            )

        return profile
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to build profile: {str(e)}")
