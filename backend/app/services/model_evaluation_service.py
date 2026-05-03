"""
Model Evaluation Service
Reads persisted evaluation JSON files produced during model training/evaluation
and exposes structured metrics for the research API.
"""
import json
from pathlib import Path
from datetime import datetime, timezone
from typing import Any


_MODELS_DIR = Path("models")


def _read_json(filename: str) -> dict | None:
    path = _MODELS_DIR / filename
    if not path.exists():
        return None
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def get_lstm_metrics() -> dict[str, Any]:
    """Return LSTM evaluation metrics from lstm_evaluation.json."""
    data = _read_json("lstm_evaluation.json")
    if data is None:
        return {
            "status": "not_evaluated",
            "note": "Retrain the LSTM model to generate evaluation metrics. "
                    "Trigger POST /ml-training/train-all or run train_ml_models.py.",
        }

    best_baseline = min(
        data.get("baseline_rmse_last_value", float("inf")),
        data.get("baseline_rmse_rolling", float("inf")),
    )
    return {
        "status": "evaluated",
        "rmse": data.get("rmse"),
        "mae": data.get("mae"),
        "r2": data.get("r2"),
        "train_size": data.get("train_size"),
        "test_size": data.get("test_size"),
        "baseline_rmse_last_value": data.get("baseline_rmse_last_value"),
        "baseline_rmse_rolling": data.get("baseline_rmse_rolling"),
        "best_baseline_rmse": round(best_baseline, 4) if best_baseline != float("inf") else None,
        "improvement_vs_best_baseline_pct": data.get("improvement_vs_best_baseline_pct"),
        "ci_90_lower_offset_w": data.get("ci_90_lower_offset_w"),
        "ci_90_upper_offset_w": data.get("ci_90_upper_offset_w"),
        "epochs_trained": data.get("epochs_trained"),
        "sequence_length": data.get("sequence_length"),
        "feature_columns": data.get("feature_columns"),
        "split_method": data.get("split_method", "chronological_80_20"),
        "trained_at": data.get("trained_at"),
    }


def get_model_comparison_table() -> dict[str, Any]:
    """Return side-by-side LSTM vs baseline comparison table."""
    data = _read_json("lstm_evaluation.json")
    if data is None:
        return {"status": "not_evaluated"}

    lstm_rmse = data.get("rmse")
    last_val_rmse = data.get("baseline_rmse_last_value")
    rolling_rmse = data.get("baseline_rmse_rolling")
    improvement = data.get("improvement_vs_best_baseline_pct")

    return {
        "status": "evaluated",
        "comparison": [
            {"model": "LSTM (this system)", "rmse_w": lstm_rmse, "highlight": True},
            {"model": "Last-Value Baseline", "rmse_w": last_val_rmse, "highlight": False},
            {"model": "Rolling-Mean Baseline (24h)", "rmse_w": rolling_rmse, "highlight": False},
        ],
        "improvement_vs_best_baseline_pct": improvement,
        "trained_at": data.get("trained_at"),
    }


def get_anomaly_metrics() -> dict[str, Any]:
    """Return anomaly detection evaluation metrics from anomaly_evaluation.json."""
    data = _read_json("anomaly_evaluation.json")
    if data is None:
        return {
            "status": "not_evaluated",
            "note": "Run backend/scripts/evaluate_anomaly_detection.py to compute precision/recall.",
        }
    return {
        "status": "evaluated",
        "isolation_forest": data.get("isolation_forest", {}),
        "autoencoder": data.get("autoencoder", {}),
        "test_set_size": data.get("test_set_size"),
        "injected_anomaly_count": data.get("injected_anomaly_count"),
        "injection_method": data.get("injection_method"),
        "evaluated_at": data.get("evaluated_at"),
    }


def get_data_quality_report() -> dict[str, Any]:
    """Return dataset quality metadata from clean_dataset_metadata.json."""
    data = _read_json("../clean_dataset_metadata.json")
    # Fallback: try root-level file
    if data is None:
        meta_path = Path("clean_dataset_metadata.json")
        if meta_path.exists():
            try:
                with open(meta_path) as f:
                    data = json.load(f)
            except Exception:
                data = None
    if data is None:
        return {"status": "metadata_not_found"}

    total = data.get("total_records", 0)
    hours = data.get("time_window_hours", 48)
    records_per_hour = round(total / hours, 1) if hours else None

    return {
        "status": "available",
        "total_records": total,
        "time_window_hours": hours,
        "records_per_hour": records_per_hour,
        "feature_count": data.get("feature_count", data.get("n_features")),
        "occupancy_rate_pct": data.get("occupancy_rate_pct", data.get("occupancy_rate")),
        "mean_power_w": data.get("mean_power_w", data.get("mean_power")),
        "split_method": "chronological_80_20",
        "generated_at": data.get("created_at", data.get("generated_at")),
    }
