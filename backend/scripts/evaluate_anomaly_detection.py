"""
Synthetic Anomaly Evaluation Script
====================================
Evaluates Isolation Forest and Autoencoder anomaly detectors using a
controlled test set with injected known anomalies.

Methodology:
  1. Load clean_dataset.csv (chronological)
  2. Hold out last 20% as test set (unseen during model training)
  3. Inject synthetic anomalies into the test set:
       - Randomly select 10% of rows
       - Multiply power_w by a random factor of 3-5x
       - Create ground-truth label: anomaly_label = 1
  4. Run each trained model on the labeled test set
  5. Compute precision, recall, F1 using sklearn.metrics
  6. Save results to models/anomaly_evaluation.json

Usage:
    cd backend
    python scripts/evaluate_anomaly_detection.py

Requirements: Run from the backend/ directory where models/ and clean_dataset.csv exist.
"""

import sys
import json
import pickle
import warnings
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime, timezone

warnings.filterwarnings("ignore")

# ── Path setup ────────────────────────────────────────────────────────────────
BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))
MODELS_DIR = BACKEND_DIR / "models"
DATASET_PATH = BACKEND_DIR / "clean_dataset.csv"

from sklearn.metrics import precision_score, recall_score, f1_score

# ── Helpers ───────────────────────────────────────────────────────────────────

def load_dataset() -> pd.DataFrame:
    if not DATASET_PATH.exists():
        raise FileNotFoundError(f"Dataset not found: {DATASET_PATH}")
    df = pd.read_csv(DATASET_PATH)
    if "received_at" in df.columns:
        df = df.sort_values("received_at").reset_index(drop=True)
    return df


def inject_anomalies(df: pd.DataFrame, injection_rate: float = 0.10,
                     spike_min: float = 3.0, spike_max: float = 5.0,
                     seed: int = 42) -> pd.DataFrame:
    """
    Inject synthetic anomalies into the dataframe.
    Selects `injection_rate` fraction of rows at random and multiplies
    power_w (and related columns) by a random factor in [spike_min, spike_max].
    Returns a copy with added `anomaly_label` column (1 = anomaly, 0 = normal).
    """
    rng = np.random.default_rng(seed)
    df = df.copy()
    n = len(df)
    n_inject = max(1, int(n * injection_rate))

    idx = rng.choice(n, size=n_inject, replace=False)
    df["anomaly_label"] = 0

    spike_factors = rng.uniform(spike_min, spike_max, size=n_inject)
    for i, factor in zip(idx, spike_factors):
        for col in ["power_w", "current_a", "current_ma", "power_kwh"]:
            if col in df.columns:
                df.at[i, col] = df.at[i, col] * factor
    df.loc[idx, "anomaly_label"] = 1

    return df, n_inject


def evaluate_isolation_forest(test_df: pd.DataFrame) -> dict:
    """Load Isolation Forest, run on test_df, return precision/recall/f1."""
    model_path = MODELS_DIR / "anomaly_model.pkl"
    if not model_path.exists():
        print("  [SKIP] anomaly_model.pkl not found.")
        return {"status": "model_not_found"}

    with open(model_path, "rb") as f:
        bundle = pickle.load(f)

    model = bundle["model"]
    scaler = bundle["scaler"]
    feature_cols = bundle["feature_cols"]

    # Align columns
    missing = set(feature_cols) - set(test_df.columns)
    for col in missing:
        test_df[col] = 0

    X = test_df[feature_cols].fillna(0)
    X_scaled = scaler.transform(X)

    preds = model.predict(X_scaled)  # -1 = anomaly, 1 = normal
    y_pred = (preds == -1).astype(int)
    y_true = test_df["anomaly_label"].values

    precision = round(float(precision_score(y_true, y_pred, zero_division=0)), 4)
    recall = round(float(recall_score(y_true, y_pred, zero_division=0)), 4)
    f1 = round(float(f1_score(y_true, y_pred, zero_division=0)), 4)

    print(f"  Isolation Forest — Precision: {precision:.3f}  Recall: {recall:.3f}  F1: {f1:.3f}")
    return {"precision": precision, "recall": recall, "f1": f1}


