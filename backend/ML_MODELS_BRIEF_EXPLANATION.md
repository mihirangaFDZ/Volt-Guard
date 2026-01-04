# 🤖 AI-Based Energy Analytics: Brief Model Explanation

## Quick Overview

This system uses **3 AI models** to analyze energy consumption:

1. **🔍 Isolation Forest** → Detects anomalies (unusual patterns)
2. **📊 Random Forest** → Predicts energy (fast, traditional ML)
3. **🧠 LSTM Neural Network** → Predicts energy (advanced time series)

---

## 🔍 How Anomaly Detection Works

### Isolation Forest Algorithm

**Simple Explanation:**
- The model learns what "normal" energy consumption looks like
- When new data comes in, it checks: "Is this easy to separate from normal data?"
- If YES → **ANOMALY DETECTED** ⚠️

**Example:**
```
Normal readings: 0.3W, 0.35W, 0.32W, 0.38W
New reading: 2.5W ← Very different!
Result: ANOMALY (device consuming way more than normal)
```

**What it analyzes:**
- Power consumption patterns
- Current readings
- Time of day patterns
- Occupancy patterns
- Historical trends

**Output:**
- `is_anomaly`: 1 = Anomaly detected, 0 = Normal
- `anomaly_score`: Higher score = More anomalous

---

## 📈 How Prediction Works

### Method 1: Random Forest

**Simple Explanation:**
- Creates 100+ "decision trees" (like flowcharts)
- Each tree asks questions: "Is it weekend? Is current high? Is it daytime?"
- Each tree makes a prediction
- **Average of all predictions** = Final prediction

**Example:**
```
Tree 1: "Weekend + Night → 0.2W"
Tree 2: "Low current → 0.3W"
Tree 3: "Normal pattern → 0.35W"
...
Final Prediction = Average = 0.32W
```

**Best for:** Quick predictions based on current conditions

---

### Method 2: LSTM (Long Short-Term Memory)

**Simple Explanation:**
- Looks at **sequences** of data (last 24 hours)
- Has "memory" to remember patterns over time
- Learns patterns like: "Power increases at 8 AM" or "Weekends are different"

**Example:**
```
Input: Last 24 hours of power readings
[0.3W, 0.32W, 0.31W, ..., 0.35W]

LSTM Processes:
- Remembers: "Power was 0.3W yesterday at this time"
- Remembers: "Mornings usually increase by 0.05W"
- Remembers: "Weekends have different pattern"

Output: Predicted next hour = 0.38W
```

**Best for:** Time series patterns, long-term predictions

**Architecture:**
```
Input (24 time steps)
    ↓
LSTM Layer 1 (learns patterns)
    ↓
LSTM Layer 2 (refines patterns)
    ↓
Output (predicted power)
```

---

## 🔄 Complete Workflow

```
1. NEW DATA ARRIVES
   ↓
2. ANOMALY CHECK
   Isolation Forest: "Is this normal?"
   ├─ Yes → Continue
   └─ No → Alert user ⚠️
   ↓
3. PREDICT ENERGY
   Random Forest: Quick prediction
   LSTM: Time-series prediction
   ↓
4. COMBINE & DISPLAY
   Show predictions to user
   Optimize energy usage
```

---

## 🎓 Training Process (Simplified)

### Step 1: Data Cleaning
- Remove garbage values (device not connected, sensors not connected)
- Remove outliers
- Fill missing values

### Step 2: Feature Engineering
- Create time features (hour, day of week, etc.)
- Create rolling averages (last 1 hour average)
- Create lag features (value from 1 hour ago)

### Step 3: Model Training

**Anomaly Detection:**
- Learns normal patterns from historical data
- No labels needed (unsupervised)

**Random Forest:**
- Splits data: 80% train, 20% test
- Trains 100+ decision trees
- Evaluates accuracy

**LSTM:**
- Creates sequences (sliding windows)
- Trains neural network with memory
- Stops early if no improvement (prevents overfitting)

### Step 4: Evaluation
- **MAE (Mean Absolute Error)**: Average prediction error (lower is better)
- **RMSE (Root Mean Squared Error)**: Penalizes large errors (lower is better)
- **R² Score**: How well model explains data (1.0 = perfect, >0.8 = good)

---

## 📊 Model Comparison

| Aspect | Random Forest | LSTM |
|--------|--------------|------|
| **Speed** | ⚡ Fast | 🐢 Slower |
| **Best For** | Current conditions | Time patterns |
| **Input** | Single data point | Sequence of data |
| **Accuracy** | Good | Better for sequences |
| **Interpretability** | High (shows which features matter) | Low (black box) |

---

## 💡 Key Concepts

### What is an Anomaly?
- **Normal**: Energy consumption follows expected patterns
- **Anomaly**: Energy consumption is unusual/unexpected
  - Examples: Sudden spike, sudden drop, unusual pattern

### What is Prediction?
- **Input**: Current conditions + Historical data
- **Output**: Expected energy consumption in future
- **Purpose**: Plan energy usage, detect issues early, optimize

### Why Two Prediction Models?
- **Random Forest**: Fast, good for real-time predictions
- **LSTM**: Better for understanding time patterns, long-term trends
- **Together**: Best of both worlds!

---

## 🚀 Real-World Example

**Scenario:** Monday, 2:00 PM
- Current Power: 0.5W
- Room: Occupied
- Temperature: 28°C

**Anomaly Detection:**
```
Input: [0.5W, occupied, 28°C, Monday 2PM, ...]
Isolation Forest Score: 0.15 (low = normal)
Result: ✅ No anomaly
```

**Prediction:**
```
Random Forest: "Based on current conditions → 0.52W next hour"
LSTM: "Based on last 24h pattern → 0.48W next hour"
Combined: 0.50W
```

**Action:**
- Display: "Next hour: ~0.50W (normal consumption)"
- No alerts needed (everything normal)

---

## 📝 Summary

1. **Anomaly Detection**: Isolation Forest automatically finds unusual patterns
2. **Prediction**: Random Forest (fast) + LSTM (accurate for time patterns)
3. **Training**: Models learn from historical data
4. **Usage**: Real-time monitoring + future predictions

**The system learns from your data and gets smarter over time!** 🎯

