# AI-Driven Energy Optimization & Recommendation Engine
## Complete Step-by-Step Guide

This guide will walk you through building an AI-driven energy optimization system from your raw sensor data.

---

## 📋 Overview

You have two types of data:
1. **energy_readings** - Current/energy consumption data (ACS712 sensors)
2. **occupancy_telemetry** - Occupancy, temperature, humidity data (PIR/RCWL sensors)

Your goal: Create an AI model that predicts energy consumption and provides optimization recommendations.

---

## 🚀 Step 1: Data Cleaning

**Goal**: Clean and preprocess raw data from MongoDB

**What we do**:
- Remove invalid/null readings
- Handle missing values
- Remove outliers (using IQR method)
- Standardize timestamps
- Merge energy and occupancy data

**Files Created**:
- `backend/app/services/data_cleaner.py`

**Usage**:

```python
from app.services.data_cleaner import DataCleaner

# Initialize cleaner
cleaner = DataCleaner()

# Fetch and clean data
cleaned_df = cleaner.create_clean_dataset(
    days=2,  # Number of days to process
    location=None,  # Optional: filter by location
    module=None,  # Optional: filter by module
    save_path="data/cleaned_data.csv"  # Optional: save cleaned data
)
```

**Output**: Clean DataFrame with merged energy and occupancy data

---

## 🔧 Step 2: Feature Engineering

**Goal**: Create ML-ready features from cleaned data

**Features Created**:

### Time Features
- `hour`: Hour of day (0-23)
- `day_of_week`: Day of week (0=Monday, 6=Sunday)
- `is_weekend`: Binary (1 if weekend, 0 otherwise)
- `hour_sin`, `hour_cos`: Cyclical encoding for hour
- `day_of_week_sin`, `day_of_week_cos`: Cyclical encoding for day

### Energy Features
- `energy_watts`: Power consumption (Voltage × Current, assuming 220V)
- `energy_rolling_mean`: Rolling average of energy
- `energy_rolling_std`: Rolling standard deviation
- `energy_lag_1`: Previous reading value
- `energy_change`: Change from previous reading

### Occupancy Features
- `is_occupied`: Binary (1 if PIR or RCWL is 1, else 0)
- `occupancy_duration`: How long room has been in current state
- `occupancy_rolling_mean`: Average occupancy over time window

### Location Features
- One-hot encoded location and module identifiers

**Files Created**:
- `backend/app/services/feature_engineer.py`

**Usage**:

```python
from app.services.feature_engineer import FeatureEngineer

# Initialize feature engineer
fe = FeatureEngineer()

# Create all features
featured_df = fe.create_all_features(cleaned_df)
```

**Output**: DataFrame with all engineered features

---

## 📊 Step 3: Clean Dataset Generation

**Goal**: Combine data cleaning and feature engineering into one pipeline

**Files Created**:
- `backend/app/services/dataset_generator.py`

**Usage**:

```python
from app.services.dataset_generator import DatasetGenerator

# Initialize generator
generator = DatasetGenerator()

# Generate clean, featured dataset
cleaned_df, featured_df = generator.generate_clean_dataset(
    days=2,
    location=None,
    module=None,
    save_path="data/cleaned_dataset.csv",  # Optional
    save_featured_path="data/featured_dataset.csv"  # Optional
)
```

**Output**: Tuple of (cleaned_df, featured_df)

---

## 🤖 Step 4: AI Model Training

**Goal**: Train a machine learning model to predict energy consumption

**Models Available**:
- `random_forest`: Random Forest Regressor (default, fast and robust)
- `gradient_boosting`: Gradient Boosting Regressor (more accurate, slower)

**Files Created**:
- `backend/app/services/energy_optimizer.py`

**Usage**:

```python
from app.services.energy_optimizer import EnergyOptimizer

# Initialize optimizer
optimizer = EnergyOptimizer()

# Train model
results = optimizer.train_model(
    days=7,  # Use 7 days of data for training
    location=None,  # Optional: filter by location
    module=None,  # Optional: filter by module
    model_type='random_forest',  # or 'gradient_boosting'
    test_size=0.2,  # 20% of data for testing
    target_column='energy_watts'  # What to predict
)

# Model is automatically saved to models/energy_optimizer.pkl
```

