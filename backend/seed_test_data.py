# backend/seed_test_data.py
"""
Seed script — inserts realistic test data into MongoDB for testing
behavioral profiling, anomaly detection, and prediction endpoints.

Usage:
    cd backend
    python seed_test_data.py          # Insert test data
    python seed_test_data.py --clean  # Remove test data first, then insert
"""
import sys
from pathlib import Path
from datetime import datetime, timedelta
import random
import math

backend_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(backend_dir))

from database import devices_col, energy_col, analytics_col

# ---------------------------------------------------------------------------
# Test devices
# ---------------------------------------------------------------------------
TEST_DEVICES = [
    {
        "device_id": "TEST_AC_01",
        "device_name": "Lab Air Conditioner",
        "device_type": "Air Conditioner",
        "location": "LAB_1",
        "rated_power_watts": 1200,
        "module_id": "MOD_AC_01",
        "installed_date": "2025-01-15",
    },
    {
        "device_id": "TEST_LIGHT_01",
        "device_name": "Lab Ceiling Lights",
        "device_type": "Lighting",
        "location": "LAB_1",
        "rated_power_watts": 150,
        "module_id": "MOD_LIGHT_01",
        "installed_date": "2025-01-15",
    },
    {
        "device_id": "TEST_PC_01",
        "device_name": "Workstation Desktop",
        "device_type": "Computer",
        "location": "LAB_1",
        "rated_power_watts": 350,
        "module_id": "MOD_PC_01",
        "installed_date": "2025-02-01",
    },
    {
        "device_id": "TEST_FAN_01",
        "device_name": "Office Ceiling Fan",
        "device_type": "Fan",
        "location": "OFFICE_1",
        "rated_power_watts": 75,
        "module_id": "MOD_FAN_01",
        "installed_date": "2025-01-20",
    },
    {
        "device_id": "TEST_PRINTER_01",
        "device_name": "Office Printer",
        "device_type": "Printer",
        "location": "OFFICE_1",
        "rated_power_watts": 500,
        "module_id": "MOD_PRINTER_01",
        "installed_date": "2025-01-25",
    },
]

VOLTAGE = 230  # Sri Lanka mains


def _noise(base: float, pct: float = 0.05) -> float:
    """Add ±pct% noise to a base value."""
    return base * (1 + random.uniform(-pct, pct))


def generate_energy_readings(device: dict, hours_back: int = 168) -> list:
    """
    Generate realistic 5-minute-interval energy readings for a device.

    Patterns:
    - AC:      high when occupied & hot, low standby when vacant (energy vampire)
    - Lights:  on when occupied, small standby (LED driver)
    - PC:      on during work hours, high standby when vacant (energy vampire)
    - Fan:     on when occupied, zero when off
    - Printer: mostly standby, occasional spikes when printing (energy vampire)
    """
    readings = []
    now = datetime.utcnow()
    start = now - timedelta(hours=hours_back)
    interval = timedelta(minutes=5)

    device_type = device["device_type"]
    module_id = device["module_id"]
    location = device["location"]
    rated = device["rated_power_watts"]

    t = start
    while t <= now:
        hour = t.hour
        day_of_week = t.weekday()
        is_weekend = day_of_week >= 5
        is_work_hours = 8 <= hour <= 18 and not is_weekend

        if device_type == "Air Conditioner":
            if is_work_hours:
                power = _noise(rated * 0.7, 0.1)       # 70% of rated when on
            else:
                power = _noise(rated * 0.15, 0.1)       # 15% standby — ENERGY VAMPIRE
        elif device_type == "Lighting":
            if is_work_hours:
                power = _noise(rated * 0.9, 0.05)
            else:
                power = _noise(3.0, 0.2)                 # 3W LED driver standby — low
        elif device_type == "Computer":
            if is_work_hours:
                power = _noise(rated * 0.6, 0.15)
            else:
                power = _noise(rated * 0.25, 0.1)        # 25% standby — ENERGY VAMPIRE
        elif device_type == "Fan":
            if is_work_hours:
                power = _noise(rated * 0.8, 0.1)
            else:
                power = _noise(0.5, 0.3)                 # Near zero when off
        elif device_type == "Printer":
            if is_work_hours and random.random() < 0.15:  # 15% chance printing
                power = _noise(rated * 0.8, 0.1)
            else:
                power = _noise(rated * 0.12, 0.1)         # 12% standby — ENERGY VAMPIRE
        else:
            power = _noise(rated * 0.5, 0.1)

        power = max(0, power)
        current_a = power / VOLTAGE

        readings.append({
            "module": module_id,
            "location": location,
            "sensor": "ACS712-20A",
            "current_ma": round(current_a * 1000, 2),
            "current_a": round(current_a, 4),
            "rms_a": round(current_a * 1.01, 4),
            "adc_samples": 1000,
            "vref": 3.3,
            "wifi_rssi": random.randint(-75, -40),
            "received_at": t,
            "source": "test_seed",
            "type": "current",
        })
        t += interval

    return readings


