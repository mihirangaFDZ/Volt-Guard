# backend/app/services/ml_service.py
import pandas as pd
import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import pickle
import os
from typing import Tuple, List, Dict
from datetime import datetime, timedelta
from pathlib import Path

class EnergyMLService:
    """Anomaly detection service using Isolation Forest"""

    def __init__(self, model_dir='models'):
        self.model_dir = Path(model_dir)
        self.model_dir.mkdir(parents=True, exist_ok=True)

        self.anomaly_model = IsolationForest(contamination=0.1, random_state=42)
        self.scaler = StandardScaler()

        self.is_trained = False
        self.feature_columns = []

    def train_anomaly_detector(self, df: pd.DataFrame, feature_cols: List[str]):
        """Train anomaly detection model"""
        print("Training anomaly detection model (Isolation Forest)...")

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

    def load_models(self):
        """Load trained anomaly detection model"""
        anomaly_path = self.model_dir / 'anomaly_model.pkl'

        if anomaly_path.exists():
            with open(anomaly_path, 'rb') as f:
                data = pickle.load(f)
                self.anomaly_model = data['model']
                self.scaler = data['scaler']
                self.feature_columns = data['feature_cols']
                self.is_trained = True
                print(f"Loaded anomaly model with {len(self.feature_columns)} features")

        return self.is_trained
