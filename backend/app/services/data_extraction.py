# backend/app/services/data_extraction.py
"""Extract real energy and occupancy data from MongoDB only (no dummy/sample data)."""
import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# Add parent directory to path to import database
backend_dir = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(backend_dir))
from database import energy_col, analytics_col

VOLTAGE = 230.0


def _parse_timestamp(raw):
    """Parse timestamp from DB: datetime, ISO string, or $date dict. Returns None if invalid."""
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw
    if isinstance(raw, str):
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except Exception:
            return None
    if isinstance(raw, dict) and "$date" in raw:
        d = raw["$date"]
        if isinstance(d, datetime):
            return d
        if isinstance(d, str):
            try:
                return datetime.fromisoformat(d.replace("Z", "+00:00"))
            except Exception:
                return None
    return None


def _get_timestamp_from_doc(doc, field_names=("received_at", "receivedAt", "timestamp", "created_at")):
    """First valid timestamp from doc using common field names."""
    for name in field_names:
        ts = _parse_timestamp(doc.get(name))
        if ts is not None:
            return ts
    return None


def extract_energy_readings(hours_back=48):
    """
    Extract real energy readings from MongoDB only (energy_readings collection).
    Uses all common timestamp fields so real device data is never skipped.
    Returns DataFrame with power_w derived from current when missing.
    """
    cutoff_time = datetime.utcnow() - timedelta(hours=hours_back)
    cutoff_str = cutoff_time.isoformat()
    query = {
        "$or": [
            {"received_at": {"$gte": cutoff_time}},
            {"received_at": {"$gte": cutoff_str}},
            {"receivedAt": {"$gte": cutoff_time}},
            {"timestamp": {"$gte": cutoff_time}},
            {"created_at": {"$gte": cutoff_time}},
        ]
    }
    cursor = energy_col.find(query).sort("_id", -1).limit(50000)

    data = []
    for doc in cursor:
        ts = _get_timestamp_from_doc(doc)
        if ts is None or ts < cutoff_time:
            continue
        current_a = doc.get("current_a")
        if current_a is None and doc.get("current_ma") is not None:
            current_a = float(doc["current_ma"]) / 1000.0
        current_a = float(current_a) if current_a is not None else 0.0
        power_w = doc.get("power_w")
        if power_w is None and current_a is not None:
            power_w = current_a * VOLTAGE
        power_w = float(power_w) if power_w is not None else 0.0

        data.append({
            "module": doc.get("module"),
            "location": doc.get("location"),
            "sensor": doc.get("sensor"),
            "current_ma": doc.get("current_ma", current_a * 1000),
            "current_a": current_a,
            "rms_a": doc.get("rms_a"),
            "adc_samples": doc.get("adc_samples"),
            "vref": doc.get("vref"),
            "wifi_rssi": doc.get("wifi_rssi"),
            "received_at": ts,
            "power_w": power_w,
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