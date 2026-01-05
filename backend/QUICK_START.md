# Quick Start: AI Energy Optimization

## 🚀 Get Started in 3 Steps

### Step 1: Generate Clean Dataset

```python
from app.services.dataset_generator import DatasetGenerator

generator = DatasetGenerator()
cleaned_df, featured_df = generator.generate_clean_dataset(days=2)
print(f"✅ Dataset created: {len(featured_df)} records")
```

### Step 2: Train AI Model

```python
from app.services.energy_optimizer import EnergyOptimizer

optimizer = EnergyOptimizer()
results = optimizer.train_model(days=7, model_type='random_forest')
print(f"✅ Model trained! R² Score: {results['test_r2']:.4f}")
```

### Step 3: Get Recommendations

```python
# Via API
# GET /optimization/recommendations?days=2

# Or via Python
optimizer.load_model()
_, df = generator.generate_clean_dataset(days=1)
recommendations = optimizer.generate_recommendations(df)

for rec in recommendations:
    print(f"[{rec['severity']}] {rec['title']}")
    print(f"  Savings: {rec['estimated_savings']:.2f} kWh/day")
```

## 📡 API Endpoints

### Train Model
```bash
POST /optimization/train?days=7
```

### Get Recommendations
```bash
GET /optimization/recommendations?days=2
```

### Predict Energy
```bash
GET /optimization/predict?days=1
```

## 📊 What You Get

- ✅ Clean, merged dataset from energy_readings + occupancy_telemetry
- ✅ ML-ready features (time, energy, occupancy patterns)
- ✅ Trained AI model (Random Forest or Gradient Boosting)
- ✅ Energy consumption predictions
- ✅ Optimization recommendations with savings estimates

## 📖 Full Documentation

See [AI_OPTIMIZATION_GUIDE.md](./AI_OPTIMIZATION_GUIDE.md) for complete guide.

