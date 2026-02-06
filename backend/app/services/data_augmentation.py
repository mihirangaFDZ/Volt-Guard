import numpy as np
import pandas as pd
from datetime import timedelta
from typing import Dict, Optional

from app.services.feature_engineering import FeatureEngineer

ENGINEERED_BASE_COLS = {
    "hour_sin",
    "hour_cos",
    "day_sin",
    "day_cos",
}


def _drop_engineered_columns(df: pd.DataFrame) -> pd.DataFrame:
    drop_cols = set()
    for col in df.columns:
        if (
            col in ENGINEERED_BASE_COLS
            or col.startswith("daily_")
            or "_rolling_" in col
            or col.endswith("_lag_1")
            or col.endswith("_lag_2")
        ):
            drop_cols.add(col)
    return df.drop(columns=list(drop_cols), errors="ignore")


def _recompute_time_columns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["received_at"] = pd.to_datetime(df["received_at"], utc=True, format="mixed")
    df["hour"] = df["received_at"].dt.hour
    df["day_of_week"] = df["received_at"].dt.dayofweek
    df["is_weekend"] = df["day_of_week"].isin([5, 6]).astype(int)
    df["time_key"] = df["received_at"]
    df["time_window"] = df["received_at"].dt.round("5min")
    return df


def _apply_physical_constraints(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    if "current_a" in df.columns:
        df["current_a"] = df["current_a"].clip(lower=0)
        df["current_ma"] = df["current_a"] * 1000.0
    if "voltage_v" in df.columns:
        if "vref" in df.columns:
            df["voltage_v"] = df["voltage_v"].fillna(df["vref"])
        df["voltage_v"] = df["voltage_v"].fillna(230.0)
    if "power_w" in df.columns and "current_a" in df.columns and "voltage_v" in df.columns:
        df["power_w"] = df["current_a"] * df["voltage_v"]
        df["power_kwh"] = df["power_w"] / 1000.0
    if "temperature" in df.columns:
        df["temperature"] = df["temperature"].clip(lower=-10, upper=60)
    if "humidity" in df.columns:
        df["humidity"] = df["humidity"].clip(lower=0, upper=100)
    if "wifi_rssi" in df.columns:
        df["wifi_rssi"] = df["wifi_rssi"].clip(lower=-100, upper=0)
    for col in ["rcwl", "pir", "occupied"]:
        if col in df.columns:
            df[col] = df[col].fillna(0).astype(int)
            df[col] = df[col].clip(lower=0, upper=1)
    return df


def _jitter_block(block: pd.DataFrame, rng: np.random.Generator, noise_cfg: Dict) -> pd.DataFrame:
    block = block.copy()
    noise_pct = noise_cfg.get("current_a_pct", 0.03)
    if "current_a" in block.columns:
        scale = 1.0 + rng.normal(0, noise_pct, size=len(block))
        block["current_a"] = block["current_a"] * scale
    if "temperature" in block.columns:
        block["temperature"] = block["temperature"] + rng.normal(
            0, noise_cfg.get("temperature_std", 0.2), size=len(block)
        )
    if "humidity" in block.columns:
        block["humidity"] = block["humidity"] + rng.normal(
            0, noise_cfg.get("humidity_std", 0.5), size=len(block)
        )
    if "wifi_rssi" in block.columns:
        block["wifi_rssi"] = block["wifi_rssi"] + rng.normal(
            0, noise_cfg.get("wifi_rssi_std", 1.0), size=len(block)
        )
    return block


def augment_clean_dataset(
    input_csv: str,
    output_csv: str,
    multiplier: float = 3.0,
    block_size: int = 12,
    seed: int = 42,
    noise_cfg: Optional[Dict] = None,
) -> pd.DataFrame:
    """
    Expand a clean dataset using block bootstrap + light jitter.
    Keeps physical constraints and recomputes engineered features.
    """
    if multiplier <= 1:
        raise ValueError("multiplier must be > 1 to expand the dataset")

    rng = np.random.default_rng(seed)
    noise_cfg = noise_cfg or {}

    df = pd.read_csv(input_csv)
    df = _drop_engineered_columns(df)
    df = _recompute_time_columns(df)
    df = _apply_physical_constraints(df)

    augmented_rows = []

    for location, group in df.groupby("location"):
        group = group.sort_values("received_at").reset_index(drop=True)
        if len(group) == 0:
            continue

        target_rows = int(np.ceil(len(group) * (multiplier - 1)))
        block_count = 0
        rows_added = 0

        if len(group) < block_size:
            # Fallback: sample rows with replacement
            sample_idx = rng.integers(0, len(group), size=target_rows)
            sampled = group.iloc[sample_idx].copy()
            sampled = _jitter_block(sampled, rng, noise_cfg)
            sampled["received_at"] = sampled["received_at"] + timedelta(days=7)
            augmented_rows.append(sampled)
            continue

        while rows_added < target_rows:
            start_idx = int(rng.integers(0, len(group) - block_size + 1))
            block = group.iloc[start_idx : start_idx + block_size].copy()
            block = _jitter_block(block, rng, noise_cfg)

            # Shift by full weeks to preserve day-of-week patterns
            block_count += 1
            block["received_at"] = block["received_at"] + timedelta(days=7 * block_count)

            augmented_rows.append(block)
            rows_added += len(block)

    if augmented_rows:
        augmented_df = pd.concat(augmented_rows, ignore_index=True)
        combined = pd.concat([df, augmented_df], ignore_index=True)
    else:
        combined = df.copy()

    combined = _recompute_time_columns(combined)
    combined = _apply_physical_constraints(combined)

    feature_engineer = FeatureEngineer()
    combined = feature_engineer.prepare_features(combined)

    combined.to_csv(output_csv, index=False)
    return combined
