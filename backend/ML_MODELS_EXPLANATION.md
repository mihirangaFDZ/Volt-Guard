# AI-Based Energy Analytics: Model Training & Logic Explanation

## 📚 Table of Contents
1. [Overview](#overview)
2. [Anomaly Detection Model](#anomaly-detection-model)
3. [Energy Prediction Models](#energy-prediction-models)
4. [How Models Work Together](#how-models-work-together)
5. [Training Process](#training-process)

---

## Overview

Our AI system uses **three types of models** to analyze energy consumption:

1. **Isolation Forest** - Detects anomalies (unusual energy patterns)
2. **Random Forest** - Predicts energy consumption (traditional ML)
3. **LSTM Neural Network** - Predicts energy consumption (advanced time series)

---

## 🔍 Anomaly Detection Model (Isolation Forest)

### What is it?
**Isolation Forest** is an unsupervised learning algorithm that identifies unusual patterns in data.

### How does it work?

#### Step 1: Understanding Normal Patterns
```
The model learns what "normal" energy consumption looks like by analyzing:
- Current readings (current_a, current_ma)
- Power consumption (power_w)
- Time patterns (hour, day of week)
- Occupancy (occupied, temperature, humidity)
- Historical patterns (rolling means, lags)
```

#### Step 2: Isolation Process
```
Think of it like finding a needle in a haystack:

1. Randomly select a feature (e.g., power_w)
2. Randomly pick a split value
3. Isolate data points (separate normal from unusual)
4. Repeat many times
5. Points that are "easy to isolate" = ANOMALIES
```

**Example:**
```
Normal power: 0.3W, 0.4W, 0.35W, 0.38W, 0.42W
Anomaly: 2.5W  ← This is easy to isolate (very different)!
```

#### Step 3: Anomaly Score
```
Each data point gets an "anomaly score":
- Low score (close to 0) = Normal
- High score (far from 0) = Anomaly

Threshold: If score > threshold → ANOMALY DETECTED
```

### Why Isolation Forest?
- ✅ Works without labeled data (no need to mark anomalies manually)
- ✅ Fast and efficient
- ✅ Good at finding outliers in high-dimensional data
- ✅ Handles multiple types of anomalies

### Real-World Example:
```
Normal: Device consumes 0.3W consistently
Anomaly: Device suddenly consumes 2.5W
→ Model flags: "ANOMALY - Unusual power spike detected!"
```

---

## 📈 Energy Prediction Models

### Model 1: Random Forest Regressor

#### What is it?
**Random Forest** is an ensemble of decision trees that vote on the final prediction.

#### How does it work?

**Step 1: Building Decision Trees**
```
Each tree asks questions like:
- Is it weekend? → Yes/No
- Is current_a > 0.2? → Yes/No
- Is hour between 9-17? → Yes/No
- ... continues until prediction

Example Tree:
IF weekend == True AND hour < 8:
    → Predict: 0.2W (low consumption)
ELSE IF current_a > 0.3:
    → Predict: 0.8W (high consumption)
ELSE:
    → Predict: 0.4W (normal)
```

**Step 2: Ensemble Prediction**
```
1. Create 100+ decision trees (each trained on random data)
2. Each tree makes a prediction
3. Average all predictions = Final prediction

Tree 1 predicts: 0.35W
Tree 2 predicts: 0.40W
Tree 3 predicts: 0.38W
...
Tree 100 predicts: 0.36W

Final Prediction = Average = 0.37W
```

**Step 3: Feature Importance**
```
The model learns which features matter most:
- current_a: 45% importance
- hour: 25% importance
- occupied: 15% importance
- temperature: 10% importance
- ... etc
```

### Why Random Forest?
- ✅ Handles non-linear relationships
- ✅ Works with many features
- ✅ Provides feature importance
- ✅ Robust to outliers

---

### Model 2: LSTM (Long Short-Term Memory) Neural Network

#### What is it?
**LSTM** is a type of Recurrent Neural Network (RNN) designed for time series data.

#### How does it work?

**Step 1: Understanding Sequences**
```
LSTM looks at SEQUENCES of data, not just single points:

Traditional ML: "Given current features, predict next value"
LSTM: "Given last 24 hours of data, predict next hour"

Example Sequence (last 24 readings):
Time 1: 0.3W
Time 2: 0.32W
Time 3: 0.31W
...
Time 24: 0.35W
→ Predict: Time 25 = 0.36W
```

**Step 2: Memory Cells**
```
LSTM has "memory cells" that remember:
- Short-term patterns (last few hours)
- Long-term patterns (daily cycles, weekly trends)

Memory Cell Structure:
┌─────────────────┐
│ Forget Gate     │ → Decides what to forget
│ Input Gate      │ → Decides what to remember
│ Output Gate     │ → Decides what to output
│ Cell State      │ → Stores long-term memory
└─────────────────┘
```

**Step 3: Learning Process**
```
1. Feed sequence of 24 hours → LSTM
2. LSTM processes sequence through memory cells
3. Learns patterns:
   - "Power increases in morning (8-10 AM)"
   - "Power decreases at night (10 PM - 6 AM)"
   - "Weekends have different patterns"
4. Predicts next value based on learned patterns
```

**Step 4: Multi-Step Prediction**
```
To predict 24 hours ahead:
1. Predict hour 1 using last 24 hours
2. Use hour 1 prediction + last 23 hours → Predict hour 2
3. Use hours 1-2 predictions + last 22 hours → Predict hour 3
4. ... continue for 24 steps
```

### Why LSTM?
- ✅ Captures temporal patterns (time dependencies)
- ✅ Learns complex sequences
- ✅ Better for long-term predictions
- ✅ Handles sequences of varying lengths

### Architecture:
```
Input (24 time steps × 7 features)
    ↓
LSTM Layer 1 (50 units) + Dropout (20%)
    ↓
LSTM Layer 2 (50 units) + Dropout (20%)
    ↓
Dense Layer (25 units)
    ↓
Output (1 value: predicted power)
```

---

## 🔄 How Models Work Together

### Complete Workflow:

```
1. NEW DATA ARRIVES
   ↓
2. ANOMALY DETECTION
   - Isolation Forest checks: "Is this normal?"
   - If anomaly → Alert user
   - If normal → Continue
   ↓
3. ENERGY PREDICTION
   - Random Forest: Quick prediction (current conditions)
   - LSTM: Advanced prediction (time series patterns)
   - Combine both for best accuracy
   ↓
4. ACTION
   - Display predictions
   - Generate alerts
   - Optimize energy usage
```

### Example Scenario:

```
Time: 2:00 PM, Monday
Current Power: 0.5W
Occupancy: Yes (room occupied)
Temperature: 28°C

Step 1: Anomaly Check
├─ Isolation Forest analyzes: [0.5W, occupied, 28°C, Monday 2PM, ...]
├─ Score: 0.15 (normal)
└─ Result: ✅ No anomaly

Step 2: Prediction
├─ Random Forest: "Based on current features → 0.52W next hour"
├─ LSTM: "Based on last 24h pattern → 0.48W next hour"
└─ Combined: 0.50W (average)

Step 3: Action
└─ Display: "Next hour: ~0.50W (normal consumption)"
```

---

## 🎓 Training Process Explained

### Step 1: Data Collection
```
Extract from MongoDB:
- Energy readings (current, power, voltage)
- Occupancy data (temperature, humidity, motion)
- Time features (hour, day, weekend)
```

### Step 2: Data Cleaning
```
Remove garbage values:
- current_a == 0 AND current_ma == 0 → Device not connected
- temperature == 0 AND humidity == 0 → Sensors not connected
- Outliers (using IQR method)
- Missing values (fill with median/forward fill)
```

### Step 3: Feature Engineering
```
Create features:
- Time features: hour_sin, hour_cos, day_sin, day_cos
- Rolling statistics: mean_1h, std_1h
- Lag features: value_1_step_ago, value_2_steps_ago
- Aggregated: daily_mean, daily_max, daily_min
```

### Step 4: Model Training

#### Anomaly Detection:
```
1. Prepare features (all columns except target)
2. Scale features (normalize to 0-1)
3. Train Isolation Forest:
   - contamination=0.1 (expect 10% anomalies)
   - Learns normal patterns
4. Save model
```

#### Random Forest:
```
1. Split data: 80% train, 20% test
2. Train 100 decision trees
3. Each tree learns different patterns
4. Evaluate: MAE, RMSE
5. Save model
```

#### LSTM:
```
1. Create sequences (sliding windows)
2. Scale data (0-1 normalization)
3. Build architecture:
   - 2 LSTM layers (50 units each)
   - Dropout (prevent overfitting)
   - Dense output layer
4. Train with early stopping
5. Evaluate: MAE, RMSE, R²
6. Save model
```

### Step 5: Evaluation Metrics

**MAE (Mean Absolute Error):**
```
Average difference between predicted and actual
Example: MAE = 0.05W means predictions are off by 0.05W on average
Lower is better!
```

**RMSE (Root Mean Squared Error):**
```
Similar to MAE but penalizes large errors more
Example: RMSE = 0.08W
Lower is better!
```

**R² Score:**
```
How well model explains the data
Range: 0 to 1
- 1.0 = Perfect predictions
- 0.8 = Good predictions
- 0.5 = Moderate predictions
- 0.0 = No better than guessing average
Higher is better!
```

---

## 📊 Model Comparison

| Feature | Random Forest | LSTM |
|---------|--------------|------|
| **Best For** | Current conditions | Time series patterns |
| **Input** | Single data point | Sequence of data |
| **Speed** | Fast | Slower |
| **Accuracy** | Good | Better for sequences |
| **Interpretability** | High (feature importance) | Low (black box) |
| **Data Needed** | Less | More (sequences) |

---

## 🚀 Usage Example

```python
# Load models
ml_service = EnergyMLService()
ml_service.load_models()

lstm = LSTMPredictor()
lstm.load_model()

# New data arrives
new_data = get_latest_readings()

# 1. Check for anomalies
anomalies = ml_service.detect_anomalies(new_data)
if anomalies['is_anomaly'].any():
    print("⚠️ ANOMALY DETECTED!")

# 2. Predict next hour (Random Forest)
prediction_rf = ml_service.predict_energy(new_data)

# 3. Predict next 24 hours (LSTM)
prediction_lstm = lstm.predict(new_data, steps_ahead=24)

# 4. Combine predictions
final_prediction = (prediction_rf + prediction_lstm.mean()) / 2
```

---

## 🎯 Key Takeaways

1. **Anomaly Detection**: Uses Isolation Forest to find unusual patterns automatically
2. **Prediction**: Uses Random Forest (fast) and LSTM (accurate for sequences)
3. **Training**: Models learn from historical data to predict future consumption
4. **Evaluation**: MAE, RMSE, and R² tell us how good the models are
5. **Combined Approach**: Use both models together for best results

---

## 📝 Next Steps

- Collect more data for better accuracy
- Tune hyperparameters (sequence length, LSTM units, etc.)
- Add more features (weather, device types, etc.)
- Implement real-time predictions in API
- Create visualization dashboards

