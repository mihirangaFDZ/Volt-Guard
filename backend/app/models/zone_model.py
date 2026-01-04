from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class ZoneSummary(BaseModel):
    location: str = Field(..., description="Sensor-reported location name")
    module: Optional[str] = Field(None, description="Hardware module identifier")
    occupancy: bool = Field(..., description="True when either RCWL or PIR reports motion")
    rcwl: int = Field(..., ge=0, le=1, description="RCWL motion flag")
    pir: int = Field(..., ge=0, le=1, description="PIR motion flag")
    temperature: Optional[float] = Field(None, description="Temperature in Celsius")
    humidity: Optional[float] = Field(None, description="Relative humidity percentage")
    last_seen: datetime = Field(..., description="Latest timestamp for this location")
    source: Optional[str] = Field(None, description="Telemetry source identifier")
    current_a: Optional[float] = Field(None, description="Latest measured current (A)")
    current_ma: Optional[float] = Field(None, description="Latest measured current (mA)")
    power_w: Optional[float] = Field(None, description="Approximate instantaneous power in watts")
    energy_received_at: Optional[datetime] = Field(None, description="Timestamp of the latest energy reading")

    class Config:
        json_encoders = {datetime: lambda v: v.isoformat()}


class ZoneDetail(BaseModel):
    latest: ZoneSummary
    history: List[dict] = Field(..., description="Recent raw telemetry rows for the location")
    latest_energy: Optional[dict] = Field(None, description="Latest energy/current reading for the location")
    energy_history: List[dict] = Field(default_factory=list, description="Recent energy readings for the location")

    class Config:
        json_encoders = {datetime: lambda v: v.isoformat()}
