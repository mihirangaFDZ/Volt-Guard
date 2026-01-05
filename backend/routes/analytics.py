from typing import Optional, List
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends
from database import analytics_col
from utils.jwt_handler import get_current_user
from app.models.analytics_model import (
    Recommendation,
    RecommendationSeverity,
    RecommendationsResponse,
)

# Import AI optimization services
try:
    from app.services.energy_optimizer import EnergyOptimizer
    from app.services.dataset_generator import DatasetGenerator
    AI_AVAILABLE = True
except ImportError:
    AI_AVAILABLE = False

router = APIRouter(
    prefix="/analytics",
    tags=["Analytics"],
    dependencies=[Depends(get_current_user)],
)

# Sri Lankan timezone (UTC+5:30)
SRI_LANKA_TZ = timezone(timedelta(hours=5, minutes=30))


@router.get("/filters")
def get_available_filters():
    """
    Get available locations and modules from occupancy_telemetry table.
    Returns distinct values for filtering.
    """
    # Get distinct locations
    locations = analytics_col.distinct("location")
    locations = [loc for loc in locations if loc]  # Filter out None/empty values
    locations.sort()
    
    # Get distinct modules
    modules = analytics_col.distinct("module")
    modules = [mod for mod in modules if mod]  # Filter out None/empty values
    modules.sort()
    
    return {
        "locations": locations,
        "modules": modules
    }


@router.get("/occupancy-stats")
def get_occupancy_stats(limit: int = 50, module: Optional[str] = None, location: Optional[str] = None):
    """
    Get occupancy statistics from occupancy_telemetry table.
    Returns statistics about occupied vs vacant periods.
    """
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location

    cursor = (
        analytics_col
        .find(query, {"_id": 0})
        .sort([
            ("received_at", -1),
            ("receivedAt", -1),
            ("timestamp", -1),
            ("_id", -1),
        ])
        .limit(limit)
    )

    docs = list(cursor)
    if not docs:
        return {
            "total_readings": 0,
            "occupied_count": 0,
            "vacant_count": 0,
            "occupied_percentage": 0.0,
            "vacant_percentage": 0.0,
            "is_currently_occupied": False,
        }

    # Check if sensors are offline (latest reading is too old)
    now = datetime.now(timezone.utc)
    offline_threshold_minutes = 30  # Consider sensor offline if no reading in last 30 minutes
    
    latest = docs[0]
    ts = latest.get("received_at") or latest.get("receivedAt") or latest.get("timestamp")
    is_sensor_offline = False
    
    if ts is not None:
        dt = _to_datetime(ts)
        if dt is not None:
            # Convert to UTC for comparison
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            else:
                dt = dt.astimezone(timezone.utc)
            time_diff = (now - dt).total_seconds() / 60  # minutes
            is_sensor_offline = time_diff > offline_threshold_minutes
        else:
            is_sensor_offline = True  # Invalid timestamp
    else:
        is_sensor_offline = True  # No timestamp
    
    # If sensor is offline, set occupancy to vacant and all counts to reflect offline status
    if is_sensor_offline:
        return {
            "total_readings": len(docs),
            "occupied_count": 0,
            "vacant_count": len(docs),
            "occupied_percentage": 0.0,
            "vacant_percentage": 100.0,
            "is_currently_occupied": False,
        }

    # Count occupied and vacant readings (sensors are online)
    occupied_count = sum(1 for d in docs if d.get("pir") == 1 or d.get("rcwl") == 1)
    vacant_count = len(docs) - occupied_count
    total_readings = len(docs)
    
    # Latest reading to determine current status
    is_currently_occupied = latest.get("pir") == 1 or latest.get("rcwl") == 1

    return {
        "total_readings": total_readings,
        "occupied_count": occupied_count,
        "vacant_count": vacant_count,
        "occupied_percentage": round((occupied_count / total_readings * 100), 1) if total_readings > 0 else 0.0,
        "vacant_percentage": round((vacant_count / total_readings * 100), 1) if total_readings > 0 else 0.0,
        "is_currently_occupied": is_currently_occupied,
    }


