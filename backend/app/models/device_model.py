from datetime import date, datetime
from typing import Optional, Union

from pydantic import BaseModel, Field


class Device(BaseModel):
    device_id: str
    device_name: str
    device_type: str
    location: Optional[str] = Field(None, description="Logical zone/location where the device is installed")
    rated_power_watts: int = Field(..., ge=0, description="Rated power draw in watts")
    installed_date: Optional[Union[date, datetime, str]] = Field(
        None, description="Install date; accepts YYYY-MM-DD or ISO datetime"
    )

    class Config:
        json_encoders = {
            date: lambda v: v.isoformat(),
            datetime: lambda v: v.isoformat(),
        }
