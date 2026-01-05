"""
AI-Driven Energy Optimization & Recommendation Engine API
"""

from typing import Optional, List
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from database import energy_col, analytics_col

from app.services.energy_optimizer import EnergyOptimizer
from app.services.dataset_generator import DatasetGenerator
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/optimization",
    tags=["AI Optimization"],
    dependencies=[Depends(get_current_user)],
)


class RecommendationResponse(BaseModel):
    """Response model for recommendations"""
    type: str
    title: str
    message: str
    estimated_savings: float  # kWh per day
    severity: str
    location: Optional[str] = None
    module: Optional[str] = None
    current_energy_watts: Optional[float] = None
    current_temperature: Optional[float] = None
    current_humidity: Optional[float] = None
    is_occupied: Optional[bool] = None
    vacancy_duration_minutes: Optional[int] = None
    rcwl: Optional[int] = None
    pir: Optional[int] = None


class OptimizationResponse(BaseModel):
    """Response model for optimization endpoint"""
    recommendations: List[RecommendationResponse]
    predicted_energy_watts: Optional[float] = None
    current_energy_watts: Optional[float] = None
    potential_savings_kwh_per_day: float
    count: int
    message: Optional[str] = None


class TrainModelResponse(BaseModel):
    """Response model for model training"""
    status: str
    message: str
    metrics: Optional[dict] = None


@router.get("/recommendations", response_model=OptimizationResponse)
def get_ai_recommendations(
    days: int = Query(2, ge=1, le=30, description="Days of historical data to analyze"),
    location: Optional[str] = Query(None, description="Filter by location"),
    module: Optional[str] = Query(None, description="Filter by module"),
    threshold_high: float = Query(1000.0, description="High energy threshold (Watts)"),
    threshold_low: float = Query(100.0, description="Low energy threshold (Watts)")
):
    """
    Get AI-driven energy optimization recommendations
    
    Analyzes energy consumption patterns and provides intelligent recommendations
    for energy optimization based on occupancy, time patterns, and consumption trends.
    """
    try:
        optimizer = EnergyOptimizer()
        
        # Try to load existing model
        model_loaded = optimizer.load_model()
        
        if not model_loaded:
            return OptimizationResponse(
                recommendations=[],
                potential_savings_kwh_per_day=0.0,
                count=0,
                message="Model not trained. Please train the model first using /optimization/train"
            )
        
        # Generate clean dataset
        generator = DatasetGenerator()
        _, featured_df = generator.generate_clean_dataset(
            days=days,
            location=location,
            module=module
        )
        
        if featured_df.empty:
            raise HTTPException(
                status_code=404,
                detail="No data available for the specified criteria"
            )
        
        # Generate recommendations
        recommendations = optimizer.generate_recommendations(
            featured_df,
            threshold_high=threshold_high,
            threshold_low=threshold_low
        )
        
        # Calculate current and predicted energy
        latest = featured_df.iloc[-1] if len(featured_df) > 0 else None
        current_energy = latest.get('energy_watts', 0) if latest is not None else None
        
        # Predict energy
        predictions = optimizer.predict(featured_df)
        predicted_energy = float(predictions[-1]) if len(predictions) > 0 else None
        
        # Calculate potential savings
        potential_savings = sum(rec.get('estimated_savings', 0) for rec in recommendations)
        
        # Convert recommendations to response model
        rec_responses = [
            RecommendationResponse(**rec) for rec in recommendations
        ]
        
        return OptimizationResponse(
            recommendations=rec_responses,
            predicted_energy_watts=predicted_energy,
            current_energy_watts=float(current_energy) if current_energy is not None else None,
            potential_savings_kwh_per_day=potential_savings,
            count=len(rec_responses)
        )
    
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error generating recommendations: {str(e)}"
        )


@router.post("/train", response_model=TrainModelResponse)
def train_optimization_model(
    days: int = Query(7, ge=1, le=30, description="Days of data to use for training"),
    location: Optional[str] = Query(None, description="Filter by location"),
    module: Optional[str] = Query(None, description="Filter by module"),
    model_type: str = Query("random_forest", regex="^(random_forest|gradient_boosting)$", description="Model type"),
    test_size: float = Query(0.2, ge=0.1, le=0.5, description="Proportion of data for testing")
):
    """
    Train the AI energy optimization model
    
    Trains a machine learning model on historical energy and occupancy data
    to predict energy consumption and generate optimization recommendations.
    """
    try:
        optimizer = EnergyOptimizer()
        
        # Train model
        metrics = optimizer.train_model(
            days=days,
            location=location,
            module=module,
            model_type=model_type,
            test_size=test_size
        )
        
        return TrainModelResponse(
            status="success",
            message=f"Model trained successfully with {metrics['n_samples']} samples",
            metrics=metrics
        )
    
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error training model: {str(e)}"
        )


@router.get("/predict")
def predict_energy_consumption(
    days: int = Query(1, ge=1, le=7, description="Days of data to use for prediction"),
    location: Optional[str] = Query(None, description="Filter by location"),
    module: Optional[str] = Query(None, description="Filter by module")
):
    """
    Predict energy consumption for next time period
    
    Uses the trained AI model to predict energy consumption based on
    current conditions and historical patterns.
    """
    try:
        optimizer = EnergyOptimizer()
        
        # Load model
        if not optimizer.load_model():
            raise HTTPException(
                status_code=404,
                detail="Model not trained. Please train the model first using /optimization/train"
            )
        
        # Generate clean dataset
        generator = DatasetGenerator()
        _, featured_df = generator.generate_clean_dataset(
            days=days,
            location=location,
            module=module
        )
        
        if featured_df.empty:
            raise HTTPException(
                status_code=404,
                detail="No data available for the specified criteria"
            )
        
        # Predict
        predictions = optimizer.predict(featured_df)
        
        # Get latest reading
        latest = featured_df.iloc[-1] if len(featured_df) > 0 else None
        current_energy = latest.get('energy_watts', 0) if latest is not None else None
        
        return {
            "current_energy_watts": float(current_energy) if current_energy is not None else None,
            "predicted_energy_watts": float(predictions[-1]) if len(predictions) > 0 else None,
            "predictions": [float(p) for p in predictions],
            "timestamp": datetime.now().isoformat()
        }
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error making prediction: {str(e)}"
        )

