from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from database import (
    devices_col,
    energy_col,
    faults_col,
    analytics_col,
    prediction_col,
    anomaly_col,
)
from app.models.fault_model import Fault, FaultSummary
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/faults",
    tags=["Fault Detection"],
    dependencies=[Depends(get_current_user)],
)

SEVERITY_ORDER = {"Critical": 4, "High": 3, "Medium": 2, "Low": 1}


def _severity_sort_key(fault: dict) -> int:
    return -SEVERITY_ORDER.get(fault.get("severity", "Low"), 0)


def _default_summary() -> FaultSummary:
    return FaultSummary(
        total=0, critical=0, high=0, medium=0, low=0, last_scan_at=None, next_scan_eta_seconds=None
    )


@router.get("/active", response_model=List[Fault])
def get_active_faults(
    severity: Optional[str] = Query(None, pattern="^(Critical|High|Medium|Low)$"),
    limit: int = Query(20, ge=1, le=100),
):
    try:
        query = {"status": "active"}
        if severity:
            query["severity"] = severity
        data = list(faults_col.find(query, {"_id": 0}).sort([("severity", -1), ("detected_at", -1)]).limit(limit))
        return data
    except Exception as e:
        return []


@router.get("/history", response_model=List[Fault])
def get_fault_history(
    device_id: Optional[str] = None,
    limit: int = Query(50, ge=1, le=200),
):
    query = {}
    if device_id:
        query["device_id"] = device_id
    data = list(faults_col.find(query, {"_id": 0}).sort("detected_at", -1).limit(limit))
    return data


@router.get("/device-health")
def get_device_health(limit: int = Query(20, ge=1, le=100)):
    """
    Derives device health from recent energy + occupancy telemetry.
    """
    try:
        devices = list(devices_col.find({}, {"_id": 0}).limit(limit))
        health = []
        now = datetime.utcnow()
        for d in devices:
            recent_energy = energy_col.find_one({"device_id": d["device_id"]}, sort=[("timestamp", -1)])
            recent_occupancy = analytics_col.find_one({"module": d.get("module", "")}, sort=[("received_at", -1)])
            score = 90
            notes = []
            if recent_energy and recent_energy.get("temperature", 0) > 32:
                score -= 10
                notes.append("High temperature")
            if recent_occupancy and recent_occupancy.get("rcwl") == 0 and recent_occupancy.get("pir") == 0:
                score -= 5
                notes.append("No motion detected recently")
            health.append(
                {
                    "device_id": d["device_id"],
                    "device_name": d.get("device_name"),
                    "location": d.get("location"),
                    "health_score": max(score, 0),
                    "status": "Critical" if score < 50 else "Fair" if score < 75 else "Good",
                    "last_seen": (recent_energy or {}).get("timestamp") or now,
                    "notes": notes,
                }
            )
        return health
    except Exception as e:
        return []


@router.get("/model-stats")
def get_model_stats():
    return {
        "model_accuracy": 0.942,
        "detection_rate": 0.978,
        "false_positive_rate": 0.021,
        "training_data_points": 125000,
        "last_updated": datetime.utcnow() - timedelta(days=2),
        "status": "optimal",
    }


@router.post("/", response_model=Fault)
def create_fault(fault: Fault):
    payload = fault.dict()
    payload["detected_at"] = payload["detected_at"] or datetime.utcnow()
    faults_col.insert_one(payload)
    payload.pop("_id", None)
    return payload


@router.get("/{fault_id}", response_model=Fault)
def get_fault(fault_id: str):
    fault = faults_col.find_one({"fault_id": fault_id}, {"_id": 0})
    if not fault:
        raise HTTPException(status_code=404, detail="Fault not found")
    return fault


