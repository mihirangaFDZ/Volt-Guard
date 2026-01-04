# backend/train_ml_models.py
"""
Training script for AI-Based Energy Analytics Models
Run this script to:
1. Extract and clean data from MongoDB
2. Create features
3. Train anomaly detection and prediction models
"""
import sys
from pathlib import Path

# Add current directory to path
backend_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(backend_dir))

from app.services.create_clean_dataset import create_clean_dataset
from app.services.ml_service import EnergyMLService
from app.services.lstm_service import LSTMPredictor
import pandas as pd

def main():
    print("=" * 60)
    print("AI-Based Energy Analytics Training Pipeline")
    print("=" * 60)
    
    # Step 1: Create clean dataset
    print("\n[1/3] Creating clean dataset...")
    try:
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
    
    # Step 2: Train models
    print("\n[2/3] Training ML models...")
    try:
        ml_service = EnergyMLService(model_dir='models')
        
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
        
        # Train anomaly detector
        print("\nTraining anomaly detection model...")
        ml_service.train_anomaly_detector(df, numeric_features)
        
        # Train prediction model (only if we have the target column)
        if 'power_w' in df.columns:
            print("\nTraining Random Forest prediction model...")
            ml_service.train_prediction_model(df, numeric_features, target_col='power_w')
            
            # Train LSTM model for time series prediction
            print("\n" + "="*60)
            print("Training LSTM Time Series Model")
            print("="*60)
            lstm = LSTMPredictor(model_dir='models', sequence_length=24, prediction_horizon=1)
            
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
                        seq_length = 12  # Use smaller sequence for small datasets
                    elif available_data < 500:
                        seq_length = 24
                    else:
                        seq_length = 48  # Use longer sequence for larger datasets
                    
                    lstm = LSTMPredictor(model_dir='models', sequence_length=seq_length, prediction_horizon=1)
                    lstm.train(
                        df, 
                        target_col='power_w',
                        feature_cols=lstm_features,
                        epochs=100,  # Increased epochs for better learning
                        batch_size=min(32, len(df) // 10)  # Adaptive batch size
                    )
                    print("\n[SUCCESS] LSTM model trained successfully!")
                except Exception as e:
                    print(f"\n[WARNING] LSTM training failed: {e}")
                    import traceback
                    traceback.print_exc()
                    print("Continuing with Random Forest model only...")
            else:
                print(f"\n[WARNING] Not enough features for LSTM. Need at least 3, got {len(lstm_features)}")
        else:
            print("\nWarning: 'power_w' column not found. Skipping prediction model training.")
            print("Available columns:", list(df.columns)[:10])
        
    except Exception as e:
        print(f"Error training models: {e}")
        import traceback
        traceback.print_exc()
        return
    
    # Step 3: Test predictions
    print("\n[3/3] Testing models...")
    try:
        # Reload models to test loading
        ml_service = EnergyMLService(model_dir='models')
        ml_service.load_models()
        
        if ml_service.is_trained:
            test_df = df.tail(min(100, len(df))).copy()
            
            # Detect anomalies
            print("\nTesting anomaly detection...")
            anomalies = ml_service.detect_anomalies(test_df)
            num_anomalies = anomalies['is_anomaly'].sum()
            print(f"  Detected {num_anomalies} anomalies in test data ({len(test_df)} records)")
            
            # Make predictions (if model was trained)
            if 'power_w' in df.columns:
                print("\nTesting Random Forest predictions...")
                predictions = ml_service.predict_energy(test_df)
                print(f"  Generated {len(predictions)} predictions")
                
                if 'predicted_power_w' in predictions.columns:
                    print(f"  Average predicted power: {predictions['predicted_power_w'].mean():.2f} W")
                
                # Test LSTM if available
                lstm = LSTMPredictor(model_dir='models')
                if lstm.load_model():
                    print("\nTesting LSTM predictions...")
                    try:
                        lstm_predictions = lstm.predict(test_df.tail(50), steps_ahead=5)
                        print(f"  Generated {len(lstm_predictions)} LSTM predictions")
                        print(f"  Next 5 steps ahead: {lstm_predictions['predicted_power_w'].values}")
                    except Exception as e:
                        print(f"  LSTM prediction test failed: {e}")
        else:
            print("Warning: Models not loaded successfully")
            
    except Exception as e:
        print(f"Error testing models: {e}")
        import traceback
        traceback.print_exc()
    
    print("\n" + "=" * 60)
    print("Training Complete!")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Check the 'models' directory for trained model files")
    print("2. Use ml_service.load_models() to load models in your API")
    print("3. Integrate predictions and anomaly detection into your routes")

if __name__ == "__main__":
    main()

