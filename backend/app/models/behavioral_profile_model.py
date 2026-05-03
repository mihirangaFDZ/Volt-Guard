# backend/app/models/behavioral_profile_model.py
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime


class HourlyUsage(BaseModel):
    hour: int
    avg_power_w: float


class DeviceBehavioralProfile(BaseModel):
    device_id: str
    device_name: str
    device_type: str
    location: str
    rated_power_watts: int
    avg_power_occupied: float
    avg_power_vacant: float
    standby_ratio: float
    hourly_profile: List[HourlyUsage]
    energy_waste_kwh: float
    is_energy_vampire: bool
    vampire_severity: Optional[str] = None
    total_readings: int
    vacant_readings: int
    analysis_period_hours: int
    generated_at: datetime
