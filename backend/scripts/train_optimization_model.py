"""
Standalone script to train the AI energy optimization model
Usage: python scripts/train_optimization_model.py
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.energy_optimizer import EnergyOptimizer


def main():
    """Train the energy optimization model"""
    print("=" * 70)
    print("AI Energy Optimization Model Training")
    print("=" * 70)
    
    # Initialize optimizer
    optimizer = EnergyOptimizer()
    
    # Train model
    try:
        results = optimizer.train_model(
            days=7,  # Use 7 days of data
            location=None,  # Use all locations
            module=None,  # Use all modules
            model_type='random_forest',  # or 'gradient_boosting'
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

