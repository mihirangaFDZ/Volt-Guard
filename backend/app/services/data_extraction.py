# backend/app/services/data_extraction.py
import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# Add parent directory to path to import database
backend_dir = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(backend_dir))
from database import energy_col, analytics_col

def extract_energy_readings(hours_back=48):
    """Extract energy readings from MongoDB"""
    cutoff_time = datetime.utcnow() - timedelta(hours=hours_back)
    
    cursor = energy_col.find({
        "received_at": {"$gte": cutoff_time}
    })
    
    data = []
    for doc in cursor:
        # Handle MongoDB date format
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
            "sensor": doc.get("sensor"),
            "current_ma": doc.get("current_ma", 0),
            "current_a": doc.get("current_a", 0),
            "rms_a": doc.get("rms_a"),
            "adc_samples": doc.get("adc_samples"),
            "vref": doc.get("vref"),
            "wifi_rssi": doc.get("wifi_rssi"),
            "received_at": timestamp,
            "source": doc.get("source"),
            "type": doc.get("type")
        })
    
    return pd.DataFrame(data)

def extract_occupancy_telemetry(hours_back=48):
    """Extract occupancy telemetry from MongoDB"""
    cutoff_time = datetime.utcnow() - timedelta(hours=hours_back)
    
    cursor = analytics_col.find({
        "received_at": {"$gte": cutoff_time}
    })
    
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
            "rcwl": doc.get("rcwl", 0),
            "pir": doc.get("pir", 0),
            "rssi": doc.get("rssi"),
            "temperature": doc.get("temperature", 0),
            "humidity": doc.get("humidity", 0),
            "received_at": timestamp,
            "source": doc.get("source")
        })
    
    return pd.DataFrame(data)

# Explore data
if __name__ == "__main__":
    print("Extracting energy readings...")
    energy_df = extract_energy_readings(hours_back=48)
    print(f"Energy readings shape: {energy_df.shape}")
    print(energy_df.info())
    print(energy_df.head())
    
    print("\nExtracting occupancy telemetry...")
    occupancy_df = extract_occupancy_telemetry(hours_back=48)
    print(f"Occupancy telemetry shape: {occupancy_df.shape}")
    print(occupancy_df.info())
    print(occupancy_df.head())