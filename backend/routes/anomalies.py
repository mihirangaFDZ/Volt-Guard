from fastapi import APIRouter, Depends
from database import anomaly_col
from app.models.anomaly_model import Anomaly
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/anomalies",
    tags=["Anomalies"],
    dependencies=[Depends(get_current_user)],
)

@router.post("/")
def add_anomaly(anomaly: Anomaly):
    anomaly_col.insert_one(anomaly.dict())
    return {"message": "Anomaly recorded"}

@router.get("/active")
def get_active_anomalies():
    return list(anomaly_col.find({"severity": "High"}, {"_id": 0}))