def generate_occupancy_data(location: str, hours_back: int = 168) -> list:
    """
    Generate occupancy telemetry matching work-hour patterns.

    Occupied during work hours (8-18 weekdays), vacant otherwise.
    Some randomness for realism.
    """
    readings = []
    now = datetime.utcnow()
    start = now - timedelta(hours=hours_back)
    interval = timedelta(minutes=5)

    t = start
    while t <= now:
        hour = t.hour
        day_of_week = t.weekday()
        is_weekend = day_of_week >= 5
        is_work_hours = 8 <= hour <= 18 and not is_weekend

        if is_work_hours:
            occupied = random.random() < 0.9   # 90% occupied during work
        else:
            occupied = random.random() < 0.05  # 5% chance someone is there

        rcwl = 1 if occupied else 0
        pir = 1 if occupied else 0

        # Temperature: warmer during the day
        base_temp = 28 + 4 * math.sin(math.pi * (hour - 6) / 12) if 6 <= hour <= 18 else 25
        temp = round(_noise(base_temp, 0.03), 1)
        humidity = round(_noise(65, 0.05), 1)

        readings.append({
            "module": f"OCC_{location}",
            "location": location,
            "rcwl": rcwl,
            "pir": pir,
            "rssi": random.randint(-70, -35),
            "uptime": random.randint(1000, 500000),
            "heap": random.randint(20000, 40000),
            "ip": "192.168.1.100",
            "mac": "AA:BB:CC:DD:EE:FF",
            "temperature": temp,
            "humidity": humidity,
            "received_at": t,
            "source": "test_seed",
        })
        t += interval

    return readings


def clean_test_data():
    """Remove all documents inserted by this seed script."""
    r1 = devices_col.delete_many({"device_id": {"$regex": "^TEST_"}})
    r2 = energy_col.delete_many({"source": "test_seed"})
    r3 = analytics_col.delete_many({"source": "test_seed"})
    print(f"Cleaned: {r1.deleted_count} devices, {r2.deleted_count} energy readings, {r3.deleted_count} occupancy readings")


def seed():
    hours_back = 168  # 7 days of data
    locations = set()

    # Insert devices
    print("Inserting test devices...")
    for device in TEST_DEVICES:
        devices_col.update_one(
            {"device_id": device["device_id"]},
            {"$set": device},
            upsert=True,
        )
        locations.add(device["location"])
        print(f"  + {device['device_id']} ({device['device_type']}) at {device['location']}")

    # Insert energy readings per device
    print(f"\nGenerating {hours_back}h of energy readings (5-min intervals)...")
    total_energy = 0
    for device in TEST_DEVICES:
        readings = generate_energy_readings(device, hours_back)
        if readings:
            energy_col.insert_many(readings)
            total_energy += len(readings)
            print(f"  + {device['module_id']}: {len(readings)} readings")

    # Insert occupancy data per location
    print(f"\nGenerating {hours_back}h of occupancy data...")
    total_occ = 0
    for loc in locations:
        occ_data = generate_occupancy_data(loc, hours_back)
        if occ_data:
            analytics_col.insert_many(occ_data)
            total_occ += len(occ_data)
            print(f"  + {loc}: {len(occ_data)} readings")

    print(f"\nDone! Inserted:")
    print(f"  {len(TEST_DEVICES)} devices")
    print(f"  {total_energy} energy readings")
    print(f"  {total_occ} occupancy readings")

    print("\n--- Expected energy vampire results ---")
    print("  TEST_AC_01 (Air Conditioner): standby ~15% of rated → VAMPIRE (Medium)")
    print("  TEST_PC_01 (Computer):        standby ~25% of rated → VAMPIRE (Medium)")
    print("  TEST_PRINTER_01 (Printer):    standby ~12% of rated → VAMPIRE (Medium)")
    print("  TEST_LIGHT_01 (Lighting):     standby ~2% of rated  → NOT a vampire")
    print("  TEST_FAN_01 (Fan):            standby ~1% of rated  → NOT a vampire")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Seed test data into MongoDB")
    parser.add_argument("--clean", action="store_true", help="Remove existing test data before seeding")
    args = parser.parse_args()

    if args.clean:
        print("Cleaning existing test data...\n")
        clean_test_data()
        print()

    seed()
