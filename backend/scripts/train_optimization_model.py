"""
Standalone script to train the AI energy optimization model.
Training produces accurate, user-understandable recommendations:
- How to use devices correctly
- How much energy is wasted
- How to save energy and mitigate issues

Usage: python scripts/train_optimization_model.py
Run after you have at least 2-7 days of energy_readings + occupancy data.
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.energy_optimizer import EnergyOptimizer


def main():
    """Train the energy optimization model for accurate recommendations."""
    print("=" * 70)
    print("AI Energy Optimization Model Training")
    print("=" * 70)
    
    optimizer = EnergyOptimizer()
    
    try:
        results = optimizer.train_model(
            days=7,  # Use 7 days for more accurate predictions and recommendations
            location=None,
            module=None,
            model_type='random_forest',
            test_size=0.2,
            target_column='energy_watts'
        )
        
        print("\n" + "=" * 70)
        print("Training Complete!")
        print("=" * 70)
        print(f"Model Performance:")
        print(f"  Test R² Score: {results['test_r2']:.4f}")
        print(f"  Test MAE: {results['test_mae']:.2f} Watts")
        print(f"  Test RMSE: {results['test_rmse']:.2f} Watts")
        print(f"\nModel saved to: models/energy_optimizer.pkl")
        print("=" * 70)
        
    except Exception as e:
        print(f"\n[ERROR] {e}")
        print("\nTroubleshooting:")
        print("1. Check MongoDB connection")
        print("2. Ensure you have at least 2-7 days of data")
        print("3. Check that energy_readings and occupancy_telemetry collections have data")
        sys.exit(1)


if __name__ == "__main__":
    main()

