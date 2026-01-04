# backend/app/services/ml_service.py
import pandas as pd
import numpy as np
from sklearn.ensemble import IsolationForest, RandomForestRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import pickle
import os
from typing import Tuple, List, Dict
from datetime import datetime, timedelta
from pathlib import Path

class EnergyMLService:
    def __init__(self, model_dir='models'):
        self.model_dir = Path(model_dir)
        self.model_dir.mkdir(parents=True, exist_ok=True)
        
        self.anomaly_model = IsolationForest(contamination=0.1, random_state=42)
        self.prediction_model = RandomForestRegressor(n_estimators=100, random_state=42)
        self.scaler = StandardScaler()
        
        self.is_trained = False
        self.feature_columns = []
        self.target_column = 'power_w'
    
    def train_anomaly_detector(self, df: pd.DataFrame, feature_cols: List[str]):
        """Train anomaly detection model"""
        print("Training anomaly detection model...")
        
        X = df[feature_cols].fillna(0)
        X_scaled = self.scaler.fit_transform(X)
        
        self.anomaly_model.fit(X_scaled)
        
        # Save model
        model_path = self.model_dir / 'anomaly_model.pkl'
        with open(model_path, 'wb') as f:
            pickle.dump({
                'model': self.anomaly_model,
                'scaler': self.scaler,
                'feature_cols': feature_cols
            }, f)
        
        print(f"Anomaly model saved to {model_path}")
        self.is_trained = True
        self.feature_columns = feature_cols
    
    def train_prediction_model(self, df: pd.DataFrame, feature_cols: List[str], target_col: str = 'power_w'):
        """Train energy prediction model"""
        print(f"Training prediction model for {target_col}...")
        
        # Prepare data
        X = df[feature_cols].fillna(0)
        y = df[target_col].fillna(0)
        
        # Remove rows where target is NaN
        valid_mask = ~y.isna()
        X = X[valid_mask]
        y = y[valid_mask]
        
        if len(X) == 0:
            print("Error: No valid data for training")
            return
        
        # Split data
        if len(X) > 10:  # Only split if we have enough data
            X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
        else:
            X_train, X_test, y_train, y_test = X, X, y, y
        
        # Scale features
        scaler_pred = StandardScaler()
        X_train_scaled = scaler_pred.fit_transform(X_train)
        X_test_scaled = scaler_pred.transform(X_test)
        
        # Train model
        self.prediction_model.fit(X_train_scaled, y_train)
        
        # Evaluate
        y_pred = self.prediction_model.predict(X_test_scaled)
        mae = mean_absolute_error(y_test, y_pred)
        rmse = np.sqrt(mean_squared_error(y_test, y_pred))
        r2 = r2_score(y_test, y_pred)
        
        print(f"  Mean Absolute Error (MAE): {mae:.4f} W")
        print(f"  Root Mean Squared Error (RMSE): {rmse:.4f} W")
        print(f"  R² Score: {r2:.4f} (1.0 = perfect, >0.8 = good)")
        
        # Save model
        model_path = self.model_dir / 'prediction_model.pkl'
        with open(model_path, 'wb') as f:
            pickle.dump({
                'model': self.prediction_model,
                'scaler': scaler_pred,
                'feature_cols': feature_cols,
                'target_col': target_col,
                'mae': mae,
                'rmse': rmse,
                'r2': r2
            }, f)
        
        print(f"Prediction model saved to {model_path}")
        self.is_trained = True
        self.feature_columns = feature_cols
        self.target_column = target_col
    
    def detect_anomalies(self, df: pd.DataFrame) -> pd.DataFrame:
        """Detect anomalies in new data"""
        if not self.is_trained or len(self.feature_columns) == 0:
            raise ValueError("Model not trained. Call train_anomaly_detector first.")
        
        # Ensure all feature columns exist
        missing_cols = set(self.feature_columns) - set(df.columns)
        if missing_cols:
            for col in missing_cols:
                df[col] = 0
        
        X = df[self.feature_columns].fillna(0)
        X_scaled = self.scaler.transform(X)
        
        predictions = self.anomaly_model.predict(X_scaled)
        scores = self.anomaly_model.score_samples(X_scaled)
        
        df['is_anomaly'] = (predictions == -1).astype(int)
        df['anomaly_score'] = -scores  # Negative scores indicate anomalies
        
        return df
    
    def predict_energy(self, df: pd.DataFrame, hours_ahead: int = 24) -> pd.DataFrame:
        """Predict future energy consumption"""
        if not self.is_trained or len(self.feature_columns) == 0:
            raise ValueError("Model not trained. Call train_prediction_model first.")
        
        # Ensure all feature columns exist
        missing_cols = set(self.feature_columns) - set(df.columns)
        if missing_cols:
            for col in missing_cols:
                df[col] = 0
        
        # For now, predict next value
        # In production, you'd use time series models like LSTM/Prophet
        X = df[self.feature_columns].fillna(0)
        
        # Load the prediction scaler from saved model
        model_path = self.model_dir / 'prediction_model.pkl'
        if model_path.exists():
            with open(model_path, 'rb') as f:
                model_data = pickle.load(f)
                pred_scaler = model_data['scaler']
                pred_model = model_data['model']
        else:
            pred_scaler = self.scaler
            pred_model = self.prediction_model
        
        X_scaled = pred_scaler.transform(X)
        predictions = pred_model.predict(X_scaled)
        
        df['predicted_power_w'] = predictions
        df['prediction_confidence'] = 0.85  # Placeholder - could calculate from model variance
        
        return df
    
    def load_models(self):
        """Load trained models"""
        anomaly_path = self.model_dir / 'anomaly_model.pkl'
        prediction_path = self.model_dir / 'prediction_model.pkl'
        
        if anomaly_path.exists():
            with open(anomaly_path, 'rb') as f:
                data = pickle.load(f)
                self.anomaly_model = data['model']
                self.scaler = data['scaler']
                self.feature_columns = data['feature_cols']
                self.is_trained = True
                print(f"Loaded anomaly model with {len(self.feature_columns)} features")
        
        if prediction_path.exists():
            with open(prediction_path, 'rb') as f:
                data = pickle.load(f)
                self.prediction_model = data['model']
                self.target_column = data.get('target_col', 'power_w')
                print(f"Loaded prediction model for {self.target_column}")
        
        return self.is_trained