**Output**: Dictionary with training metrics:
```python
{
    'train_mae': 45.23,  # Mean Absolute Error (Watts)
    'test_mae': 52.18,
    'train_rmse': 65.34,  # Root Mean Squared Error (Watts)
    'test_rmse': 71.23,
    'train_r2': 0.85,  # R² score (closer to 1 is better)
    'test_r2': 0.82,
    'n_samples': 1000,
    'n_features': 25,
    'feature_columns': [...],
    'model_type': 'random_forest'
}
```

**Model Files Saved**:
- `models/energy_optimizer.pkl` - Trained model
- `models/scaler.pkl` - Feature scaler
- `models/metadata.pkl` - Feature metadata

---

## 🎯 Step 5: Generate Recommendations

**Goal**: Use trained model to generate energy optimization recommendations

**Usage**:

```python
from app.services.energy_optimizer import EnergyOptimizer
from app.services.dataset_generator import DatasetGenerator

# Initialize
optimizer = EnergyOptimizer()
generator = DatasetGenerator()

# Load trained model
optimizer.load_model()

# Get recent data
_, featured_df = generator.generate_clean_dataset(days=2)

# Generate recommendations
recommendations = optimizer.generate_recommendations(
    featured_df,
    threshold_high=1000.0,  # High energy threshold (Watts)
    threshold_low=100.0  # Low energy threshold (Watts)
)

# Print recommendations
for rec in recommendations:
    print(f"[{rec['severity'].upper()}] {rec['title']}")
    print(f"  {rec['message']}")
    print(f"  Estimated savings: {rec['estimated_savings']:.2f} kWh/day")
```

**Output**: List of recommendation dictionaries:
```python
[
    {
        'type': 'high_priority',
        'title': 'Turn off unused devices',
        'message': 'Room is vacant but consuming 1250.00W. Turn off AC and other devices.',
        'estimated_savings': 30.0,  # kWh per day
        'severity': 'high'
    },
    ...
]
```

---

## 🌐 Step 6: API Endpoints

**Goal**: Expose AI optimization through REST API

**Files Created**:
- `backend/routes/optimization.py`

**Endpoints**:

### 1. Train Model
```
POST /optimization/train
```

**Query Parameters**:
- `days` (int, default=7): Days of data to use for training
- `location` (string, optional): Filter by location
- `module` (string, optional): Filter by module
- `model_type` (string, default='random_forest'): 'random_forest' or 'gradient_boosting'
- `test_size` (float, default=0.2): Proportion of data for testing

**Example**:
```bash
curl -X POST "http://localhost:8000/optimization/train?days=7&model_type=random_forest" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response**:
```json
{
  "status": "success",
  "message": "Model trained successfully with 1000 samples",
  "metrics": {
    "train_mae": 45.23,
    "test_mae": 52.18,
    "train_r2": 0.85,
    "test_r2": 0.82,
    ...
  }
}
```

### 2. Get AI Recommendations
```
GET /optimization/recommendations
```

**Query Parameters**:
- `days` (int, default=2): Days of historical data to analyze
- `location` (string, optional): Filter by location
- `module` (string, optional): Filter by module
- `threshold_high` (float, default=1000.0): High energy threshold (Watts)
- `threshold_low` (float, default=100.0): Low energy threshold (Watts)

**Example**:
```bash
curl "http://localhost:8000/optimization/recommendations?days=2&location=LAB_1" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response**:
```json
{
  "recommendations": [
    {
      "type": "high_priority",
      "title": "Turn off unused devices",
      "message": "Room is vacant but consuming 1250.00W. Turn off AC and other devices.",
      "estimated_savings": 30.0,
      "severity": "high"
    }
  ],
  "predicted_energy_watts": 1250.5,
  "current_energy_watts": 1250.0,
  "potential_savings_kwh_per_day": 30.0,
  "count": 1
}
```

### 3. Predict Energy Consumption
```
GET /optimization/predict
```

