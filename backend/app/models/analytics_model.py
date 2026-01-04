from typing import Optional
from datetime import datetime
from pydantic import BaseModel, Field
from enum import Enum
from typing import List


class SensorReading(BaseModel):
    module: str = Field(..., description="Module identifier")
    location: str = Field(..., description="Sensor location")
    rcwl: int = Field(..., ge=0, le=1, description="RCWL motion binary flag")
    pir: int = Field(..., ge=0, le=1, description="PIR motion binary flag")
    rssi: Optional[int] = Field(None, description="Signal strength dBm")
    uptime: Optional[int] = Field(None, description="Device uptime seconds")
    heap: Optional[int] = Field(None, description="Free heap bytes")
    ip: Optional[str] = Field(None, description="Device IP")
    mac: Optional[str] = Field(None, description="Device MAC")
    temperature: float = Field(..., description="Temperature in Celsius")
    humidity: float = Field(..., description="Relative humidity percentage")
    received_at: datetime = Field(..., description="Reading timestamp")
    source: Optional[str] = Field(None, description="Source identifier")

    class Config:
        json_encoders = {datetime: lambda v: v.isoformat()}
        allow_population_by_field_name = True


class RecommendationSeverity(str, Enum):
    low = "low"
    medium = "medium"
    high = "high"


class Recommendation(BaseModel):
    title: str
    detail: str
    cta: str
    severity: RecommendationSeverity = RecommendationSeverity.low


class RecommendationsResponse(BaseModel):
    recommendations: List[Recommendation] = []
    count: int = 0
