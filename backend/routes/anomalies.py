from fastapi import APIRouter, Depends, Query, HTTPException
from typing import Optional
from database import anomaly_col, energy_col, analytics_col
from app.models.anomaly_model import Anomaly
from utils.jwt_handler import get_current_user
import pandas as pd
import sys
from pathlib import Path
from datetime import datetime, timedelta

# Add backend directory to path
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from app.services.ml_service import EnergyMLService
from app.services.data_extraction import extract_energy_readings, extract_occupancy_telemetry
from app.services.data_cleaning import DataCleaner
from app.services.feature_engineering import FeatureEngineer

router = APIRouter(
    prefix="/anomalies",
    tags=["Anomalies"],
    dependencies=[Depends(get_current_user)],
)

# Initialize ML service (lazy loading)
_ml_service = None

def get_ml_service():
    """Lazy load ML service"""
    global _ml_service
    if _ml_service is None:
        _ml_service = EnergyMLService(model_dir='models')
        _ml_service.load_models()
    return _ml_service

@router.post("/")
def add_anomaly(anomaly: Anomaly):
    """Manually add an anomaly to database"""
    doc = anomaly.dict()
    doc["created_at"] = datetime.utcnow()
    anomaly_col.insert_one(doc)
    return {"message": "Anomaly recorded"}

@router.get("/active")
def get_active_anomalies():
    """Get active anomalies from database"""
    return list(anomaly_col.find({"severity": "High"}, {"_id": 0}).sort("detected_at", -1).limit(100))

@router.get("/detect")
def detect_anomalies(
    location: Optional[str] = Query(None, description="Filter by location"),
    hours_back: int = Query(24, ge=1, le=168, description="Hours back to analyze"),
    min_score: float = Query(0.5, ge=0, le=1, description="Minimum anomaly score threshold")
):
    """
    Detect anomalies in recent energy data using Isolation Forest model
    
    Returns anomalies detected in the specified time period
    """
    try:
        ml_service = get_ml_service()
        
        if not ml_service.is_trained:
            raise HTTPException(status_code=503, detail="Anomaly detection model not trained. Please train models first.")
        
        # Extract and prepare data
        energy_df = extract_energy_readings(hours_back=hours_back)
        occupancy_df = extract_occupancy_telemetry(hours_back=hours_back)
        
        if len(energy_df) == 0:
            raise HTTPException(status_code=400, detail="No data available for anomaly detection")
        
        # Clean and merge data
        cleaner = DataCleaner()
        clean_energy = cleaner.clean_energy_readings(energy_df)
        
        if len(occupancy_df) > 0:
            clean_occupancy = cleaner.clean_occupancy_telemetry(occupancy_df)
            df = cleaner.merge_datasets(clean_energy, clean_occupancy)
        else:
            df = clean_energy
        
        # Filter by location if specified
        if location:
            df = df[df['location'] == location]
            if len(df) == 0:
                raise HTTPException(status_code=404, detail=f"No data found for location: {location}")
        
        # Create features
        feature_engineer = FeatureEngineer()
        df = feature_engineer.prepare_features(df)
        
        # Detect anomalies
        anomalies_df = ml_service.detect_anomalies(df)
        
        # Filter by anomaly score threshold
        anomalies_df = anomalies_df[anomalies_df['anomaly_score'] >= min_score]
        anomalies_df = anomalies_df[anomalies_df['is_anomaly'] == 1]
        
        # Sort by anomaly score (highest first)
        anomalies_df = anomalies_df.sort_values('anomaly_score', ascending=False)
        
        # Convert to list of dictionaries
        anomalies_list = []
        for _, row in anomalies_df.head(100).iterrows():  # Limit to 100 most significant
            anomaly_doc = {
                "device_id": row.get('location', 'unknown'),
                "anomaly_type": "energy_consumption",
                "severity": "High" if row['anomaly_score'] > 0.7 else "Medium",
                "description": f"Unusual energy pattern detected: {row.get('power_w', 0):.2f}W",
                "detected_at": row['received_at'].isoformat() if hasattr(row['received_at'], 'isoformat') else str(row['received_at']),
                "anomaly_score": float(row['anomaly_score']),
                "power_w": float(row.get('power_w', 0)),
                "current_a": float(row.get('current_a', 0)),
                "location": row.get('location', 'unknown')
            }
            anomalies_list.append(anomaly_doc)
            
            # Save to database
            anomaly_col.insert_one(anomaly_doc)
        
        return {
            "total_detected": len(anomalies_list),
            "location": location,
            "hours_analyzed": hours_back,
            "anomalies": anomalies_list
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Anomaly detection failed: {str(e)}")

@router.get("/stats")
def get_anomaly_stats(
    location: Optional[str] = Query(None, description="Filter by location"),
    days: int = Query(7, ge=1, le=90, description="Number of days to analyze")
):
    """Get anomaly statistics"""
    try:
        cutoff_time = datetime.utcnow() - timedelta(days=days)
        query = {"detected_at": {"$gte": cutoff_time.isoformat()}}
        if location:
            query["location"] = location
        
        anomalies = list(anomaly_col.find(query, {"_id": 0}))
        
        if not anomalies:
            return {
                "total": 0,
                "by_severity": {"High": 0, "Medium": 0, "Low": 0},
                "by_location": {},
                "average_score": 0
            }
        
        severity_count = {"High": 0, "Medium": 0, "Low": 0}
        location_count = {}
        total_score = 0
        
        for anomaly in anomalies:
            severity = anomaly.get("severity", "Medium")
            severity_count[severity] = severity_count.get(severity, 0) + 1
            
            loc = anomaly.get("location", "unknown")
            location_count[loc] = location_count.get(loc, 0) + 1
            
            total_score += anomaly.get("anomaly_score", 0)
        
        return {
            "total": len(anomalies),
            "by_severity": severity_count,
            "by_location": location_count,
            "average_score": total_score / len(anomalies) if anomalies else 0,
            "period_days": days
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get stats: {str(e)}")
