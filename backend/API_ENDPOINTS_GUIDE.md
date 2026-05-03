# 🔌 API Endpoints Guide - ML Models Integration

## Overview

This guide documents all API endpoints related to ML models for energy analytics, prediction, and anomaly detection.

**Base URL:** `http://localhost:8000` (or your server URL)

**Authentication:** All endpoints require JWT authentication (except `/health`)

---

## 📊 Prediction Endpoints

### 1. Predict Energy Consumption

**Endpoint:** `GET /prediction/predict`

**Description:** Predict future energy consumption using ML models

**Query Parameters:**
- `location` (optional): Filter by location (e.g., "LAB_1")
- `hours_ahead` (optional): Hours ahead to predict (1-168, default: 24)
- `model_type` (optional): Model to use - `"random_forest"` or `"lstm"` (default: "random_forest")

**Example Request:**
```bash
GET /prediction/predict?location=LAB_1&hours_ahead=24&model_type=random_forest
```

**Response (Random Forest):**
```json
{
  "model_type": "random_forest",
  "location": "LAB_1",
  "predicted_power_w": 0.552,
  "predicted_energy_kwh": 0.000552,
  "confidence_score": 0.85,
  "hours_ahead": 24,
  "timestamp": "2026-01-05T02:00:00"
}
```

**Response (LSTM):**
```json
{
  "model_type": "lstm",
  "location": "LAB_1",
  "hours_ahead": 24,
  "predictions": [
    {
      "step": 1,
      "predicted_power_w": 0.548,
      "timestamp": "2026-01-05T03:00:00"
    },
    {
      "step": 2,
      "predicted_power_w": 0.551,
      "timestamp": "2026-01-05T04:00:00"
    }
    // ... more predictions
  ],
  "average_power": 0.552
}
```

---

### 2. Compare Models

**Endpoint:** `GET /prediction/compare`

**Description:** Compare predictions from both Random Forest and LSTM models

**Query Parameters:**
- `location` (optional): Filter by location

**Example Request:**
```bash
GET /prediction/compare?location=LAB_1
```

**Response:**
```json
{
  "location": "LAB_1",
  "random_forest": {
    "predicted_power_w": 0.552,
    "predicted_energy_kwh": 0.000552,
    "confidence": 0.85
  },
  "lstm": {
    "predicted_power_w": 0.548,
    "predicted_energy_kwh": 0.000548,
    "next_5_steps": [
      {"step": 1, "power_w": 0.548},
      {"step": 2, "power_w": 0.551},
      {"step": 3, "power_w": 0.549},
      {"step": 4, "power_w": 0.552},
      {"step": 5, "power_w": 0.550}
    ]
  }
}
```

---

## 🔍 Anomaly Detection Endpoints

### 3. Detect Anomalies

**Endpoint:** `GET /anomalies/detect`

**Description:** Detect anomalies in recent energy data using Isolation Forest model

**Query Parameters:**
- `location` (optional): Filter by location
- `hours_back` (optional): Hours back to analyze (1-168, default: 24)
- `min_score` (optional): Minimum anomaly score threshold (0-1, default: 0.5)

**Example Request:**
```bash
GET /anomalies/detect?location=LAB_1&hours_back=24&min_score=0.5
```

**Response:**
```json
{
  "total_detected": 5,
  "location": "LAB_1",
  "hours_analyzed": 24,
  "anomalies": [
    {
      "device_id": "LAB_1",
      "anomaly_type": "energy_consumption",
      "severity": "High",
      "description": "Unusual energy pattern detected: 2.5W",
      "detected_at": "2026-01-05T01:30:00",
      "anomaly_score": 0.85,
      "power_w": 2.5,
      "current_a": 0.011,
      "location": "LAB_1"
    }
    // ... more anomalies
  ]
}
```

---

### 4. Get Anomaly Statistics

**Endpoint:** `GET /anomalies/stats`

**Description:** Get anomaly statistics for a time period

**Query Parameters:**
- `location` (optional): Filter by location
- `days` (optional): Number of days to analyze (1-90, default: 7)

**Example Request:**
```bash
GET /anomalies/stats?location=LAB_1&days=7
```

**Response:**
```json
{
  "total": 15,
  "by_severity": {
    "High": 5,
    "Medium": 8,
    "Low": 2
  },
  "by_location": {
    "LAB_1": 10,
    "LAB_2": 5
  },
  "average_score": 0.65,
  "period_days": 7
}
```

---

### 5. Get Active Anomalies