def evaluate_autoencoder(test_df: pd.DataFrame) -> dict:
    """Load Autoencoder, compute reconstruction error, threshold at 90th pct."""
    model_path = MODELS_DIR / "autoencoder_model.h5"
    if not model_path.exists():
        print("  [SKIP] autoencoder_model.h5 not found.")
        return {"status": "model_not_found"}

    try:
        from tensorflow.keras.models import load_model
        from sklearn.preprocessing import StandardScaler
    except ImportError:
        print("  [SKIP] TensorFlow not installed.")
        return {"status": "tensorflow_not_installed"}

    autoencoder = load_model(model_path, compile=False)
    n_features = autoencoder.input_shape[-1]

    # Build a numeric feature matrix matching the autoencoder's expected shape
    numeric_cols = test_df.select_dtypes(include=[np.number]).columns.tolist()
    numeric_cols = [c for c in numeric_cols if c != "anomaly_label"]

    # Pad or trim to n_features
    if len(numeric_cols) < n_features:
        for i in range(n_features - len(numeric_cols)):
            test_df[f"_pad_{i}"] = 0
            numeric_cols.append(f"_pad_{i}")
    numeric_cols = numeric_cols[:n_features]

    X = test_df[numeric_cols].fillna(0).values
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    reconstructions = autoencoder.predict(X_scaled, verbose=0)
    mse = np.mean(np.power(X_scaled - reconstructions, 2), axis=1)

    threshold = np.percentile(mse, 90)  # flag top 10% as anomalous
    y_pred = (mse > threshold).astype(int)
    y_true = test_df["anomaly_label"].values

    precision = round(float(precision_score(y_true, y_pred, zero_division=0)), 4)
    recall = round(float(recall_score(y_true, y_pred, zero_division=0)), 4)
    f1 = round(float(f1_score(y_true, y_pred, zero_division=0)), 4)

    print(f"  Autoencoder     — Precision: {precision:.3f}  Recall: {recall:.3f}  F1: {f1:.3f}")
    return {"precision": precision, "recall": recall, "f1": f1,
            "threshold_mse": round(float(threshold), 6)}


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("Anomaly Detection Evaluation — Synthetic Injection Method")
    print("=" * 60)

    print("\n[1] Loading dataset...")
    df = load_dataset()
    n_total = len(df)
    print(f"  Total records: {n_total}")

    # Chronological 80/20 split — use the same split as LSTM training
    split_idx = int(n_total * 0.8)
    test_df_clean = df.iloc[split_idx:].copy().reset_index(drop=True)
    print(f"  Test set (last 20%): {len(test_df_clean)} records")

    print("\n[2] Injecting synthetic anomalies (10% rate, 3-5x power spike)...")
    test_df, n_injected = inject_anomalies(test_df_clean, injection_rate=0.10)
    print(f"  Injected {n_injected} anomalies into {len(test_df)} test records")

    print("\n[3] Evaluating Isolation Forest...")
    iso_results = evaluate_isolation_forest(test_df.copy())

    print("\n[4] Evaluating Autoencoder...")
    ae_results = evaluate_autoencoder(test_df.copy())

    output = {
        "isolation_forest": iso_results,
        "autoencoder": ae_results,
        "test_set_size": len(test_df),
        "injected_anomaly_count": n_injected,
        "injection_rate_pct": 10.0,
        "injection_method": "3x-5x power multiplier on randomly selected 10% of test rows",
        "split_method": "chronological_80_20",
        "evaluated_at": datetime.now(timezone.utc).isoformat(),
    }

    out_path = MODELS_DIR / "anomaly_evaluation.json"
    with open(out_path, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\n[5] Results saved to {out_path}")
    print("=" * 60)
    print("Evaluation complete.")
    print("Now accessible via GET /model-evaluation/anomaly-metrics and GET /faults/model-stats")
    print("=" * 60)


if __name__ == "__main__":
    main()
