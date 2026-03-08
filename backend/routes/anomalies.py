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
from app.services.autoencoder_service import AutoencoderAnomalyDetector
from app.services.data_extraction import extract_energy_readings, extract_occupancy_telemetry
from app.services.data_cleaning import DataCleaner
from app.services.feature_engineering import FeatureEngineer

router = APIRouter(
    prefix="/anomalies",
    tags=["Anomalies"],
    dependencies=[Depends(get_current_user)],
)

# Initialize services (lazy loading)
_ml_service = None
_ae_service = None

def get_ml_service():
    """Lazy load Isolation Forest service"""
    global _ml_service
    if _ml_service is None:
        _ml_service = EnergyMLService(model_dir='models')
        _ml_service.load_models()
    return _ml_service

def get_ae_service():
    """Lazy load Autoencoder service"""
    global _ae_service
    if _ae_service is None:
        _ae_service = AutoencoderAnomalyDetector(model_dir='models')
        _ae_service.load_model()
    return _ae_service if _ae_service.is_trained else None

@router.post("/")
def add_anomaly(anomaly: Anomaly):
    """Manually add an anomaly to database"""
    doc = anomaly.dict()
    doc["created_at"] = datetime.utcnow()
    anomaly_col.insert_one(doc)
    return {"message": "Anomaly recorded"}

@router.get("/active")
def get_active_anomalies(
    severity: Optional[str] = Query(None, description="Filter by severity: High, Medium, Low"),
    limit: int = Query(50, ge=1, le=200),
    hours_back: int = Query(168, ge=1, le=720, description="How many hours back to look"),
):
    """Get recent anomaly alerts (auto-detected and manual)."""
    cutoff = datetime.utcnow() - timedelta(hours=hours_back)
    query = {"detected_at": {"$gte": cutoff.isoformat()}}
    if severity:
        query["severity"] = severity

    results = list(
        anomaly_col
        .find(query, {"_id": 0})
        .sort("detected_at", -1)
        .limit(limit)
    )
    return results

@router.get("/recent-alerts")
def get_recent_alerts(
    limit: int = Query(20, ge=1, le=100),
    hours_back: int = Query(24, ge=1, le=168, description="Hours back to look"),
):
    """
    Get recent anomaly alerts formatted for the mobile app alerts page.
    Returns user-friendly alert objects sorted by time.
    """
    cutoff = datetime.utcnow() - timedelta(hours=hours_back)
    query = {"detected_at": {"$gte": cutoff.isoformat()}}

    raw = list(
        anomaly_col
        .find(query, {"_id": 0})
        .sort("detected_at", -1)
        .limit(limit)
    )

    alerts = []
    for doc in raw:
        severity = doc.get("severity", "Medium")
        if severity == "High":
            icon = "warning"
            color = "red"
        elif severity == "Medium":
            icon = "info"
            color = "orange"
        else:
            icon = "info_outline"
            color = "blue"

        # Parse detected_at for relative time
        detected_at = doc.get("detected_at", "")
        try:
            dt = datetime.fromisoformat(detected_at) if isinstance(detected_at, str) else detected_at
            time_ago = _format_time_ago(dt)
        except Exception:
            time_ago = detected_at

        alerts.append({
            "id": doc.get("device_id", ""),
            "title": _alert_title(doc),
            "subtitle": doc.get("description", "Anomaly detected"),
            "severity": severity,
            "icon": icon,
            "color": color,
            "device_name": doc.get("device_name", doc.get("device_id", "Unknown")),
            "location": doc.get("location", ""),
            "power_w": doc.get("power_w", 0),
            "avg_power_w": doc.get("avg_power_w", 0),
            "detection_method": doc.get("detection_method", ""),
            "detected_at": detected_at,
            "time_ago": time_ago,
            "status": doc.get("status", "active"),
        })

    return {
        "total": len(alerts),
        "hours_back": hours_back,
        "alerts": alerts,
    }


def _alert_title(doc: dict) -> str:
    """Generate a user-friendly alert title."""
    severity = doc.get("severity", "Medium")
    device_name = doc.get("device_name", doc.get("device_id", "Device"))
    power = doc.get("power_w", 0)
    avg = doc.get("avg_power_w", 0)

    if severity == "High" and power > 0:
        return f"High energy spike on {device_name}"
    elif power > avg * 1.5 and avg > 0:
        return f"Unusual usage on {device_name}"
    else:
        return f"Anomaly detected on {device_name}"


def _format_time_ago(dt: datetime) -> str:
    """Format datetime as relative time string."""
    now = datetime.utcnow()
    diff = now - dt
    seconds = int(diff.total_seconds())
    if seconds < 60:
        return f"{seconds}s ago"
    elif seconds < 3600:
        return f"{seconds // 60}m ago"
    elif seconds < 86400:
        return f"{seconds // 3600}h ago"
    else:
        return f"{seconds // 86400}d ago"