**Endpoint:** `GET /anomalies/active`

**Description:** Get active high-severity anomalies from database

**Response:**
```json
[
  {
    "device_id": "LAB_1",
    "anomaly_type": "energy_consumption",
    "severity": "High",
    "description": "Unusual energy pattern detected: 2.5W",
    "detected_at": "2026-01-05T01:30:00"
  }
]
```

---

## 🤖 ML Training Endpoints

### 6. Train Models

**Endpoint:** `POST /ml-training/train`

**Description:** Train/retrain all ML models using recent data (runs in background)

**Query Parameters:**
- `hours_back` (optional): Hours of data to use for training (default: 48)

**Example Request:**
```bash
POST /ml-training/train?hours_back=48
```

**Response:**
```json
{
  "message": "Training started in background",
  "hours_back": 48,
  "status": "training"
}
```

**Note:** Training runs in the background. Check status using `/ml-training/status`

---

### 7. Get Training Status

**Endpoint:** `GET /ml-training/status`

**Description:** Get current training status and model availability

**Example Request:**
```bash
GET /ml-training/status
```

**Response:**
```json
{
  "is_training": false,
  "last_training": "2026-01-05T02:00:00",
  "training_error": null,
  "models": {
    "anomaly_detection": {
      "trained": true,
      "loaded": true
    },
    "prediction_rf": {
      "trained": true,
      "loaded": true
    },
    "prediction_lstm": {
      "trained": true,
      "loaded": true
    }
  },
  "model_files_exist": {
    "anomaly_model": true,
    "prediction_model": true,
    "lstm_model": true,
    "lstm_scalers": true
  }
}
```

---

### 8. Get Model Information

**Endpoint:** `GET /ml-training/model-info`

**Description:** Get detailed information about trained models

**Example Request:**
```bash
GET /ml-training/model-info
```

**Response:**
```json
{
  "anomaly_detection": {
    "type": "Isolation Forest",
    "trained": true,
    "features_count": 32
  },
  "prediction": {
    "random_forest": {
      "type": "Random Forest Regressor",
      "trained": true,
      "features_count": 32
    },
    "lstm": {
      "type": "LSTM Neural Network",
      "trained": true,
      "sequence_length": 48,
      "features_count": 7
    }
  }
}
```

---

## 🧪 Testing Examples

### Using cURL

```bash
# 1. Get prediction
curl -X GET "http://localhost:8000/prediction/predict?location=LAB_1&hours_ahead=24" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# 2. Detect anomalies
curl -X GET "http://localhost:8000/anomalies/detect?hours_back=24" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# 3. Compare models
curl -X GET "http://localhost:8000/prediction/compare?location=LAB_1" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# 4. Check training status
curl -X GET "http://localhost:8000/ml-training/status" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# 5. Train models
curl -X POST "http://localhost:8000/ml-training/train?hours_back=48" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Using Python

```python
import requests

BASE_URL = "http://localhost:8000"
TOKEN = "YOUR_JWT_TOKEN"
headers = {"Authorization": f"Bearer {TOKEN}"}

# Get prediction
response = requests.get(
    f"{BASE_URL}/prediction/predict",
    params={"location": "LAB_1", "hours_ahead": 24, "model_type": "lstm"},
    headers=headers
)
print(response.json())

# Detect anomalies
response = requests.get(
    f"{BASE_URL}/anomalies/detect",
    params={"hours_back": 24, "min_score": 0.5},
    headers=headers
)
print(response.json())

# Check model status
response = requests.get(f"{BASE_URL}/ml-training/status", headers=headers)
print(response.json())
```

---

## 📝 Notes

1. **Model Training:** Models must be trained before using prediction/anomaly endpoints
   - Train manually: Run `python train_ml_models.py`
   - Train via API: `POST /ml-training/train`

2. **Model Types:**
   - **Random Forest:** Fast, good for real-time predictions
   - **LSTM:** Better for time-series patterns, requires more data

3. **Anomaly Scores:**
   - Higher score = More anomalous
   - Score > 0.7 = High severity
   - Score 0.5-0.7 = Medium severity

4. **Error Handling:**
   - `503`: Models not trained
   - `400`: Invalid parameters or insufficient data
   - `500`: Server error during processing

---

## 🔗 Related Documentation

- `ML_MODELS_EXPLANATION.md` - Detailed model explanations
- `ML_MODELS_BRIEF_EXPLANATION.md` - Brief model overview
- FastAPI Docs: `http://localhost:8000/docs` (Interactive API documentation)

