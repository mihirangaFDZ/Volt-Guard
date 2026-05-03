"""
Model Evaluation API
Exposes research-grade metrics for LSTM prediction quality, anomaly detection
precision/recall, and dataset quality. These endpoints power the Research
Metrics panel in the mobile app.
"""
from fastapi import APIRouter
from app.services import model_evaluation_service as svc

router = APIRouter(
    prefix="/model-evaluation",
    tags=["Model Evaluation"],
)


@router.get("/lstm-metrics")
def lstm_metrics():
    """
    RMSE, MAE, R² for the LSTM prediction model on the held-out test set,
    plus improvement percentages versus two naive baselines.
    """
    return svc.get_lstm_metrics()


@router.get("/model-comparison")
def model_comparison():
    """
    Side-by-side RMSE comparison: LSTM vs last-value baseline vs
    rolling-mean baseline.
    """
    return svc.get_model_comparison_table()


@router.get("/anomaly-metrics")
def anomaly_metrics():
    """
    Precision, recall, and F1 for Isolation Forest and Autoencoder,
    evaluated via synthetic anomaly injection on the test set.
    """
    return svc.get_anomaly_metrics()


@router.get("/data-quality")
def data_quality():
    """
    Dataset statistics: record count, time window, occupancy rate,
    feature count, and train/test split details.
    """
    return svc.get_data_quality_report()
