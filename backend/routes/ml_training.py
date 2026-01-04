# backend/routes/ml_training.py
"""
API endpoints for ML model training and management
"""
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from typing import Optional
from datetime import datetime
from utils.jwt_handler import get_current_user
import sys
from pathlib import Path

# Add backend directory to path
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from app.services.create_clean_dataset import create_clean_dataset
from app.services.ml_service import EnergyMLService
from app.services.lstm_service import LSTMPredictor
import pandas as pd

router = APIRouter(
    prefix="/ml-training",
    tags=["ML Training"],
    dependencies=[Depends(get_current_user)],
)

# Training status tracking
_training_status = {
    "is_training": False,
    "last_training": None,
    "training_error": None
}

def train_models_background(hours_back: int = 48):
    """Background task to train models"""
    try:
        _training_status["is_training"] = True
        _training_status["training_error"] = None
        
        # Create clean dataset
        df, feature_cols = create_clean_dataset(hours_back=hours_back, output_path='clean_dataset.csv')
        
        if df is None or len(df) == 0:
            raise ValueError("No data available for training")
        
        ml_service = EnergyMLService(model_dir='models')
        
        # Select numeric features
        numeric_features = [col for col in feature_cols 
                           if col in df.columns and
                           df[col].dtype in ['float64', 'int64', 'float32', 'int32'] 
                           and not col.startswith('received_at')
                           and col != 'power_w'
                           and col != 'current_a']
        
        if len(numeric_features) == 0:
            numeric_features = [col for col in feature_cols if col in df.columns and col != 'power_w']
        
        # Train anomaly detector
        ml_service.train_anomaly_detector(df, numeric_features)
        
        # Train prediction model
        if 'power_w' in df.columns:
            ml_service.train_prediction_model(df, numeric_features, target_col='power_w')
            
            # Train LSTM
            lstm_features = [
                'current_a', 'power_w', 'hour_sin', 'hour_cos', 
                'day_sin', 'day_cos', 'is_weekend'
            ]
            lstm_features = [col for col in lstm_features if col in df.columns]
            
            if len(lstm_features) >= 3:
                available_data = len(df)
                seq_length = 12 if available_data < 100 else (24 if available_data < 500 else 48)
                
                lstm = LSTMPredictor(model_dir='models', sequence_length=seq_length, prediction_horizon=1)
                lstm.train(
                    df, 
                    target_col='power_w',
                    feature_cols=lstm_features,
                    epochs=100,
                    batch_size=min(32, len(df) // 10)
                )
        
        _training_status["last_training"] = datetime.utcnow().isoformat()
        _training_status["is_training"] = False
        
    except Exception as e:
        _training_status["training_error"] = str(e)
        _training_status["is_training"] = False
        _training_status["last_training"] = datetime.utcnow().isoformat()

@router.post("/train")
def train_models(
    background_tasks: BackgroundTasks,
    hours_back: int = 48
):
    """
    Train ML models using recent data
    
    This endpoint triggers training of:
    - Anomaly Detection (Isolation Forest)
    - Energy Prediction (Random Forest)
    - Time Series Prediction (LSTM)
    
    Training runs in the background to avoid blocking the API.
    """
    if _training_status["is_training"]:
        raise HTTPException(status_code=409, detail="Training is already in progress")
    
    background_tasks.add_task(train_models_background, hours_back)
    
    return {
        "message": "Training started in background",
        "hours_back": hours_back,
        "status": "training"
    }

@router.get("/status")
def get_training_status():
    """
    Get current training status and model information
    """
    try:
        ml_service = EnergyMLService(model_dir='models')
        ml_loaded = ml_service.load_models()
        
        lstm_service = LSTMPredictor(model_dir='models')
        lstm_loaded = lstm_service.load_model()
        
        # Check if model files exist
        model_dir = Path('models')
        models_exist = {
            "anomaly_model": (model_dir / 'anomaly_model.pkl').exists(),
            "prediction_model": (model_dir / 'prediction_model.pkl').exists(),
            "lstm_model": (model_dir / 'lstm_model.h5').exists(),
            "lstm_scalers": (model_dir / 'lstm_scalers.pkl').exists()
        }
        
        return {
            "is_training": _training_status["is_training"],
            "last_training": _training_status["last_training"],
            "training_error": _training_status["training_error"],
            "models": {
                "anomaly_detection": {
                    "trained": models_exist["anomaly_model"],
                    "loaded": ml_loaded
                },
                "prediction_rf": {
                    "trained": models_exist["prediction_model"],
                    "loaded": ml_loaded
                },
                "prediction_lstm": {
                    "trained": models_exist["lstm_model"] and models_exist["lstm_scalers"],
                    "loaded": lstm_loaded
                }
            },
            "model_files_exist": models_exist
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error checking status: {str(e)}")

@router.get("/model-info")
def get_model_info():
    """
    Get detailed information about trained models
    """
    try:
        ml_service = EnergyMLService(model_dir='models')
        ml_service.load_models()
        
        info = {
            "anomaly_detection": {
                "type": "Isolation Forest",
                "trained": ml_service.is_trained,
                "features_count": len(ml_service.feature_columns) if ml_service.feature_columns else 0
            },
            "prediction": {
                "random_forest": {
                    "type": "Random Forest Regressor",
                    "trained": ml_service.is_trained,
                    "features_count": len(ml_service.feature_columns) if ml_service.feature_columns else 0
                }
            }
        }
        
        # Try to load LSTM info
        try:
            lstm_service = LSTMPredictor(model_dir='models')
            if lstm_service.load_model():
                info["prediction"]["lstm"] = {
                    "type": "LSTM Neural Network",
                    "trained": True,
                    "sequence_length": lstm_service.sequence_length,
                    "features_count": len(lstm_service.feature_columns) if lstm_service.feature_columns else 0
                }
        except:
            info["prediction"]["lstm"] = {
                "type": "LSTM Neural Network",
                "trained": False
            }
        
        return info
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting model info: {str(e)}")

