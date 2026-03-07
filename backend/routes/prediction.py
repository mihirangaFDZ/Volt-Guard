from fastapi import APIRouter, Depends
from database import prediction_col
from app.models.prediction_model import Prediction
from datetime import datetime
from utils.jwt_handler import get_current_user
from app.services.ownership import get_owner_user_id

router = APIRouter(
    prefix="/prediction",
    tags=["Prediction"],
    dependencies=[Depends(get_current_user)],
)

@router.post("/")
def save_prediction(prediction: Prediction, current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)
    doc = prediction.dict()
    doc["created_at"] = datetime.now()
    doc["owner_user_id"] = owner_user_id
    prediction_col.insert_one(doc)
    return {"message": "Prediction saved"}

@router.get("/daily")
def get_daily_predictions(current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)
    return list(prediction_col.find({"prediction_type": "daily", "owner_user_id": owner_user_id}, {"_id": 0}))
