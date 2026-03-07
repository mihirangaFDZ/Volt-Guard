from fastapi import APIRouter, Depends
from database import anomalies_col
from app.models.anomaly_model import Anomaly
from utils.jwt_handler import get_current_user
from app.services.ownership import get_owner_user_id

router = APIRouter(
    prefix="/anomalies",
    tags=["Anomalies"],
    dependencies=[Depends(get_current_user)],
)

@router.post("/")
def add_anomaly(anomaly: Anomaly, current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)
    doc = anomaly.dict()
    doc["owner_user_id"] = owner_user_id
    anomalies_col.insert_one(doc)
    return {"message": "Anomaly recorded"}

@router.get("/active")
def get_active_anomalies(current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)
    return list(anomalies_col.find({"severity": "High", "owner_user_id": owner_user_id}, {"_id": 0}))