@router.get("/detect")
def detect_anomalies(
    location: Optional[str] = Query(None, description="Filter by location"),
    hours_back: int = Query(24, ge=1, le=168, description="Hours back to analyze"),
    min_score: float = Query(0.5, ge=0, le=1, description="Minimum anomaly score threshold"),
    method: str = Query("isolation_forest", description="Detection method: isolation_forest, autoencoder, or both")
):
    """
    Detect anomalies in recent energy data

    Supports two detection methods:
    - isolation_forest: Statistical isolation-based detection
    - autoencoder: Neural network reconstruction error detection
    - both: Run both methods and combine results
    """
    try:
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

        anomalies_list = []

        # Run Isolation Forest
        if method in ("isolation_forest", "both"):
            ml_service = get_ml_service()
            if not ml_service.is_trained:
                if method == "isolation_forest":
                    raise HTTPException(status_code=503, detail="Isolation Forest model not trained.")
            else:
                if_df = ml_service.detect_anomalies(df.copy())
                if_anomalies = if_df[(if_df['is_anomaly'] == 1) & (if_df['anomaly_score'] >= min_score)]
                if_anomalies = if_anomalies.sort_values('anomaly_score', ascending=False)

                for _, row in if_anomalies.head(100).iterrows():
                    anomaly_doc = {
                        "device_id": row.get('location', 'unknown'),
                        "anomaly_type": "energy_consumption",
                        "severity": "High" if row['anomaly_score'] > 0.7 else "Medium",
                        "description": f"Unusual energy pattern detected: {row.get('power_w', 0):.2f}W",
                        "detected_at": row['received_at'].isoformat() if hasattr(row['received_at'], 'isoformat') else str(row['received_at']),
                        "anomaly_score": float(row['anomaly_score']),
                        "power_w": float(row.get('power_w', 0)),
                        "current_a": float(row.get('current_a', 0)),
                        "location": row.get('location', 'unknown'),
                        "detection_method": "isolation_forest"
                    }
                    anomalies_list.append(anomaly_doc)
                    anomaly_col.insert_one(anomaly_doc)

        # Run Autoencoder
        if method in ("autoencoder", "both"):
            ae_service = get_ae_service()
            if ae_service is None:
                if method == "autoencoder":
                    raise HTTPException(status_code=503, detail="Autoencoder model not trained.")
            else:
                ae_df = ae_service.detect_anomalies(df.copy())
                ae_anomalies = ae_df[(ae_df['is_anomaly_ae'] == 1) & (ae_df['anomaly_score_ae'] >= min_score)]
                ae_anomalies = ae_anomalies.sort_values('anomaly_score_ae', ascending=False)

                for _, row in ae_anomalies.head(100).iterrows():
                    anomaly_doc = {
                        "device_id": row.get('location', 'unknown'),
                        "anomaly_type": "energy_consumption",
                        "severity": "High" if row['anomaly_score_ae'] > 0.7 else "Medium",
                        "description": f"Abnormal reconstruction pattern: {row.get('power_w', 0):.2f}W (error: {row['reconstruction_error']:.4f})",
                        "detected_at": row['received_at'].isoformat() if hasattr(row['received_at'], 'isoformat') else str(row['received_at']),
                        "anomaly_score": float(row['anomaly_score_ae']),
                        "reconstruction_error": float(row['reconstruction_error']),
                        "power_w": float(row.get('power_w', 0)),
                        "current_a": float(row.get('current_a', 0)),
                        "location": row.get('location', 'unknown'),
                        "detection_method": "autoencoder"
                    }
                    anomalies_list.append(anomaly_doc)
                    anomaly_col.insert_one(anomaly_doc)

        return {
            "total_detected": len(anomalies_list),
            "location": location,
            "hours_analyzed": hours_back,
            "detection_method": method,
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
                "by_method": {},
                "average_score": 0
            }

        severity_count = {"High": 0, "Medium": 0, "Low": 0}
        location_count = {}
        method_count = {}
        total_score = 0

        for anomaly in anomalies:
            severity = anomaly.get("severity", "Medium")
            severity_count[severity] = severity_count.get(severity, 0) + 1

            loc = anomaly.get("location", "unknown")
            location_count[loc] = location_count.get(loc, 0) + 1

            det_method = anomaly.get("detection_method", "isolation_forest")
            method_count[det_method] = method_count.get(det_method, 0) + 1

            total_score += anomaly.get("anomaly_score", 0)

        return {
            "total": len(anomalies),
            "by_severity": severity_count,
            "by_location": location_count,
            "by_method": method_count,
            "average_score": total_score / len(anomalies) if anomalies else 0,
            "period_days": days
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get stats: {str(e)}")
