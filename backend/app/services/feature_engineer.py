"""
Feature Engineering Service for Energy Optimization
Creates ML-ready features from cleaned sensor data
"""

import pandas as pd
import numpy as np
from datetime import datetime
from typing import Optional


class FeatureEngineer:
    """Creates features for ML model training"""
    
    def __init__(self):
        pass
    
    def create_time_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Create time-based features from timestamp
        
        Features:
        - hour: Hour of day (0-23)
        - day_of_week: Day of week (0=Monday, 6=Sunday)
        - is_weekend: Binary (1 if weekend, 0 otherwise)
        - month: Month (1-12)
        - day_of_month: Day of month (1-31)
        """
        if 'timestamp' not in df.columns:
            return df
        
        df = df.copy()
        df['timestamp'] = pd.to_datetime(df['timestamp'])
        
        # Time features
        df['hour'] = df['timestamp'].dt.hour
        df['day_of_week'] = df['timestamp'].dt.dayofweek  # 0=Monday, 6=Sunday
        df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)
        df['month'] = df['timestamp'].dt.month
        df['day_of_month'] = df['timestamp'].dt.day
        
        # Cyclical encoding for hour (sine/cosine)
        df['hour_sin'] = np.sin(2 * np.pi * df['hour'] / 24)
        df['hour_cos'] = np.cos(2 * np.pi * df['hour'] / 24)
        
        # Cyclical encoding for day of week
        df['day_of_week_sin'] = np.sin(2 * np.pi * df['day_of_week'] / 7)
        df['day_of_week_cos'] = np.cos(2 * np.pi * df['day_of_week'] / 7)
        
        return df
    
    def create_energy_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Create energy-related features
        
        Features:
        - energy_watts: Estimated power consumption (assuming 220V)
        - energy_rolling_mean: Rolling average of energy
        - energy_rolling_std: Rolling std of energy
        - energy_lag_1: Previous reading value
        - energy_change: Change from previous reading
        """
        df = df.copy()
        
        # Calculate power (Watts) = Voltage * Current
        # Assuming 220V for Sri Lanka
        voltage = 220.0
        if 'rms_a' in df.columns and df['rms_a'].notna().any():
            df['energy_watts'] = voltage * df['rms_a']
        elif 'current_a' in df.columns and df['current_a'].notna().any():
            df['energy_watts'] = voltage * df['current_a']
        else:
            df['energy_watts'] = 0.0
        
        # Sort by timestamp for rolling features
        if 'timestamp' in df.columns:
            df = df.sort_values('timestamp').reset_index(drop=True)
        
        # Rolling statistics (last 10 readings, ~5-10 minutes if readings every 30s-1min)
        if 'energy_watts' in df.columns:
            window_size = min(10, len(df) // 2) if len(df) > 1 else 1
            
            df['energy_rolling_mean'] = df['energy_watts'].rolling(
                window=window_size, 
                min_periods=1
            ).mean()
            
            df['energy_rolling_std'] = df['energy_watts'].rolling(
                window=window_size, 
                min_periods=1
            ).std().fillna(0)
            
            # Lag features
            df['energy_lag_1'] = df['energy_watts'].shift(1).fillna(df['energy_watts'].iloc[0])
            df['energy_change'] = df['energy_watts'] - df['energy_lag_1']
        
        return df
    
    def create_occupancy_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Create occupancy-related features
        
        Features:
        - occupancy_duration: How long has room been occupied/vacant
        - occupancy_rolling_mean: Average occupancy over time window
        """
        df = df.copy()
        
        if 'is_occupied' not in df.columns:
            df['is_occupied'] = 0
        
        # Sort by timestamp
        if 'timestamp' in df.columns:
            df = df.sort_values('timestamp').reset_index(drop=True)
        
        # Occupancy duration (how many consecutive readings in current state)
        df['occupancy_duration'] = 0
        if len(df) > 0:
            occupancy_state = df['is_occupied'].fillna(0).values
            duration = np.zeros(len(df))
            current_duration = 1
            current_state = occupancy_state[0]
            
            for i in range(1, len(df)):
                if occupancy_state[i] == current_state:
                    current_duration += 1
                else:
                    current_duration = 1
                    current_state = occupancy_state[i]
                duration[i] = current_duration
            
            df['occupancy_duration'] = duration
        
        # Rolling mean of occupancy
        window_size = min(10, len(df) // 2) if len(df) > 1 else 1
        df['occupancy_rolling_mean'] = df['is_occupied'].rolling(
            window=window_size,
            min_periods=1
        ).mean().fillna(0)
        
        return df
    
    def create_location_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Create location-specific features (one-hot encoding)
        """
        df = df.copy()
        
        if 'location' in df.columns:
            # Create location dummies (one-hot encoding)
            location_dummies = pd.get_dummies(df['location'], prefix='location')
            df = pd.concat([df, location_dummies], axis=1)
        
        if 'module' in df.columns:
            # Create module dummies
            module_dummies = pd.get_dummies(df['module'], prefix='module')
            df = pd.concat([df, module_dummies], axis=1)
        
        return df
    
    def create_all_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Apply all feature engineering steps
        
        Args:
            df: Cleaned DataFrame from DataCleaner
            
        Returns:
            DataFrame with all engineered features
        """
        print("\n" + "=" * 60)
        print("STEP 2: FEATURE ENGINEERING")
        print("=" * 60)
        
        if df.empty:
            return df
        
        print(f"\nStarting with {len(df)} records, {len(df.columns)} columns")
        
        # Apply feature engineering steps
        print("\n[1/4] Creating time features...")
        df = self.create_time_features(df)
        
        print("[2/4] Creating energy features...")
        df = self.create_energy_features(df)
        
        print("[3/4] Creating occupancy features...")
        df = self.create_occupancy_features(df)
        
        print("[4/4] Creating location features...")
        df = self.create_location_features(df)
        
        print(f"\n[OK] Feature engineering complete!")
        print(f"Final dataset: {len(df)} records, {len(df.columns)} columns")
        print("=" * 60)
        
        return df
    
    def get_feature_columns(self, df: pd.DataFrame) -> list:
        """
        Get list of feature columns (excluding metadata and target)
        
        Returns:
            List of feature column names
        """
        exclude_cols = [
            'timestamp', 'module', 'location', 'sensor', 'source', 'type',
            'received_at', 'receivedAt', '_id', 'ip', 'mac', 'adc_samples',
            'vref', 'wifi_rssi', 'rssi', 'uptime', 'heap',
            'current_ma',  # We use current_a/rms_a instead
        ]
        
        feature_cols = [col for col in df.columns if col not in exclude_cols]
        return feature_cols

