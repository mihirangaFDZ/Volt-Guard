"""
Generate a 1500-row CSV dataset for occupancy telemetry analysis recommendations.
Uses the same structure as occupancy_telemetry: module, location, rcwl, pir, rssi,
temperature, humidity, uptime, heap. Each row is labeled with recommendation_type
for environment section (AC in vacant room, motion alignment, link quality, comfort, etc.).

Usage: python scripts/generate_occupancy_telemetry_recommendations_dataset.py
Output: data/occupancy_telemetry_recommendations_dataset.csv
"""

import csv
import random
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
OUTPUT_PATH = BACKEND_DIR / "data" / "occupancy_telemetry_recommendations_dataset.csv"

MODULES = ("MOD_PC_01", "MOD_PC_02", "MOD_ESP_01", "MOD_ESP_02", "MOD_ROOM_01")
LOCATIONS = ("M_ROOM", "LIVING_ROOM", "BEDROOM", "OFFICE", "KITCHEN", "LAB")

# Environment recommendation types (actionable, aligned with analytics _derive_recommendations + extensions)
RECOMMENDATION_TYPES = (
    "turn_off_ac_vacant",      # Vacant, temp high -> save energy (high)
    "align_motion_sensing",     # RCWL/PIR mismatch (medium)
    "check_link_quality",      # Weak/fair RSSI (medium)
    "comfort_guardrails",      # Informational 24-27°C (low)
    "review_comfort_drift",    # Avg temp/humidity drift (low)
    "high_humidity_risk",      # Humidity > 70% mold risk (medium)
    "low_humidity",            # Humidity < 30% dry (low)
    "high_temp_occupied",      # Occupied, temp > 29 (medium)
    "low_temp_occupied",       # Occupied, temp < 22 (low)
    "comfort_ok",              # Good range, no action (low)
    "weak_signal_env",         # RSSI very weak (medium)
)


def _assign_recommendation(
    temperature: float,
    humidity: float,
    rcwl: int,
    pir: int,
    rssi: int,
) -> tuple:
    """Return (recommendation_type, severity). Priority order matters."""
    occupied = rcwl == 1 or pir == 1

    # Signal first (device issue)
    if rssi < -80:
        return ("weak_signal_env", "medium")
    if rssi < -75:
        return ("check_link_quality", "medium")

    # Vacant + high temp -> turn off AC
    if not occupied and temperature > 30:
        return ("turn_off_ac_vacant", "high")
    if not occupied and temperature > 28:
        return ("turn_off_ac_vacant", "medium")

    # High humidity risk
    if humidity > 75:
        return ("high_humidity_risk", "high")
    if humidity > 70:
        return ("high_humidity_risk", "medium")

    # Occupied comfort
    if occupied and temperature > 29:
        return ("high_temp_occupied", "medium")
    if occupied and temperature < 20:
        return ("low_temp_occupied", "low")
    if humidity < 28:
        return ("low_humidity", "low")

    # Motion alignment: RCWL=1, PIR=0 pattern (simplified: we use single reading; dataset can have both)
    if rcwl == 1 and pir == 0 and random.random() < 0.25:
        return ("align_motion_sensing", "medium")

    # Narrow comfort guardrails band (24-27°C, 40-55% RH)
    if 24 <= temperature <= 27 and 40 <= humidity <= 55:
        return ("comfort_guardrails", "low")

    # Comfort OK band (wider)
    if 22 <= temperature <= 28 and 35 <= humidity <= 65:
        return ("comfort_ok", "low")

    # Drift / review
    return ("review_comfort_drift", "low")


def generate_row(target_type: str) -> dict:
    """Generate one row targeting a specific recommendation_type with realistic occupancy telemetry."""
    for _ in range(500):
        module = random.choice(MODULES)
        location = random.choice(LOCATIONS)
        rcwl = random.choice((0, 1))
        pir = random.choice((0, 1))
        rssi = random.randint(-90, -50)
        uptime = random.randint(100, 86400)
        heap = random.randint(10000, 50000)

        if target_type == "turn_off_ac_vacant":
            temperature = round(random.uniform(28.5, 35.0), 1)
            humidity = round(random.uniform(40, 70), 1)
            rcwl, pir = 0, 0
        elif target_type == "align_motion_sensing":
            temperature = round(random.uniform(24, 28), 1)
            humidity = round(random.uniform(40, 60), 1)
            rcwl, pir = 1, 0
        elif target_type == "check_link_quality":
            temperature = round(random.uniform(24, 28), 1)
            humidity = round(random.uniform(40, 60), 1)
            rssi = random.randint(-85, -65)
        elif target_type == "weak_signal_env":
            temperature = round(random.uniform(24, 28), 1)
            humidity = round(random.uniform(40, 60), 1)
            rssi = random.randint(-92, -78)
        elif target_type == "comfort_guardrails":
            temperature = round(random.uniform(24, 27), 1)
            humidity = round(random.uniform(40, 55), 1)
        elif target_type == "review_comfort_drift":
            temperature = round(random.uniform(22, 30), 1)
            humidity = round(random.uniform(35, 70), 1)
        elif target_type == "high_humidity_risk":
            temperature = round(random.uniform(26, 32), 1)
            humidity = round(random.uniform(70, 95), 1)
        elif target_type == "low_humidity":
            temperature = round(random.uniform(22, 28), 1)
            humidity = round(random.uniform(15, 30), 1)
        elif target_type == "high_temp_occupied":
            temperature = round(random.uniform(29, 34), 1)
            humidity = round(random.uniform(45, 65), 1)
            rcwl, pir = 1, 1
        elif target_type == "low_temp_occupied":
            temperature = round(random.uniform(16, 21), 1)
            humidity = round(random.uniform(40, 60), 1)
            rcwl, pir = 1, 1
        elif target_type == "comfort_ok":
            temperature = round(random.uniform(24, 27), 1)
            humidity = round(random.uniform(40, 60), 1)
            rcwl, pir = random.choice([(0, 0), (1, 0), (0, 1), (1, 1)])
        else:
            temperature = round(random.uniform(24, 28), 1)
            humidity = round(random.uniform(40, 60), 1)

        rec_type, severity = _assign_recommendation(temperature, humidity, rcwl, pir, rssi)
        if rec_type == target_type:
            return {
                "module": module,
                "location": location,
                "rcwl": rcwl,
                "pir": pir,
                "rssi": rssi,
                "uptime": uptime,
                "heap": heap,
                "temperature": temperature,
                "humidity": humidity,
                "recommendation_type": rec_type,
                "severity": severity,
            }
    return None


def main():
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    n_total = 1500
    n_per_type = max(1, n_total // len(RECOMMENDATION_TYPES))
    rows = []
    for rec_type in RECOMMENDATION_TYPES:
        for _ in range(n_per_type):
            row = generate_row(rec_type)
            if row:
                rows.append(row)
    # Pad to 1500 if needed
    while len(rows) < n_total:
        row = generate_row(random.choice(RECOMMENDATION_TYPES))
        if row:
            rows.append(row)
    rows = rows[:n_total]

    fieldnames = [
        "module", "location", "rcwl", "pir", "rssi", "uptime", "heap",
        "temperature", "humidity", "recommendation_type", "severity",
    ]
    with open(OUTPUT_PATH, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)

    print(f"Generated {len(rows)} rows at {OUTPUT_PATH}")
    for rt in RECOMMENDATION_TYPES:
        count = sum(1 for r in rows if r["recommendation_type"] == rt)
        print(f"  {rt}: {count}")


if __name__ == "__main__":
    main()
