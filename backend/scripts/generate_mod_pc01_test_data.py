#!/usr/bin/env python3
"""
Generate test data for MOD_PC_01 to validate model accuracy.

Payload formats match IoT device output:
  - Energy:  module, location, sensor, current_ma, current_a, adc_samples, vref,
             wifi_rssi, counter, uptime_ms, relay_state, received_at (added)
  - Telemetry: module, location, rcwl, pir, rssi, uptime, heap, ip, mac,
               temperature, humidity, received_at (added)

Usage:
  cd backend
  python scripts/generate_mod_pc01_test_data.py                    # Write JSON only
  python scripts/generate_mod_pc01_test_data.py --insert           # Insert into MongoDB
  python scripts/generate_mod_pc01_test_data.py --insert --clean   # Clean MOD_PC_01 test data first
  python scripts/generate_mod_pc01_test_data.py --days 3          # 3 days per scenario (default 7)
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from database import energy_col, analytics_col

# ---------------------------------------------------------------------------
# Config: MOD_PC_01 (PC / workstation, 350W rated)
# ---------------------------------------------------------------------------
MODULE_ID = "MOD_PC_01"
LOCATION = "M_ROOM"
RATED_POWER_W = 350
VOLTAGE = 230  # Sri Lanka mains

# Default: 7 days of data, 5-minute intervals (2016 readings per week per scenario)
INTERVAL_MINUTES = 5


def _noise(base: float, pct: float = 0.05) -> float:
    return base * (1 + random.uniform(-pct, pct))


def _energy_doc(
    t: datetime,
    current_a: float,
    counter: int,
    relay_state: str = "ON",
    source: str = "test_mod_pc01",
) -> dict:
    """Build one energy reading in IoT payload format."""
    current_ma = round(current_a * 1000, 2)
    return {
        "module": MODULE_ID,
        "location": LOCATION,
        "sensor": "ACS712-20A",
        "current_ma": current_ma,
        "current_a": round(current_a, 4),
        "adc_samples": 200,
        "vref": 3.3,
        "wifi_rssi": random.randint(-65, -45),
        "counter": counter,
        "uptime_ms": random.randint(500000, 6000000),
        "relay_state": relay_state,
        "received_at": t,
        "source": source,
    }


def _telemetry_doc(t: datetime, occupied: bool, source: str = "test_mod_pc01") -> dict:
    """Build one occupancy telemetry reading in IoT payload format."""
    return {
        "module": "MOD001",  # occupancy sensor module for same room
        "location": LOCATION,
        "rcwl": 1 if occupied else 0,
        "pir": 1 if occupied else 0,
        "rssi": random.randint(-60, -40),
        "uptime": random.randint(60, 500000),
        "heap": random.randint(35000, 45000),
        "ip": "10.36.15.193",
        "mac": "60:01:94:36:A2:F4",
        "temperature": round(_noise(28 + 4 * math.sin(math.pi * (t.hour - 6) / 12) if 6 <= t.hour <= 18 else 26, 0.03), 1),
        "humidity": round(_noise(65, 0.05), 1),
        "received_at": t,
        "source": source,
    }


# ---------------------------------------------------------------------------
# Test scenarios (each returns list of energy readings)
# ---------------------------------------------------------------------------

def scenario_normal_baseline(start: datetime, end: datetime, interval: timedelta) -> list:
    """
    TC-01: Normal PC usage — work hours ~60% load, off-hours ~25% standby (energy vampire).
    Use for: LSTM baseline accuracy, behavioral profile, energy vampire detection.
    """
    readings = []
    counter = 0
    t = start
    while t <= end:
        hour, dow = t.hour, t.weekday()
        is_work = 8 <= hour <= 18 and dow < 5
        if is_work:
            current_a = (RATED_POWER_W * 0.6 / VOLTAGE) * (1 + random.uniform(-0.12, 0.12))
        else:
            current_a = (RATED_POWER_W * 0.25 / VOLTAGE) * (1 + random.uniform(-0.08, 0.08))
        current_a = max(0.01, current_a)
        readings.append(_energy_doc(t, current_a, counter))
        counter += 1
        t += interval
    return readings


def scenario_stable_low(start: datetime, end: datetime, interval: timedelta) -> list:
    """
    TC-02: Stable low (sleep/idle) — constant ~5% of rated.
    Use for: Prediction stability, no anomaly.
    """
    readings = []
    base = RATED_POWER_W * 0.05 / VOLTAGE
    counter = 0
    t = start
    while t <= end:
        current_a = max(0.01, _noise(base, 0.03))
        readings.append(_energy_doc(t, current_a, counter))
        counter += 1
        t += interval
    return readings


def scenario_stable_high(start: datetime, end: datetime, interval: timedelta) -> list:
    """
    TC-03: Stable high (gaming/load) — constant ~85% of rated.
    Use for: Upper range prediction, no anomaly if consistent.
    """
    readings = []
    base = RATED_POWER_W * 0.85 / VOLTAGE
    counter = 0
    t = start
    while t <= end:
        current_a = _noise(base, 0.04)
        readings.append(_energy_doc(t, current_a, counter))
        counter += 1
        t += interval
    return readings


def scenario_spike_anomaly(start: datetime, end: datetime, interval: timedelta) -> list:
    """
    TC-04: Power spike — normal baseline with one short spike to ~2x rated (e.g. 2 hours).
    Use for: Anomaly detection (Isolation Forest / Autoencoder should flag spike).
    """
    readings = []
    spike_start = start + (end - start) * 0.4  # 40% into period
    spike_end = spike_start + timedelta(hours=2)
    counter = 0
    t = start
    while t <= end:
        hour, dow = t.hour, t.weekday()
        is_work = 8 <= hour <= 18 and dow < 5
        if spike_start <= t <= spike_end:
            current_a = (RATED_POWER_W * 2.0 / VOLTAGE) * (1 + random.uniform(-0.05, 0.05))
        elif is_work:
            current_a = (RATED_POWER_W * 0.6 / VOLTAGE) * (1 + random.uniform(-0.1, 0.1))
        else:
            current_a = (RATED_POWER_W * 0.25 / VOLTAGE) * (1 + random.uniform(-0.08, 0.08))
        current_a = max(0.01, current_a)
        readings.append(_energy_doc(t, current_a, counter))
        counter += 1
        t += interval
    return readings


def scenario_gradual_drift(start: datetime, end: datetime, interval: timedelta) -> list:
    """
    TC-05: Gradual drift — power slowly increases over the week (fault simulation).
    Use for: Anomaly/trend detection, LSTM behavior under non-stationarity.
    """
    readings = []
    total_seconds = (end - start).total_seconds()
    counter = 0
    t = start
    while t <= end:
        progress = (t - start).total_seconds() / total_seconds  # 0 -> 1
        # Base goes from 30% to 90% of rated over the period
        base_ratio = 0.30 + 0.60 * progress
        current_a = (RATED_POWER_W * base_ratio / VOLTAGE) * (1 + random.uniform(-0.06, 0.06))
        current_a = max(0.02, current_a)
        readings.append(_energy_doc(t, current_a, counter))
        counter += 1
        t += interval
    return readings


def scenario_high_variance(start: datetime, end: datetime, interval: timedelta) -> list:
    """
    TC-06: High variance — same mean as normal but large random swings.
    Use for: Model robustness to noise; anomaly detector may flag some points.
    """
    readings = []
    mean_ratio = 0.45
    counter = 0
    t = start
    while t <= end:
        ratio = mean_ratio + random.uniform(-0.35, 0.35)
        ratio = max(0.05, min(0.95, ratio))
        current_a = RATED_POWER_W * ratio / VOLTAGE
        current_a = max(0.01, current_a)
        readings.append(_energy_doc(t, current_a, counter))
        counter += 1
        t += interval
    return readings


def scenario_weekend_off(start: datetime, end: datetime, interval: timedelta) -> list:
    """
    TC-07: Weekend off — weekdays normal, weekends near-zero (PC off).
    Use for: LSTM day-of-week pattern, behavioral profile occupancy link.
    """
    readings = []
    counter = 0
    t = start
    while t <= end:
        dow = t.weekday()
        if dow >= 5:  # Saturday, Sunday
            current_a = _noise(0.02, 0.5)  # ~4.6W standby
        else:
            hour = t.hour
            if 8 <= hour <= 18:
                current_a = (RATED_POWER_W * 0.6 / VOLTAGE) * (1 + random.uniform(-0.1, 0.1))
            else:
                current_a = (RATED_POWER_W * 0.25 / VOLTAGE) * (1 + random.uniform(-0.08, 0.08))
        current_a = max(0.01, current_a)
        readings.append(_energy_doc(t, current_a, counter))
        counter += 1
        t += interval
    return readings


def scenario_sudden_drop(start: datetime, end: datetime, interval: timedelta) -> list:
    """
    TC-08: Sudden drop — normal then drops to near zero for 6 hours (power off).
    Use for: Handling regime change; prediction may overshoot after drop.
    """
    readings = []
    drop_start = start + (end - start) * 0.35
    drop_end = drop_start + timedelta(hours=6)
    counter = 0
    t = start
    while t <= end:
        if drop_start <= t <= drop_end:
            current_a = _noise(0.01, 0.3)
        else:
            hour, dow = t.hour, t.weekday()
            is_work = 8 <= hour <= 18 and dow < 5
            if is_work:
                current_a = (RATED_POWER_W * 0.6 / VOLTAGE) * (1 + random.uniform(-0.1, 0.1))
            else:
                current_a = (RATED_POWER_W * 0.25 / VOLTAGE) * (1 + random.uniform(-0.08, 0.08))
        current_a = max(0.005, current_a)
        readings.append(_energy_doc(t, current_a, counter))
        counter += 1
        t += interval
    return readings


# ---------------------------------------------------------------------------
# Telemetry (occupancy) for M_ROOM — aligned with normal/TC-01 pattern
# ---------------------------------------------------------------------------

def generate_telemetry(start: datetime, end: datetime, interval: timedelta, source: str = "test_mod_pc01") -> list:
    """Occupancy: work hours 8–18 weekdays ~90% occupied, else ~5%."""
    out = []
    t = start
    while t <= end:
        hour, dow = t.hour, t.weekday()
        is_work = 8 <= hour <= 18 and dow < 5
        occupied = random.random() < (0.9 if is_work else 0.05)
        out.append(_telemetry_doc(t, occupied, source))
        t += interval
    return out


# ---------------------------------------------------------------------------
# Serialization for JSON (datetime -> ISO string)
# ---------------------------------------------------------------------------

def _serialize_doc(d: dict) -> dict:
    out = dict(d)
    if "received_at" in out and hasattr(out["received_at"], "isoformat"):
        ts = out["received_at"].isoformat()
        out["received_at"] = ts.replace("+00:00", "Z") if "+00:00" in ts else (ts + "Z" if "Z" not in ts and "+" not in ts else ts)
    return out


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

SCENARIOS = {
    "tc01_normal_baseline": scenario_normal_baseline,
    "tc02_stable_low": scenario_stable_low,
    "tc03_stable_high": scenario_stable_high,
    "tc04_spike_anomaly": scenario_spike_anomaly,
    "tc05_gradual_drift": scenario_gradual_drift,
    "tc06_high_variance": scenario_high_variance,
    "tc07_weekend_off": scenario_weekend_off,
    "tc08_sudden_drop": scenario_sudden_drop,
}


def main():
    ap = argparse.ArgumentParser(description="Generate MOD_PC_01 test data for model accuracy")
    ap.add_argument("--days", type=int, default=7, help="Days of data per scenario (default 7)")
    ap.add_argument("--output-dir", type=str, default=None, help="Write JSON here (default: backend/test_data/mod_pc01)")
    ap.add_argument("--insert", action="store_true", help="Insert into MongoDB (energy_readings + occupancy_telemetry)")
    ap.add_argument("--scenario", type=str, default="tc01_normal_baseline",
                    choices=list(SCENARIOS.keys()),
                    help="Which scenario to insert when using --insert (default: tc01_normal_baseline)")
    ap.add_argument("--clean", action="store_true", help="Remove existing test data for MOD_PC_01 / test_mod_pc01 before insert")
    args = ap.parse_args()

    days = max(1, min(args.days, 30))
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days)
    interval = timedelta(minutes=INTERVAL_MINUTES)

    out_dir = Path(args.output_dir) if args.output_dir else backend_dir / "test_data" / "mod_pc01"
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.clean and args.insert:
        r1 = energy_col.delete_many({"module": MODULE_ID, "source": "test_mod_pc01"})
        r2 = analytics_col.delete_many({"location": LOCATION, "source": "test_mod_pc01"})
        print(f"Cleaned: {r1.deleted_count} energy, {r2.deleted_count} telemetry")

    # Generate telemetry once (same for all scenarios; used with any energy insert)
    telemetry = generate_telemetry(start, now, interval)
    telemetry_path = out_dir / "occupancy_telemetry_M_ROOM.json"
    with open(telemetry_path, "w") as f:
        json.dump([_serialize_doc(d) for d in telemetry], f, indent=2)
    print(f"Wrote {len(telemetry)} telemetry readings -> {telemetry_path}")

    all_energy = []
    for name, fn in SCENARIOS.items():
        readings = fn(start, now, interval)
        all_energy.extend(readings)
        path = out_dir / f"energy_{name}.json"
        with open(path, "w") as f:
            json.dump([_serialize_doc(d) for d in readings], f, indent=2)
        print(f"Wrote {len(readings)} energy readings -> {path}")

    # Single combined energy file (all scenarios concatenated) for offline analysis only
    # (Do not insert combined — same timestamps would be duplicated.)
    combined_path = out_dir / "energy_all_scenarios_combined.json"
    with open(combined_path, "w") as f:
        json.dump([_serialize_doc(d) for d in all_energy], f, indent=2)
    print(f"Wrote {len(all_energy)} combined energy -> {combined_path}")

    if args.insert:
        to_insert = SCENARIOS[args.scenario](start, now, interval)
        energy_col.insert_many(to_insert)
        analytics_col.insert_many(telemetry)
        print(f"Inserted scenario '{args.scenario}': {len(to_insert)} energy + {len(telemetry)} telemetry into MongoDB.")

    print("\nTest scenarios generated. See backend/docs/TEST_CASES_MOD_PC_01.md for expected model behavior.")


if __name__ == "__main__":
    main()
