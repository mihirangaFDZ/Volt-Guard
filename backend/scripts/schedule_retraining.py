"""
Scheduled Retraining Script for AI Energy Optimization Model
This script can be run periodically (e.g., via cron job or Windows Task Scheduler)
to retrain the model with the latest data.

Usage:
    python scripts/schedule_retraining.py

For Windows Task Scheduler:
    - Create a task to run daily/weekly
    - Action: Start a program
    - Program: python
    - Arguments: scripts/schedule_retraining.py
    - Start in: C:\path\to\Volt-Guard\backend

For Linux cron:
    # Run daily at 2 AM
    0 2 * * * cd /path/to/Volt-Guard/backend && python scripts/schedule_retraining.py >> logs/retraining.log 2>&1

For systemd (Linux):
    Create a service file in /etc/systemd/system/voltguard-retraining.service
    See documentation below.
"""

import sys
import logging
from pathlib import Path
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.energy_optimizer import EnergyOptimizer

# Setup logging
log_dir = Path(__file__).parent.parent / "logs"
log_dir.mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_dir / 'retraining.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)


def main():
    """Retrain the AI energy optimization model"""
    logger.info("=" * 70)
    logger.info("Scheduled Model Retraining Started")
    logger.info("=" * 70)
    
    try:
        optimizer = EnergyOptimizer()
        
        # Retrain with 7 days of data (adjust as needed)
        logger.info("Starting model training with 7 days of data...")
        results = optimizer.train_model(
            days=7,  # Use 7 days of historical data
            location=None,  # All locations
            module=None,  # All modules
            model_type='random_forest',  # or 'gradient_boosting'
            test_size=0.2,
            target_column='energy_watts'
        )
        
        logger.info("=" * 70)
        logger.info("Model Retraining Completed Successfully!")
        logger.info("=" * 70)
        logger.info(f"Model Performance:")
        logger.info(f"  Test R² Score: {results['test_r2']:.4f}")
        logger.info(f"  Test MAE: {results['test_mae']:.2f} Watts")
        logger.info(f"  Test RMSE: {results['test_rmse']:.2f} Watts")
        logger.info(f"  Training Samples: {results['n_samples']}")
        logger.info(f"  Features: {results['n_features']}")
        logger.info(f"Model saved to: {optimizer.model_path}")
        logger.info("=" * 70)
        
        return 0  # Success
        
    except Exception as e:
        logger.error(f"Error during model retraining: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return 1  # Failure


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)

