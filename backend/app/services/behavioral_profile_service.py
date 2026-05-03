# backend/app/services/behavioral_profile_service.py
"""
Behavioral Profiling & Energy Vampire Detection Service

Builds per-device consumption profiles by correlating energy readings
with occupancy data. Flags "energy vampires" — devices that draw
significant power when the room is vacant.
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from pathlib import Path
import sys

backend_dir = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(backend_dir))

from database import devices_col, energy_col, analytics_col
from app.services.data_cleaning import DataCleaner


# Thresholds for energy vampire detection
IDLE_POWER_THRESHOLD_W = 5.0     # Minimum idle draw to be considered non-trivial
STANDBY_RATIO_MEDIUM = 0.1       # >10% of rated power while idle = Medium vampire
STANDBY_RATIO_HIGH = 0.3         # >30% of rated power while idle = High vampire
DEFAULT_VOLTAGE = 230             # Sri Lanka mains voltage


class BehavioralProfileService:

    def __init__(self):
        self.cleaner = DataCleaner()

    # ------------------------------------------------------------------
    # Data helpers
    # ------------------------------------------------------------------

    def _get_devices(self, device_id: Optional[str] = None,
                     location: Optional[str] = None) -> List[dict]:
        """Fetch devices from MongoDB, optionally filtered."""
        query = {}
        if device_id:
            query["device_id"] = device_id
        if location:
            query["location"] = location
        return list(devices_col.find(query, {"_id": 0}))

    def _get_energy_readings(self, module_id: str, hours_back: int) -> pd.DataFrame:
        """Get energy readings for a specific module within a time window."""
        cutoff = datetime.utcnow() - timedelta(hours=hours_back)
        cursor = energy_col.find(
            {"module": module_id, "received_at": {"$gte": cutoff}},
            {"_id": 0}
        ).sort("received_at", 1)

        rows = []
        for doc in cursor:
            received_at = doc.get("received_at")
            if isinstance(received_at, dict) and "$date" in received_at:
                received_at = datetime.fromisoformat(
                    received_at["$date"].replace("Z", "+00:00")
                )
            elif not isinstance(received_at, datetime):
                continue

            current_a = doc.get("current_a", 0) or 0
            rows.append({
                "module": doc.get("module"),
                "location": doc.get("location"),
                "current_a": current_a,
                "power_w": current_a * DEFAULT_VOLTAGE,
                "received_at": received_at,
            })

        return pd.DataFrame(rows) if rows else pd.DataFrame()

    def _get_occupancy(self, location: str, hours_back: int) -> pd.DataFrame:
        """Get occupancy telemetry for a location within a time window."""
        cutoff = datetime.utcnow() - timedelta(hours=hours_back)
        cursor = analytics_col.find(
            {"location": location, "received_at": {"$gte": cutoff}},
            {"_id": 0}
        ).sort("received_at", 1)

        rows = []
        for doc in cursor:
            received_at = doc.get("received_at")
            if isinstance(received_at, dict) and "$date" in received_at:
                received_at = datetime.fromisoformat(
                    received_at["$date"].replace("Z", "+00:00")
                )
            elif not isinstance(received_at, datetime):
                continue

            rcwl = doc.get("rcwl", 0) or 0
            pir = doc.get("pir", 0) or 0
            rows.append({
                "location": doc.get("location"),
                "rcwl": rcwl,
                "pir": pir,
                "occupied": int(rcwl == 1 or pir == 1),
                "temperature": doc.get("temperature"),
                "humidity": doc.get("humidity"),
                "received_at": received_at,
            })

        return pd.DataFrame(rows) if rows else pd.DataFrame()

    def _merge_energy_occupancy(self, energy_df: pd.DataFrame,
                                 occupancy_df: pd.DataFrame) -> pd.DataFrame:
        """Merge energy and occupancy DataFrames on a 5-minute time window."""
        if energy_df.empty or occupancy_df.empty:
            # No occupancy data — treat all readings as vacant
            if not energy_df.empty:
                energy_df["occupied"] = 0
            return energy_df

        energy_df = energy_df.copy()
        occupancy_df = occupancy_df.copy()

        energy_df["received_at"] = pd.to_datetime(energy_df["received_at"], utc=True)
        occupancy_df["received_at"] = pd.to_datetime(occupancy_df["received_at"], utc=True)

        # Round to 5-minute windows for merging
        energy_df["time_key"] = energy_df["received_at"].dt.floor("5min")
        occupancy_df["time_key"] = occupancy_df["received_at"].dt.floor("5min")

        # Keep last occupancy reading per window
        occ_grouped = (
            occupancy_df
            .sort_values("received_at")
            .groupby(["location", "time_key"])
            .last()
            .reset_index()[["location", "time_key", "occupied"]]
        )

        merged = pd.merge(
            energy_df, occ_grouped,
            on=["location", "time_key"],
            how="left"
        )

        # Forward-fill missing occupancy, default to 0 (vacant)
        merged["occupied"] = merged["occupied"].ffill().fillna(0).astype(int)

        return merged

    # ------------------------------------------------------------------
    # Profile computation
    # ------------------------------------------------------------------

    def build_profile(self, device_id: str, hours_back: int = 168) -> Optional[dict]:
        """
        Build a behavioral profile for a single device.

        Args:
            device_id: The device to profile.
            hours_back: Analysis window (default 168 = 7 days).

        Returns:
            Profile dict or None if insufficient data.
        """
        devices = self._get_devices(device_id=device_id)
        if not devices:
            return None
        device = devices[0]

        module_id = device.get("module_id")
        if not module_id:
            return None

        location = device.get("location", "")
        rated_power = device.get("rated_power_watts", 0) or 1  # avoid division by zero

        # Fetch data
        energy_df = self._get_energy_readings(module_id, hours_back)
        if energy_df.empty:
            return None

        occupancy_df = self._get_occupancy(location, hours_back)
        merged = self._merge_energy_occupancy(energy_df, occupancy_df)

        if merged.empty:
            return None

        return self._compute_profile(device, merged, rated_power, hours_back)

    def build_all_profiles(self, hours_back: int = 168,
                           location: Optional[str] = None) -> List[dict]:
        """Build profiles for all devices (optionally filtered by location)."""
        devices = self._get_devices(location=location)
        profiles = []

        # Pre-fetch occupancy per location to avoid repeated queries
        locations = set(d.get("location", "") for d in devices)
        occupancy_cache: Dict[str, pd.DataFrame] = {}
        for loc in locations:
            if loc:
                occupancy_cache[loc] = self._get_occupancy(loc, hours_back)

        for device in devices:
            module_id = device.get("module_id")
            if not module_id:
                continue

            loc = device.get("location", "")
            rated_power = device.get("rated_power_watts", 0) or 1

            energy_df = self._get_energy_readings(module_id, hours_back)
            if energy_df.empty:
                continue

            occ_df = occupancy_cache.get(loc, pd.DataFrame())
            merged = self._merge_energy_occupancy(energy_df, occ_df)

            if merged.empty:
                continue

            profile = self._compute_profile(device, merged, rated_power, hours_back)
            if profile:
                profiles.append(profile)

        return profiles

    def get_energy_vampires(self, hours_back: int = 168,
                            location: Optional[str] = None) -> List[dict]:
        """Return only devices flagged as energy vampires."""
        profiles = self.build_all_profiles(hours_back=hours_back, location=location)
        return [p for p in profiles if p["is_energy_vampire"]]

    # ------------------------------------------------------------------
    # Internal computation
    # ------------------------------------------------------------------

    def _compute_profile(self, device: dict, df: pd.DataFrame,
                         rated_power: int, hours_back: int) -> dict:
        """Compute the behavioral profile from merged energy+occupancy data."""
        df = df.copy()
        df["received_at"] = pd.to_datetime(df["received_at"], utc=True)
        df["hour"] = df["received_at"].dt.hour

        occupied_df = df[df["occupied"] == 1]
        vacant_df = df[df["occupied"] == 0]

        avg_power_occupied = float(occupied_df["power_w"].mean()) if len(occupied_df) > 0 else 0.0
        avg_power_vacant = float(vacant_df["power_w"].mean()) if len(vacant_df) > 0 else 0.0

        standby_ratio = avg_power_vacant / rated_power if rated_power > 0 else 0.0

        # Hourly profile
        hourly = (
            df.groupby("hour")["power_w"]
            .mean()
            .reindex(range(24), fill_value=0.0)
        )
        hourly_profile = [
            {"hour": int(h), "avg_power_w": round(float(v), 2)}
            for h, v in hourly.items()
        ]

        # Energy waste — total kWh consumed during vacant periods
        # Estimate: each reading represents ~5 minutes (0.0833 hours)
        if len(vacant_df) > 1:
            time_diffs = vacant_df["received_at"].diff().dt.total_seconds().fillna(300)
            # Cap individual gaps at 15 minutes to avoid inflating waste
            time_diffs = time_diffs.clip(upper=900)
            energy_waste_wh = (vacant_df["power_w"].values * time_diffs.values / 3600).sum()
            energy_waste_kwh = float(energy_waste_wh / 1000)
        else:
            energy_waste_kwh = 0.0

        # Energy vampire classification
        is_vampire = (
            avg_power_vacant > IDLE_POWER_THRESHOLD_W
            and standby_ratio > STANDBY_RATIO_MEDIUM
        )

        severity = None
        if is_vampire:
            severity = "High" if standby_ratio > STANDBY_RATIO_HIGH else "Medium"

        return {
            "device_id": device.get("device_id", ""),
            "device_name": device.get("device_name", ""),
            "device_type": device.get("device_type", ""),
            "location": device.get("location", ""),
            "rated_power_watts": rated_power,
            "avg_power_occupied": round(avg_power_occupied, 2),
            "avg_power_vacant": round(avg_power_vacant, 2),
            "standby_ratio": round(standby_ratio, 4),
            "hourly_profile": hourly_profile,
            "energy_waste_kwh": round(energy_waste_kwh, 4),
            "is_energy_vampire": is_vampire,
            "vampire_severity": severity,
            "total_readings": len(df),
            "vacant_readings": len(vacant_df),
            "analysis_period_hours": hours_back,
            "generated_at": datetime.utcnow().isoformat(),
        }
