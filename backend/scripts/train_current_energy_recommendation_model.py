"""
Train the current energy recommendation model using the CSV dataset.
Run after generating the dataset: python scripts/generate_current_energy_recommendations_dataset.py

Usage: python scripts/train_current_energy_recommendation_model.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.current_energy_recommendation_model import train_current_energy_model


def main():
    print("=" * 60)
    print("Training Current Energy Recommendation Model")
    print("=" * 60)
    try:
        metrics = train_current_energy_model(test_size=0.2)
        print(f"\nAccuracy: {metrics['accuracy']:.4f}")
        print(f"Training samples: {metrics['n_samples']}")
        print("\nClassification report (test set):")
        for k, v in metrics.get("classification_report", {}).items():
            if isinstance(v, dict):
                print(f"  {k}: {v}")
        print("\nModel saved to models/current_energy_rec_*.pkl")
        print("=" * 60)
    except FileNotFoundError as e:
        print(f"\nError: {e}")
        print("Run first: python scripts/generate_current_energy_recommendations_dataset.py")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
