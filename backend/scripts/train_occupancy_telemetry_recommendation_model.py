"""
Train the occupancy telemetry (environment) recommendation model using the CSV dataset.
Run after generating the dataset: python scripts/generate_occupancy_telemetry_recommendations_dataset.py

Usage: python scripts/train_occupancy_telemetry_recommendation_model.py
"""

import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from app.services.occupancy_telemetry_recommendation_model import train_occupancy_telemetry_model

if __name__ == "__main__":
    try:
        metrics = train_occupancy_telemetry_model(test_size=0.2)
        print("\nOccupancy telemetry (environment) recommendation model trained successfully.")
        print(f"  Accuracy: {metrics['accuracy']:.4f}")
        print(f"  Samples:  {metrics['n_samples']}")
        print("\nModel saved to models/occupancy_telemetry_rec_*.pkl")
    except FileNotFoundError as e:
        print(f"Error: {e}")
        print("Run first: python scripts/generate_occupancy_telemetry_recommendations_dataset.py")
        sys.exit(1)
    except Exception as e:
        print(f"Training failed: {e}")
        sys.exit(1)
