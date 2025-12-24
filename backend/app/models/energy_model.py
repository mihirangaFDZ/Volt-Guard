from pydantic import BaseModel
from datetime import datetime

class EnergyReading(BaseModel):
    device_id: str
    voltage: float
    current: float
    power_kwh: float
    occupancy: bool
    temperature: float
    timestamp: datetime
