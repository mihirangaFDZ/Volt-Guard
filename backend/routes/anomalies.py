from fastapi import APIRouter
from database import anomaly_col
from app.models.anomaly_model import Anomaly

router = APIRouter(prefix="/anomalies", tags=["Anomalies"])

@router.post("/")
def add_anomaly(anomaly: Anomaly):
    anomaly_col.insert_one(anomaly.dict())
    return {"message": "Anomaly recorded"}

@router.get("/active")
def get_active_anomalies():
    return list(anomaly_col.find({"severity": "High"}, {"_id": 0}))
