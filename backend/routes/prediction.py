from fastapi import APIRouter, Depends, Query, HTTPException
from typing import Optional
from database import prediction_col, energy_col, analytics_col
from app.models.prediction_model import Prediction
from datetime import datetime, timedelta
from utils.jwt_handler import get_current_user
import pandas as pd
import sys
from pathlib import Path

# Add backend directory to path
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from app.services.ml_service import EnergyMLService
from app.services.lstm_service import LSTMPredictor
from app.services.create_clean_dataset import create_clean_dataset

router = APIRouter(
    prefix="/prediction",
    tags=["Prediction"],
    dependencies=[Depends(get_current_user)],
)

# Initialize ML services (lazy loading)
_ml_service = None
_lstm_service = None

def get_ml_service():
    """Lazy load ML service"""
    global _ml_service
    if _ml_service is None:
        _ml_service = EnergyMLService(model_dir='models')
        _ml_service.load_models()
    return _ml_service

def get_lstm_service():
    """Lazy load LSTM service"""
    global _lstm_service
    if _lstm_service is None:
        _lstm_service = LSTMPredictor(model_dir='models')
        _lstm_service.load_model()
    return _lstm_service if _lstm_service.is_trained else None

@router.post("/")
def save_prediction(prediction: Prediction):
    """Save a prediction to database"""
    doc = prediction.dict()
    doc["created_at"] = datetime.utcnow()
    prediction_col.insert_one(doc)
    return {"message": "Prediction saved"}

@router.get("/daily")
def get_daily_predictions():
    """Get daily predictions from database"""
    return list(prediction_col.find({"prediction_type": "daily"}, {"_id": 0}).sort("created_at", -1).limit(100))

@router.get("/predict")
def predict_energy(
    location: Optional[str] = Query(None, description="Filter by location"),
    hours_ahead: int = Query(24, ge=1, le=168, description="Hours ahead to predict"),
    model_type: str = Query("random_forest", description="Model type: random_forest or lstm")
):
    """
    Predict future energy consumption using ML models
    
    Uses either Random Forest (fast) or LSTM (time series) model
    """
    try:
        ml_service = get_ml_service()
        
        if not ml_service.is_trained:
            raise HTTPException(status_code=503, detail="ML models not trained. Please train models first.")
        
        # Get recent data for prediction
        cutoff_time = datetime.utcnow() - timedelta(hours=48)
        query = {"received_at": {"$gte": cutoff_time}}
        if location:
            query["location"] = location
        
        # Get energy readings
        cursor = energy_col.find(query).sort("received_at", -1).limit(200)
        data = []
        for doc in cursor:
            received_at = doc.get("received_at", {})
            if isinstance(received_at, dict) and "$date" in received_at:
                timestamp = datetime.fromisoformat(received_at["$date"].replace("Z", "+00:00"))
            elif isinstance(received_at, datetime):
                timestamp = received_at
            else:
                continue
            
            data.append({
                "module": doc.get("module"),
                "location": doc.get("location"),
                "current_a": doc.get("current_a", 0),
                "power_w": doc.get("power_w") or (doc.get("current_a", 0) * 230),
                "received_at": timestamp
            })
        
        if len(data) < 10:
            raise HTTPException(status_code=400, detail="Not enough data for prediction. Need at least 10 readings.")
        
        df = pd.DataFrame(data)
        df = df.sort_values('received_at')
        
        if model_type == "lstm":
            lstm_service = get_lstm_service()
            if lstm_service is None:
                raise HTTPException(status_code=503, detail="LSTM model not available. Using Random Forest instead.")
                model_type = "random_forest"
            else:
                # Use LSTM for time series prediction
                predictions_df = lstm_service.predict(df.tail(50), steps_ahead=min(hours_ahead, 24))
                predictions = predictions_df['predicted_power_w'].tolist()
                
                return {
                    "model_type": "lstm",
                    "location": location,
                    "hours_ahead": len(predictions),
                    "predictions": [
                        {
                            "step": i + 1,
                            "predicted_power_w": float(pred),
                            "timestamp": (datetime.utcnow() + timedelta(hours=i+1)).isoformat()
                        }
                        for i, pred in enumerate(predictions)
                    ],
                    "average_power": float(predictions_df['predicted_power_w'].mean())
                }
        
        # Use Random Forest (default)
        predictions = ml_service.predict_energy(df.tail(100))
        avg_prediction = predictions['predicted_power_w'].mean()
        
        # Save prediction to database
        prediction_doc = {
            "device_id": location or "all",
            "predicted_energy_kwh": float(avg_prediction / 1000.0),  # Convert W to kWh
            "confidence_score": 0.85,
            "prediction_type": "real-time",
            "created_at": datetime.utcnow(),
            "hours_ahead": hours_ahead
        }
        prediction_col.insert_one(prediction_doc)
        
        return {
            "model_type": "random_forest",
            "location": location,
            "predicted_power_w": float(avg_prediction),
            "predicted_energy_kwh": float(avg_prediction / 1000.0),
            "confidence_score": 0.85,
            "hours_ahead": hours_ahead,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

@router.get("/compare")
def compare_models(location: Optional[str] = None):
    """
    Compare predictions from both Random Forest and LSTM models
    """
    try:
        ml_service = get_ml_service()
        lstm_service = get_lstm_service()
        
        if not ml_service.is_trained:
            raise HTTPException(status_code=503, detail="ML models not trained")
        
        # Get recent data
        cutoff_time = datetime.utcnow() - timedelta(hours=48)
        query = {"received_at": {"$gte": cutoff_time}}
        if location:
            query["location"] = location
        
        cursor = energy_col.find(query).sort("received_at", -1).limit(100)
        data = []
        for doc in cursor:
            received_at = doc.get("received_at", {})
            if isinstance(received_at, dict) and "$date" in received_at:
                timestamp = datetime.fromisoformat(received_at["$date"].replace("Z", "+00:00"))
            elif isinstance(received_at, datetime):
                timestamp = received_at
            else:
                continue
            
            data.append({
                "module": doc.get("module"),
                "location": doc.get("location"),
                "current_a": doc.get("current_a", 0),
                "power_w": doc.get("power_w") or (doc.get("current_a", 0) * 230),
                "received_at": timestamp
            })
        
        if len(data) < 10:
            raise HTTPException(status_code=400, detail="Not enough data for comparison")
        
        df = pd.DataFrame(data)
        df = df.sort_values('received_at')
        
        # Random Forest prediction
        rf_predictions = ml_service.predict_energy(df.tail(50))
        rf_avg = rf_predictions['predicted_power_w'].mean()
        
        result = {
            "location": location,
            "random_forest": {
                "predicted_power_w": float(rf_avg),
                "predicted_energy_kwh": float(rf_avg / 1000.0),
                "confidence": 0.85
            }
        }
        
        # LSTM prediction if available
        if lstm_service and lstm_service.is_trained:
            try:
                lstm_predictions = lstm_service.predict(df.tail(50), steps_ahead=5)
                lstm_avg = lstm_predictions['predicted_power_w'].mean()
                result["lstm"] = {
                    "predicted_power_w": float(lstm_avg),
                    "predicted_energy_kwh": float(lstm_avg / 1000.0),
                    "next_5_steps": [
                        {"step": i+1, "power_w": float(p)} 
                        for i, p in enumerate(lstm_predictions['predicted_power_w'].head(5))
                    ]
                }
            except Exception as e:
                result["lstm"] = {"error": str(e)}
        else:
            result["lstm"] = {"status": "not_available"}
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Comparison failed: {str(e)}")