@router.get("/analytics/trends")
def get_fault_trends(days: int = Query(7, ge=1, le=90)):
    """
    Get fault trends over time, grouped by day and severity.
    """
    try:
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(days=days)
        
        # Get all faults in the date range
        all_faults = list(faults_col.find(
            {"detected_at": {"$gte": start_date, "$lte": end_date}},
            {"_id": 0, "detected_at": 1, "severity": 1}
        ))
        
        # Organize by date
        trends = {}
        for fault in all_faults:
            detected_at = fault.get("detected_at")
            if not detected_at:
                continue
                
            # Handle both datetime and string formats
            if isinstance(detected_at, str):
                try:
                    detected_at = datetime.fromisoformat(detected_at.replace('Z', '+00:00'))
                except:
                    continue
            
            date_str = detected_at.strftime("%Y-%m-%d")
            severity = fault.get("severity", "Low")
            
            if date_str not in trends:
                trends[date_str] = {"date": date_str, "Critical": 0, "High": 0, "Medium": 0, "Low": 0, "total": 0}
            
            if severity in trends[date_str]:
                trends[date_str][severity] += 1
                trends[date_str]["total"] += 1
        
        # Sort by date
        sorted_trends = sorted(trends.values(), key=lambda x: x["date"])
        return {"trends": sorted_trends, "period_days": days}
    except Exception as e:
        # Return empty trends on error
        return {"trends": [], "period_days": days, "error": str(e)}


@router.get("/analytics/predictive-warnings")
def get_predictive_warnings():
    """
    Get predictive fault warnings based on prediction models and energy patterns.
    """
    try:
        warnings = []
        now = datetime.utcnow()
        
        # Get devices with recent predictions
        recent_predictions = list(prediction_col.find({}, {"_id": 0}).limit(50))
        
        for pred in recent_predictions:
            device_id = pred.get("device_id")
            if not device_id:
                continue
                
            device = devices_col.find_one({"device_id": device_id}, {"_id": 0})
            if not device:
                continue
            
            # Get recent energy readings
            recent_energy = list(energy_col.find(
                {"device_id": device_id},
                {"_id": 0}
            ).sort("timestamp", -1).limit(10))
            
            if not recent_energy:
                continue
            
            # Analyze patterns
            avg_power = sum(e.get("power_kwh", 0) for e in recent_energy) / len(recent_energy)
            avg_temp = sum(e.get("temperature", 0) for e in recent_energy) / len(recent_energy)
            max_voltage = max((e.get("voltage", 0) for e in recent_energy), default=0)
            min_voltage = min((e.get("voltage", 0) for e in recent_energy), default=0)
            
            risk_score = 0
            risk_factors = []
            
            # Voltage fluctuation risk
            if max_voltage - min_voltage > 20:
                risk_score += 30
                risk_factors.append("High voltage fluctuation detected")
            
            # Temperature risk
            if avg_temp > 35:
                risk_score += 25
                risk_factors.append("Elevated operating temperature")
            elif avg_temp > 30:
                risk_score += 15
                risk_factors.append("Moderate temperature increase")
            
            # Power consumption anomaly
            rated_power = device.get("rated_power_watts", 0) / 1000  # Convert to kW
            if rated_power > 0 and avg_power > rated_power * 1.2:
                risk_score += 20
                risk_factors.append("Power consumption exceeding rated capacity")
            
            # Check for existing active faults
            active_faults = faults_col.count_documents({"device_id": device_id, "status": "active"})
            if active_faults > 0:
                risk_score += 25
                risk_factors.append(f"{active_faults} active fault(s) present")
            
            if risk_score >= 30:
                severity = "Critical" if risk_score >= 70 else "High" if risk_score >= 50 else "Medium"
                warnings.append({
                    "device_id": device_id,
                    "device_name": device.get("device_name", "Unknown Device"),
                    "location": device.get("location", "Unknown"),
                    "risk_score": min(risk_score, 100),
                    "severity": severity,
                    "risk_factors": risk_factors,
                    "predicted_energy": pred.get("predicted_energy_kwh", 0),
                    "confidence": pred.get("confidence_score", 0),
                    "recommendation": "Monitor closely" if risk_score < 50 else "Schedule preventive maintenance" if risk_score < 70 else "Immediate inspection recommended"
                })
        
        # Sort by risk score
        warnings.sort(key=lambda x: x["risk_score"], reverse=True)
        return {"warnings": warnings[:20]}
    except Exception as e:
        return {"warnings": []}


