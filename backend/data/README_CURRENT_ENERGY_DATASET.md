# Current Energy Recommendations Dataset

## File

- **current_energy_recommendations_dataset.csv** – 2000 rows for training the current energy analysis recommendation model.

## Columns

| Column | Description |
|--------|-------------|
| current_a | Current in amperes |
| current_ma | Current in milliamperes |
| power_w | Power in watts (current_a × 230) |
| trend_direction | stable, rising, falling |
| trend_percent_change | Percentage change in consumption |
| signal_quality | strong, fair, weak |
| recommendation_type | high_load, moderate_load, rising_consumption, weak_signal, efficient_usage |
| severity | high, medium, low |
| estimated_savings_kwh_per_day | Estimated savings (kWh/day) |
| energy_wasted_kwh_per_day | Estimated waste (kWh/day) |

## Regenerate dataset (2000 rows)

```bash
python scripts/generate_current_energy_recommendations_dataset.py
```

## Train the model

```bash
python scripts/train_current_energy_recommendation_model.py
```

Model artifacts are saved under `models/` (classifier, scaler, encoders). The analytics page uses the trained model via the `/analytics/current-energy-recommendations` API for accurate recommendations.