**Query Parameters**:
- `days` (int, default=1): Days of data to use for prediction
- `location` (string, optional): Filter by location
- `module` (string, optional): Filter by module

**Example**:
```bash
curl "http://localhost:8000/optimization/predict?days=1&location=LAB_1" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response**:
```json
{
  "current_energy_watts": 1250.0,
  "predicted_energy_watts": 1300.5,
  "predictions": [1250.0, 1280.0, 1300.5],
  "timestamp": "2026-01-04T18:30:00"
}
```

---

## 📝 Complete Workflow Example

Here's a complete example of using the system:

```python
# Step 1: Generate clean dataset
from app.services.dataset_generator import DatasetGenerator

generator = DatasetGenerator()
cleaned_df, featured_df = generator.generate_clean_dataset(
    days=2,
    save_featured_path="data/featured_dataset.csv"
)

print(f"Generated dataset with {len(featured_df)} records")
print(f"Features: {list(featured_df.columns)[:10]}...")

# Step 2: Train model
from app.services.energy_optimizer import EnergyOptimizer

optimizer = EnergyOptimizer()
results = optimizer.train_model(
    days=7,
    model_type='random_forest'
)

print(f"Model trained! Test R²: {results['test_r2']:.4f}")

# Step 3: Generate recommendations
optimizer.load_model()
_, recent_df = generator.generate_clean_dataset(days=1)

recommendations = optimizer.generate_recommendations(recent_df)

for rec in recommendations:
    print(f"\n[{rec['severity'].upper()}] {rec['title']}")
    print(f"  {rec['message']}")
    print(f"  Estimated savings: {rec['estimated_savings']:.2f} kWh/day")
```

---

## 🔍 Data Quality Checklist

Before training your model, ensure:

- [ ] **Sufficient Data**: At least 2-7 days of continuous data
- [ ] **Data Completeness**: Check for missing values (run `df.isnull().sum()`)
- [ ] **Outlier Removal**: Verify outliers are removed (check `energy_watts` distribution)
- [ ] **Location Matching**: Ensure energy_readings and occupancy_telemetry have matching locations
- [ ] **Timestamp Alignment**: Check that timestamps are correctly parsed

---

## 🎓 Understanding Model Performance

### Metrics Explained:

1. **MAE (Mean Absolute Error)**: Average prediction error in Watts
   - Lower is better
   - Example: MAE of 50 means predictions are off by ~50W on average

2. **RMSE (Root Mean Squared Error)**: Penalizes larger errors more
   - Lower is better
   - Example: RMSE of 70 means larger errors are penalized more

3. **R² Score**: How well the model explains variance (0 to 1)
   - Closer to 1 is better
   - R² > 0.8: Good model
   - R² > 0.9: Excellent model

### Improving Model Performance:

1. **More Data**: Use 7-30 days instead of 2 days
2. **Feature Engineering**: Add more domain-specific features
3. **Hyperparameter Tuning**: Adjust model parameters
4. **Different Models**: Try `gradient_boosting` instead of `random_forest`
5. **Data Quality**: Ensure clean, consistent data

---

## 🚨 Troubleshooting

### Issue: "No data available"
**Solution**: Check MongoDB connection and ensure data exists for the date range

### Issue: "Model not trained"
**Solution**: Train the model first using `/optimization/train` endpoint

### Issue: Poor model performance (R² < 0.5)
**Solutions**:
- Use more training data (7+ days)
- Check data quality (missing values, outliers)
- Try different model type (`gradient_boosting`)
- Review feature importance to identify important features

### Issue: Memory errors during training
**Solutions**:
- Reduce number of days
- Filter by specific location/module
- Reduce model complexity (fewer trees)

---

## 📚 Next Steps

1. **Collect More Data**: More data = better model
2. **Feature Engineering**: Add domain-specific features (weather, events, etc.)
3. **Model Tuning**: Experiment with hyperparameters
4. **Deployment**: Set up automated retraining schedule
5. **Integration**: Connect to your frontend/dashboard

---

## 📞 Support

For questions or issues, check:
- Code comments in service files
- API documentation at `http://localhost:8000/docs`
- Model files in `models/` directory

---

**Happy Optimizing! 🚀**

