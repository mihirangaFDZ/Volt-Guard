from fastapi import APIRouter
from database import prediction_col
from app.models.prediction_model import Prediction
from datetime import datetime

router = APIRouter(prefix="/prediction", tags=["Prediction"])

@router.post("/")
def save_prediction(prediction: Prediction):
    doc = prediction.dict()
    doc["created_at"] = datetime.now()
    prediction_col.insert_one(doc)
    return {"message": "Prediction saved"}

@router.get("/daily")
def get_daily_predictions():
    return list(prediction_col.find({"prediction_type": "daily"}, {"_id": 0}))
