from pydantic import BaseModel
from datetime import datetime

class Anomaly(BaseModel):
    device_id: str
    anomaly_type: str
    severity: str
    description: str
    detected_at: datetime