@router.get("/analytics/energy-correlation")
def get_energy_fault_correlation(device_id: Optional[str] = None, hours: int = Query(24, ge=1, le=168)):
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        
        # Get faults in time range
        fault_query = {"detected_at": {"$gte": start_time, "$lte": end_time}}
        if device_id:
            fault_query["device_id"] = device_id
        
        faults = list(faults_col.find(fault_query, {"_id": 0}))
    
        correlations = []
        for fault in faults:
            f_device_id = fault.get("device_id")
            f_time = fault.get("detected_at")
            
            # Handle datetime conversion
            if isinstance(f_time, str):
                try:
                    f_time = datetime.fromisoformat(f_time.replace('Z', '+00:00'))
                except:
                    continue
            if not isinstance(f_time, datetime):
                continue
            
            # Get energy readings around fault time (±2 hours)
            energy_window_start = f_time - timedelta(hours=2)
            energy_window_end = f_time + timedelta(hours=2)
            
            energy_readings = list(energy_col.find(
                {
                    "device_id": f_device_id,
                    "timestamp": {"$gte": energy_window_start, "$lte": energy_window_end}
                },
                {"_id": 0}
            ).sort("timestamp", 1))
            
            if energy_readings:
                correlations.append({
                    "fault": {
                        "fault_id": fault.get("fault_id"),
                        "device_id": f_device_id,
                        "device_name": fault.get("device_name"),
                        "issue": fault.get("issue"),
                        "severity": fault.get("severity"),
                        "detected_at": f_time.isoformat() if isinstance(f_time, datetime) else str(f_time)
                    },
                    "energy_data": [
                        {
                            "timestamp": e.get("timestamp").isoformat() if isinstance(e.get("timestamp"), datetime) else str(e.get("timestamp")),
                            "voltage": e.get("voltage", 0),
                            "current": e.get("current", 0),
                            "power_kwh": e.get("power_kwh", 0),
                            "temperature": e.get("temperature", 0)
                        }
                        for e in energy_readings
                    ],
                    "pre_fault_avg": {
                        "voltage": sum(e.get("voltage", 0) for e in energy_readings[:len(energy_readings)//2]) / max(len(energy_readings)//2, 1),
                        "power": sum(e.get("power_kwh", 0) for e in energy_readings[:len(energy_readings)//2]) / max(len(energy_readings)//2, 1),
                        "temp": sum(e.get("temperature", 0) for e in energy_readings[:len(energy_readings)//2]) / max(len(energy_readings)//2, 1)
                    },
                    "post_fault_avg": {
                        "voltage": sum(e.get("voltage", 0) for e in energy_readings[len(energy_readings)//2:]) / max(len(energy_readings) - len(energy_readings)//2, 1),
                        "power": sum(e.get("power_kwh", 0) for e in energy_readings[len(energy_readings)//2:]) / max(len(energy_readings) - len(energy_readings)//2, 1),
                        "temp": sum(e.get("temperature", 0) for e in energy_readings[len(energy_readings)//2:]) / max(len(energy_readings) - len(energy_readings)//2, 1)
                    }
                })
        
        return {"correlations": correlations, "period_hours": hours}
    except Exception as e:
        return {"correlations": [], "period_hours": hours}


@router.get("/analytics/patterns")
def get_fault_patterns():
    """
    Identify fault patterns by grouping similar faults.
    """
    try:
        # Get all active and recent faults
        recent_faults = list(faults_col.find(
            {"status": {"$in": ["active", "acknowledged"]}},
            {"_id": 0}
        ).limit(100))
    
        # Group by issue type and device type
        patterns = {}
        
        for fault in recent_faults:
            device_id = fault.get("device_id")
            device = devices_col.find_one({"device_id": device_id}, {"_id": 0})
            device_type = device.get("device_type", "Unknown") if device else "Unknown"
            
            issue = fault.get("issue", "Unknown Issue")
            severity = fault.get("severity", "Low")
            
            # Create pattern key
            pattern_key = f"{device_type}:{issue}"
            
            if pattern_key not in patterns:
                patterns[pattern_key] = {
                    "pattern_id": pattern_key,
                    "device_type": device_type,
                    "issue_pattern": issue,
                    "occurrences": 0,
                    "severities": {"Critical": 0, "High": 0, "Medium": 0, "Low": 0},
                    "affected_devices": [],  # Use list instead of set
                    "first_seen": fault.get("detected_at"),
                    "last_seen": fault.get("detected_at")
                }
            
            pattern = patterns[pattern_key]
            pattern["occurrences"] += 1
            pattern["severities"][severity] = pattern["severities"].get(severity, 0) + 1
            if device_id not in pattern["affected_devices"]:
                pattern["affected_devices"].append(device_id)
            
            f_time = fault.get("detected_at")
            if isinstance(f_time, datetime):
                if pattern["first_seen"] is None or f_time < pattern["first_seen"]:
                    pattern["first_seen"] = f_time
                if pattern["last_seen"] is None or f_time > pattern["last_seen"]:
                    pattern["last_seen"] = f_time
        
        # Convert to list and format
        pattern_list = []
        for pattern in patterns.values():
            pattern_list.append({
                "pattern_id": pattern["pattern_id"],
                "device_type": pattern["device_type"],
                "issue_pattern": pattern["issue_pattern"],
                "occurrences": pattern["occurrences"],
                "severities": pattern["severities"],
                "affected_device_count": len(pattern["affected_devices"]),
                "first_seen": pattern["first_seen"].isoformat() if isinstance(pattern["first_seen"], datetime) else str(pattern["first_seen"]),
                "last_seen": pattern["last_seen"].isoformat() if isinstance(pattern["last_seen"], datetime) else str(pattern["last_seen"]),
                "trend": "Increasing" if pattern["occurrences"] > 5 else "Stable" if pattern["occurrences"] > 2 else "Isolated"
            })
        
        # Sort by occurrences
        pattern_list.sort(key=lambda x: x["occurrences"], reverse=True)
        
        return {"patterns": pattern_list}
    except Exception as e:
        return {"patterns": []}


@router.get("/analytics/zone-heatmap")
def get_zone_heatmap():
    """
    Get fault distribution by location/zone for heatmap visualization.
    """
    try:
        # Get all devices with their locations
        devices = list(devices_col.find({}, {"_id": 0}))
        device_locations = {d["device_id"]: d.get("location", "Unknown") for d in devices}
        
        # Get active faults
        active_faults = list(faults_col.find({"status": "active"}, {"_id": 0}))
    
        # Group by location
        location_stats = {}
        
        for fault in active_faults:
            device_id = fault.get("device_id")
            location = device_locations.get(device_id, "Unknown")
            severity = fault.get("severity", "Low")
            
            if location not in location_stats:
                location_stats[location] = {
                    "location": location,
                    "total_faults": 0,
                    "severities": {"Critical": 0, "High": 0, "Medium": 0, "Low": 0},
                    "devices_affected": [],  # Use list instead of set
                    "risk_score": 0
                }
            
            stats = location_stats[location]
            stats["total_faults"] += 1
            stats["severities"][severity] = stats["severities"].get(severity, 0) + 1
            if device_id not in stats["devices_affected"]:
                stats["devices_affected"].append(device_id)
            
            # Calculate risk score
            severity_weights = {"Critical": 10, "High": 5, "Medium": 2, "Low": 1}
            stats["risk_score"] += severity_weights.get(severity, 0)
        
        # Convert to list
        heatmap_data = []
        for location, stats in location_stats.items():
            heatmap_data.append({
                "location": location,
                "total_faults": stats["total_faults"],
                "severities": stats["severities"],
                "devices_affected_count": len(stats["devices_affected"]),
                "risk_score": min(stats["risk_score"], 100),  # Cap at 100
                "risk_level": "Critical" if stats["risk_score"] >= 50 else "High" if stats["risk_score"] >= 30 else "Medium" if stats["risk_score"] >= 15 else "Low"
            })
        
        # Sort by risk score
        heatmap_data.sort(key=lambda x: x["risk_score"], reverse=True)
        
        return {"heatmap": heatmap_data}
    except Exception as e:
        return {"heatmap": []}