from pydantic import BaseModel

class Device(BaseModel):
    device_id: str
    device_name: str
    device_type: str
    location: str
    rated_power_watts: int