@router.get("/latest")
def get_latest_readings(limit: int = 50, module: Optional[str] = None, location: Optional[str] = None):
    query = {}
    if module:
        query["module"] = module
    if location:
        query["location"] = location

    cursor = (
        analytics_col
        .find(query, {"_id": 0})
        .sort([
            ("received_at", -1),
            ("receivedAt", -1),
            ("timestamp", -1),
            ("_id", -1),
        ])
        .limit(limit)
    )   

    normalized = []
    now = datetime.now(timezone.utc)
    # Consider sensor offline if no reading in last 30 minutes
    offline_threshold_minutes = 30
    
    for doc in cursor:
        ts = doc.get("received_at") or doc.get("receivedAt") or doc.get("timestamp")
        if ts is not None:
            dt = _to_datetime(ts)
            if dt is not None:
                # Convert to UTC for comparison
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                else:
                    dt = dt.astimezone(timezone.utc)
                
                # Check if sensor is offline (reading is older than threshold)
                time_diff = (now - dt).total_seconds() / 60  # minutes
                is_offline = time_diff > offline_threshold_minutes
                
                # Convert to Sri Lankan time and return as ISO string
                doc["receivedAt"] = dt.astimezone(SRI_LANKA_TZ).isoformat()
            else:
                doc["receivedAt"] = ts
                is_offline = True  # Invalid timestamp, consider offline
        else:
            is_offline = True  # No timestamp, consider offline
        
        # If sensor is offline, set all values to 0 and occupancy to vacant
        if is_offline:
            doc["temperature"] = 0
            doc["humidity"] = 0
            doc["pir"] = 0
            doc["rcwl"] = 0
            doc["rssi"] = 0 if doc.get("rssi") is not None else None  # Keep None if was None
            doc["occupied"] = False
            doc["is_occupied"] = False
        else:
            # Ensure occupied status is correctly set based on sensors
            pir = doc.get("pir", 0) or 0
            rcwl = doc.get("rcwl", 0) or 0
            doc["occupied"] = bool(pir == 1 or rcwl == 1)
            doc["is_occupied"] = bool(pir == 1 or rcwl == 1)
        
        normalized.append(doc)

    return normalized


def _to_datetime(value):
    if isinstance(value, datetime):
        dt = value
    else:
        try:
            dt = datetime.fromisoformat(str(value))
        except Exception:
            return None
    
    # Ensure timezone-aware datetime (assume UTC if naive)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    
    # Convert to Sri Lankan time
    return dt.astimezone(SRI_LANKA_TZ)


def _get_ai_recommendations(module: Optional[str] = None, location: Optional[str] = None) -> List[Recommendation]:
    """
    Get AI-driven recommendations and convert to Recommendation format.
    Returns empty list if AI is not available or model is not trained.
    """
    if not AI_AVAILABLE:
        return []
    
    try:
        optimizer = EnergyOptimizer()
        if not optimizer.load_model():
            # Model not trained, return empty list
            return []
        
        # Generate clean dataset
        generator = DatasetGenerator()
        _, featured_df = generator.generate_clean_dataset(
            days=2,
            location=location,
            module=module
        )
        
        if featured_df.empty:
            return []
        
        # Generate AI recommendations
        ai_recs = optimizer.generate_recommendations(
            featured_df,
            threshold_high=1000.0,
            threshold_low=100.0
        )
        
        # Convert AI recommendations to Recommendation format
        converted_recs = []
        for ai_rec in ai_recs:
            # Map severity string to RecommendationSeverity enum
            severity_map = {
                'high': RecommendationSeverity.high,
                'medium': RecommendationSeverity.medium,
                'low': RecommendationSeverity.low,
            }
            severity = severity_map.get(ai_rec.get('severity', 'low').lower(), RecommendationSeverity.low)
            
            # Add savings info to detail if available
            detail = ai_rec.get('message', '')
            savings = ai_rec.get('estimated_savings', 0)
            if savings > 0:
                detail += f" (Potential savings: {savings:.2f} kWh/day)"
            
            converted_recs.append(
                Recommendation(
                    title=ai_rec.get('title', ''),
                    detail=detail,
                    cta='View Details',
                    severity=severity,
                )
            )
        
        return converted_recs
    
    except Exception:
        # If AI recommendations fail, just return empty list (non-blocking)
        return []


@router.get("/recommendations", response_model=RecommendationsResponse)
def get_recommendations(limit: int = 50, module: Optional[str] = None, location: Optional[str] = None):
    """
    Get AI-based energy optimization recommendations.
    Returns only AI-driven recommendations from the trained model.
    """
    # Get AI-based recommendations only
    ai_recs = _get_ai_recommendations(module=module, location=location)
    
    # Sort by severity (high -> medium -> low)
    severity_order = {RecommendationSeverity.high: 0, RecommendationSeverity.medium: 1, RecommendationSeverity.low: 2}
    ai_recs.sort(key=lambda r: severity_order.get(r.severity, 3))
    
    return RecommendationsResponse(recommendations=ai_recs, count=len(ai_recs))
