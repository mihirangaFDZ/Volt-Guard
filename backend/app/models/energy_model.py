from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class EnergyReading(BaseModel):
    """Flexible energy/current telemetry payload from ACS712 devices."""

    module: Optional[str] = Field(None, description="Hardware module identifier")
    location: str = Field(..., description="Logical room/location identifier")
    sensor: Optional[str] = Field(None, description="Sensor type/model, e.g., ACS712-20A")
    current_ma: Optional[float] = Field(None, description="Current in milliamps")
    current_a: Optional[float] = Field(None, description="Current in amps")
    rms_a: Optional[float] = Field(None, description="RMS current in amps")
    adc_samples: Optional[int] = Field(None, description="Sample count used for reading")
    vref: Optional[float] = Field(None, description="Reference voltage used for ADC")
    wifi_rssi: Optional[int] = Field(None, description="WiFi signal strength")
    received_at: Optional[datetime] = Field(None, description="Timestamp from device")
    source: Optional[str] = Field(None, description="Source identifier, e.g., esp32")
    type: Optional[str] = Field(None, description="Reading type, e.g., current")

    class Config:
        extra = "allow"
        json_encoders = {datetime: lambda v: v.isoformat()}
