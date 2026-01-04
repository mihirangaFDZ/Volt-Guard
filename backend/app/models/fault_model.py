from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field


class FaultSignal(BaseModel):
    name: str
    value: float
    unit: Optional[str] = None
    direction: Optional[str] = Field(None, description="up/down/flat")


class FaultRecommendation(BaseModel):
    short: str
    detail: Optional[str] = None
    priority: Optional[str] = Field(None, description="immediate/soon/monitor")


class Fault(BaseModel):
    fault_id: Optional[str] = None
    device_id: str
    device_name: Optional[str] = None
    module: Optional[str] = None
    location: Optional[str] = None
    issue: str
    severity: str = Field(..., pattern="^(Critical|High|Medium|Low)$")
    confidence: float = Field(..., ge=0, le=1)
    detected_at: datetime
    status: str = Field("active", pattern="^(active|acknowledged|resolved)$")
    recommendation: Optional[FaultRecommendation] = None
    signals: Optional[List[FaultSignal]] = None
    source: Optional[str] = None  # e.g., esp32, model:v1


class FaultSummary(BaseModel):
    total: int
    critical: int
    high: int
    medium: int
    low: int
    last_scan_at: Optional[datetime] = None
    next_scan_eta_seconds: Optional[int] = None