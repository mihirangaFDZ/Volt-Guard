from pydantic import BaseModel
from typing import Optional

class Device(BaseModel):
    device_id: str
    device_name: str
    device_type: str
    location: str
    rated_power_watts: int
    module_id: Optional[str] = None  # Reference to module in energy_readings
    installed_date: Optional[str] = None
