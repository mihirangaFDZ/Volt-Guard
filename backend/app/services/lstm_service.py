# backend/app/services/lstm_service.py
"""
LSTM (Long Short-Term Memory) Model for Time Series Energy Prediction

LSTM is a type of Recurrent Neural Network (RNN) that's perfect for time series data
because it can remember patterns over long sequences of time.
"""
import pandas as pd
import numpy as np
from tensorflow.keras.models import Sequential, load_model
from tensorflow.keras.layers import LSTM, Dense, Dropout
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import pickle
from pathlib import Path
from typing import Tuple, List
import warnings
warnings.filterwarnings('ignore')

class LSTMPredictor:
    """
    LSTM Model for Energy Consumption Time Series Prediction
    
    How it works:
    1. Takes sequences of historical data (e.g., last 24 hours)
    2. Learns patterns in the sequence
    3. Predicts future values (e.g., next hour, next 24 hours)
    
    LSTM Architecture:
    - Input Layer: Receives sequences of features
    - LSTM Layers: Learn temporal patterns (memory cells)
    - Dropout: Prevents overfitting
    - Dense Layer: Outputs prediction
    """
    
    def __init__(self, model_dir='models', sequence_length=24, prediction_horizon=1):
        """
        Initialize LSTM Predictor
        
        Args:
            sequence_length: How many time steps to look back (e.g., 24 = last 24 readings)
            prediction_horizon: How many steps ahead to predict (e.g., 1 = next reading)
        """
        self.model_dir = Path(model_dir)
        self.model_dir.mkdir(parents=True, exist_ok=True)
        
        self.sequence_length = sequence_length  # Look back 24 time steps
        self.prediction_horizon = prediction_horizon  # Predict 1 step ahead
        self.model = None
        self.scaler = MinMaxScaler(feature_range=(0, 1))
        self.target_scaler = MinMaxScaler(feature_range=(0, 1))
        self.is_trained = False
        self.feature_columns = []
        self.target_column = 'power_w'
        
    def create_sequences(self, data: np.ndarray, target: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """
        Create sequences for LSTM training
        
        Example:
        If sequence_length=3 and we have data [1,2,3,4,5,6]:
        X sequences: [[1,2,3], [2,3,4], [3,4,5]]
        y targets:   [4, 5, 6]
        
        This teaches the model: "Given these 3 values, predict the next value"
        """
        X, y = [], []
        for i in range(len(data) - self.sequence_length - self.prediction_horizon + 1):
            # Get sequence of features
            X.append(data[i:(i + self.sequence_length)])
            # Get target value (prediction_horizon steps ahead)
            y.append(target[i + self.sequence_length + self.prediction_horizon - 1])
        return np.array(X), np.array(y)
    
    def train(self, df: pd.DataFrame, target_col: str = 'power_w', 
              feature_cols: List[str] = None, epochs: int = 50, batch_size: int = 32):
        """
        Train LSTM model on time series data
        
        Training Process:
        1. Prepare data: Sort by time, extract features
        2. Scale data: Normalize to 0-1 range (LSTM works better with normalized data)
        3. Create sequences: Convert to sliding windows
        4. Build model: LSTM layers with dropout
        5. Train: Learn patterns from sequences
        6. Evaluate: Check accuracy on test data
        """
        print(f"\n{'='*60}")
        print("Training LSTM Time Series Model")
        print(f"{'='*60}")
        
        # Prepare data
        df = df.sort_values('received_at').copy()
        df = df.reset_index(drop=True)
        
        # Select features
        if feature_cols is None:
            # Use time-based and energy features
            feature_cols = [
                'current_a', 'power_w', 'hour_sin', 'hour_cos', 
                'day_sin', 'day_cos', 'is_weekend'
            ]
            # Only use columns that exist
            feature_cols = [col for col in feature_cols if col in df.columns]
        
        self.feature_columns = feature_cols
        self.target_column = target_col
        
        # Extract features and target
        X_data = df[feature_cols].fillna(0).values
        y_data = df[target_col].fillna(0).values.reshape(-1, 1)
        
        # Scale data (critical for LSTM performance)
        print(f"Scaling {len(X_data)} samples...")
        X_scaled = self.scaler.fit_transform(X_data)
        y_scaled = self.target_scaler.fit_transform(y_data)
        
        # Create sequences
        print(f"Creating sequences (look back: {self.sequence_length} steps)...")
        X_seq, y_seq = self.create_sequences(X_scaled, y_scaled.flatten())
        
        if len(X_seq) < 50:
            print(f"Warning: Only {len(X_seq)} sequences available. Need at least 50 for good training.")
            print("Consider reducing sequence_length or collecting more data.")
            return
        
        # Split data (80% train, 20% test) - IMPORTANT: Don't shuffle time series!
        split_idx = int(len(X_seq) * 0.8)
        X_train, X_test = X_seq[:split_idx], X_seq[split_idx:]
        y_train, y_test = y_seq[:split_idx], y_seq[split_idx:]
        
        print(f"Training sequences: {len(X_train)}, Test sequences: {len(X_test)}")
        
        # Build LSTM Model
        print("\nBuilding LSTM architecture...")
        self.model = Sequential([
            # First LSTM layer with return_sequences=True (passes full sequence to next layer)
            LSTM(units=50, return_sequences=True, input_shape=(self.sequence_length, len(feature_cols))),
            Dropout(0.2),  # Drop 20% of connections to prevent overfitting
            
            # Second LSTM layer
            LSTM(units=50, return_sequences=False),
            Dropout(0.2),
            
            # Dense layer (fully connected)
            Dense(units=25),
            Dense(units=1)  # Output: single prediction value
        ])
        
        # Compile model
        self.model.compile(
            optimizer='adam',  # Adaptive learning rate optimizer
            loss='mean_squared_error',  # Minimize prediction error
            metrics=['mae']  # Track Mean Absolute Error
        )
        
        print("\nModel Architecture:")
        self.model.summary()
        
        # Callbacks for better training
        early_stop = EarlyStopping(
            monitor='val_loss',
            patience=10,  # Stop if no improvement for 10 epochs
            restore_best_weights=True
        )
        
        checkpoint = ModelCheckpoint(
            self.model_dir / 'lstm_best_model.h5',
            monitor='val_loss',
            save_best_only=True,
            verbose=1
        )
        
        # Train model
        print(f"\nTraining for up to {epochs} epochs...")
        print("(Training will stop early if model stops improving)")
        
        history = self.model.fit(
            X_train, y_train,
            validation_data=(X_test, y_test),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=[early_stop, checkpoint],
            verbose=1
        )
        
        # Evaluate on test set
        print("\nEvaluating on test set...")
        y_pred_scaled = self.model.predict(X_test, verbose=0)
        
        # Inverse transform to get actual values
        y_pred = self.target_scaler.inverse_transform(y_pred_scaled)
        y_test_actual = self.target_scaler.inverse_transform(y_test.reshape(-1, 1))
        
        # Calculate metrics
        mae = mean_absolute_error(y_test_actual, y_pred)
        rmse = np.sqrt(mean_squared_error(y_test_actual, y_pred))
        r2 = r2_score(y_test_actual, y_pred)
        
        print(f"\n{'='*60}")
        print("LSTM Model Performance:")
        print(f"{'='*60}")
        print(f"Mean Absolute Error (MAE): {mae:.4f} W")
        print(f"Root Mean Squared Error (RMSE): {rmse:.4f} W")
        print(f"R² Score (closer to 1 is better): {r2:.4f}")
        print(f"{'='*60}\n")
        
        # Save model and scalers
        self.save_model()
        self.is_trained = True
        
        return history
    
    def predict(self, df: pd.DataFrame, steps_ahead: int = 24) -> pd.DataFrame:
        """
        Predict future energy consumption
        
        How it works:
        1. Take the last N sequences from historical data
        2. Feed them to the trained LSTM model
        3. Model predicts next value
        4. Use that prediction to predict the next, and so on (multi-step)
        """
        if not self.is_trained or self.model is None:
            self.load_model()
        
        if not self.is_trained:
            raise ValueError("Model not trained. Call train() first.")
        
        df = df.sort_values('received_at').copy()
        df = df.reset_index(drop=True)
        
        # Get last sequence
        X_data = df[self.feature_columns].fillna(0).values
        X_scaled = self.scaler.transform(X_data)
        
        # Get the last sequence_length rows
        last_sequence = X_scaled[-self.sequence_length:].reshape(1, self.sequence_length, len(self.feature_columns))
        
        # Predict
        predictions = []
        current_sequence = last_sequence.copy()
        
        for _ in range(steps_ahead):
            # Predict next value
            pred_scaled = self.model.predict(current_sequence, verbose=0)
            pred_actual = self.target_scaler.inverse_transform(pred_scaled)[0, 0]
            predictions.append(pred_actual)
            
            # Update sequence for next prediction (shift window)
            # In production, you'd update with actual new data
            new_row = current_sequence[0, 1:, :]  # Remove first row
            # Append prediction (simplified - in reality, update all features)
            new_row = np.vstack([new_row, current_sequence[0, -1:, :]])
            current_sequence = new_row.reshape(1, self.sequence_length, len(self.feature_columns))
        
        # Create result dataframe
        result = pd.DataFrame({
            'predicted_power_w': predictions,
            'step_ahead': range(1, steps_ahead + 1)
        })
        
        return result
    
    def save_model(self):
        """Save trained model and scalers"""
        # Save Keras model
        model_path = self.model_dir / 'lstm_model.h5'
        if self.model:
            self.model.save(model_path)
            print(f"Saved LSTM model to {model_path}")
        
        # Save scalers and metadata
        scaler_path = self.model_dir / 'lstm_scalers.pkl'
        with open(scaler_path, 'wb') as f:
            pickle.dump({
                'feature_scaler': self.scaler,
                'target_scaler': self.target_scaler,
                'feature_columns': self.feature_columns,
                'target_column': self.target_column,
                'sequence_length': self.sequence_length,
                'prediction_horizon': self.prediction_horizon
            }, f)
        print(f"Saved scalers to {scaler_path}")
    
    def load_model(self):
        """Load trained model and scalers"""
        model_path = self.model_dir / 'lstm_model.h5'
        scaler_path = self.model_dir / 'lstm_scalers.pkl'
        
        if model_path.exists() and scaler_path.exists():
            self.model = load_model(model_path)
            
            with open(scaler_path, 'rb') as f:
                data = pickle.load(f)
                self.scaler = data['feature_scaler']
                self.target_scaler = data['target_scaler']
                self.feature_columns = data['feature_columns']
                self.target_column = data['target_column']
                self.sequence_length = data['sequence_length']
                self.prediction_horizon = data['prediction_horizon']
            
            self.is_trained = True
            print(f"Loaded LSTM model from {model_path}")
            return True
        
        return False

