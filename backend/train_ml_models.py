# backend/train_ml_models.py
"""
Training script for AI-Based Energy Analytics Models
Run this script to:
1. Extract and clean data from MongoDB
2. Create features
3. Train anomaly detection (Isolation Forest + Autoencoder) and prediction (LSTM) models
"""
import sys
from pathlib import Path

# Add current directory to path
backend_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(backend_dir))

from app.services.ml_service import EnergyMLService
from app.services.lstm_service import LSTMPredictor
from app.services.autoencoder_service import AutoencoderAnomalyDetector
import pandas as pd

def _load_dataset_from_csv(input_csv: str):
    df = pd.read_csv(input_csv)
    # Preserve feature columns from the file
    feature_cols = list(df.columns)
    return df, feature_cols


def main(input_csv: str | None = None):
    print("=" * 60)
    print("AI-Based Energy Analytics Training Pipeline")
    print("=" * 60)

    # Step 1: Create clean dataset
    print("\n[1/4] Creating clean dataset...")
    try:
        if input_csv:
            df, feature_cols = _load_dataset_from_csv(input_csv)
        else:
            from app.services.create_clean_dataset import create_clean_dataset
            df, feature_cols = create_clean_dataset(hours_back=48, output_path='clean_dataset.csv')

        if df is None or len(df) == 0:
            print("Error: No data available for training. Please ensure you have data in MongoDB.")
            return

        print(f"Successfully created dataset with {len(df)} records")
    except Exception as e:
        print(f"Error creating dataset: {e}")
        import traceback
        traceback.print_exc()
        return

    # Select numeric features only (exclude datetime, categorical)
    numeric_features = [col for col in feature_cols
                       if col in df.columns and
                       df[col].dtype in ['float64', 'int64', 'float32', 'int32']
                       and not col.startswith('received_at')
                       and col != 'power_w'  # Exclude target from features
                       and col != 'current_a'  # Exclude if used as target
                       ]

    if len(numeric_features) == 0:
        print("Warning: No numeric features found. Using all available features.")
        numeric_features = [col for col in feature_cols if col in df.columns and col != 'power_w']

    print(f"Using {len(numeric_features)} features for training")

    # Step 2: Train anomaly detection models
    print("\n[2/4] Training anomaly detection models...")
    try:
        # 2a: Isolation Forest
        ml_service = EnergyMLService(model_dir='models')
        print("\nTraining Isolation Forest anomaly detection model...")
        ml_service.train_anomaly_detector(df, numeric_features)

        # 2b: Autoencoder
        print("\nTraining Autoencoder anomaly detection model...")
        try:
            autoencoder = AutoencoderAnomalyDetector(model_dir='models')
            autoencoder.train(
                df, numeric_features,
                contamination=0.1,
                epochs=100,
                batch_size=min(32, max(1, len(df) // 10))
            )
            print("\n[SUCCESS] Autoencoder model trained successfully!")
        except Exception as e:
            print(f"\n[WARNING] Autoencoder training failed: {e}")
            import traceback
            traceback.print_exc()

    except Exception as e:
        print(f"Error training anomaly models: {e}")
        import traceback
        traceback.print_exc()
        return

    # Step 3: Train LSTM prediction model
    print("\n[3/4] Training LSTM prediction model...")
    try:
        if 'power_w' in df.columns:
            # Select time-series features for LSTM
            lstm_features = [
                'current_a', 'power_w', 'hour_sin', 'hour_cos',
                'day_sin', 'day_cos', 'is_weekend'
            ]
            lstm_features = [col for col in lstm_features if col in df.columns]

            if len(lstm_features) >= 3:  # Need at least 3 features
                try:
                    # Adjust sequence length based on available data
                    available_data = len(df)
                    if available_data < 100:
                        seq_length = 12
                    elif available_data < 500:
                        seq_length = 24
                    else:
                        seq_length = 48

                    lstm = LSTMPredictor(model_dir='models', sequence_length=seq_length, prediction_horizon=1)
                    lstm.train(
                        df,
                        target_col='power_w',
                        feature_cols=lstm_features,
                        epochs=100,
                        batch_size=min(32, len(df) // 10)
                    )
                    print("\n[SUCCESS] LSTM model trained successfully!")
                except Exception as e:
                    print(f"\n[WARNING] LSTM training failed: {e}")
                    import traceback
                    traceback.print_exc()
            else:
                print(f"\n[WARNING] Not enough features for LSTM. Need at least 3, got {len(lstm_features)}")
        else:
            print("\nWarning: 'power_w' column not found. Skipping LSTM prediction model training.")
            print("Available columns:", list(df.columns)[:10])

    except Exception as e:
        print(f"Error training LSTM: {e}")
        import traceback
        traceback.print_exc()

    # Step 4: Test all models
    print("\n[4/4] Testing models...")
    try:
        test_df = df.tail(min(100, len(df))).copy()

        # Test Isolation Forest
        ml_service = EnergyMLService(model_dir='models')
        ml_service.load_models()
        if ml_service.is_trained:
            print("\nTesting anomaly detection (Isolation Forest)...")
            anomalies = ml_service.detect_anomalies(test_df.copy())
            num_anomalies = anomalies['is_anomaly'].sum()
            print(f"  Detected {num_anomalies} anomalies in test data ({len(test_df)} records)")

        # Test Autoencoder
        autoencoder = AutoencoderAnomalyDetector(model_dir='models')
        if autoencoder.load_model():
            print("\nTesting anomaly detection (Autoencoder)...")
            ae_results = autoencoder.detect_anomalies(test_df.copy())
            ae_anomalies = ae_results['is_anomaly_ae'].sum()
            print(f"  Detected {ae_anomalies} anomalies in test data ({len(test_df)} records)")
            print(f"  Mean reconstruction error: {ae_results['reconstruction_error'].mean():.6f}")

        # Test LSTM
        lstm = LSTMPredictor(model_dir='models')
        if lstm.load_model():
            print("\nTesting LSTM predictions...")
            try:
                lstm_predictions = lstm.predict(test_df.tail(50), steps_ahead=5)
                print(f"  Generated {len(lstm_predictions)} LSTM predictions")
                print(f"  Next 5 steps ahead: {lstm_predictions['predicted_power_w'].values}")
            except Exception as e:
                print(f"  LSTM prediction test failed: {e}")

    except Exception as e:
        print(f"Error testing models: {e}")
        import traceback
        traceback.print_exc()

    print("\n" + "=" * 60)
    print("Training Complete!")
    print("=" * 60)
    print("\nTrained models:")
    print("  - Isolation Forest (anomaly detection)")
    print("  - Autoencoder (anomaly detection)")
    print("  - LSTM Neural Network (energy prediction)")
    print("\nNext steps:")
    print("1. Check the 'models' directory for trained model files")
    print("2. Use ml_service.load_models() to load models in your API")
    print("3. Integrate predictions and anomaly detection into your routes")

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Train ML models from clean dataset or MongoDB"
    )
    parser.add_argument(
        "--input-csv",
        type=str,
        default=None,
        help="Path to an existing clean dataset CSV",
    )

    args = parser.parse_args()
    main(input_csv=args.input_csv)
