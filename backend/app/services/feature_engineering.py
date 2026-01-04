# backend/app/services/feature_engineering.py
import pandas as pd
import numpy as np
from typing import List

class FeatureEngineer:
    def __init__(self):
        self.feature_columns = []
    
    def create_time_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Create time-based features"""
        df = df.copy()
        
        df['hour_sin'] = np.sin(2 * np.pi * df['hour'] / 24)
        df['hour_cos'] = np.cos(2 * np.pi * df['hour'] / 24)
        df['day_sin'] = np.sin(2 * np.pi * df['day_of_week'] / 7)
        df['day_cos'] = np.cos(2 * np.pi * df['day_of_week'] / 7)
        
        return df
    
    def create_rolling_features(self, df: pd.DataFrame, group_by: str = 'location') -> pd.DataFrame:
        """Create rolling window features"""
        df = df.copy()
        df = df.sort_values('received_at')
        
        feature_cols = ['current_a', 'power_w']
        
        for col in feature_cols:
            if col in df.columns:
                # Rolling statistics
                df[f'{col}_rolling_mean_1h'] = df.groupby(group_by)[col].transform(
                    lambda x: x.rolling(window=12, min_periods=1).mean()  # 1 hour if 5-min intervals
                )
                df[f'{col}_rolling_std_1h'] = df.groupby(group_by)[col].transform(
                    lambda x: x.rolling(window=12, min_periods=1).std()
                )
                
                # Lag features
                df[f'{col}_lag_1'] = df.groupby(group_by)[col].shift(1)
                df[f'{col}_lag_2'] = df.groupby(group_by)[col].shift(2)
        
        # Fill NaN values - use bfill then ffill, then 0
        for col in df.columns:
            if 'rolling' in col or col.endswith('_lag_1') or col.endswith('_lag_2'):
                df[col] = df[col].bfill().ffill().fillna(0)
        
        return df
    
    def create_aggregated_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Create aggregated features by location"""
        df = df.copy()
        
        # Daily statistics per location
        df['date'] = df['received_at'].dt.date
        
        # Build aggregation dict based on available columns
        agg_dict = {}
        if 'power_w' in df.columns:
            agg_dict['power_w'] = ['mean', 'max', 'min', 'std']
        if 'current_a' in df.columns:
            agg_dict['current_a'] = ['mean', 'max']
        if 'occupied' in df.columns:
            agg_dict['occupied'] = 'mean'
        
        if agg_dict:
            daily_stats = df.groupby(['location', 'date']).agg(agg_dict).reset_index()
            
            # Flatten column names
            daily_stats.columns = ['_'.join(col).strip('_') if isinstance(col, tuple) else col 
                                   for col in daily_stats.columns]
            # Rename to expected format
            rename_dict = {}
            for col in daily_stats.columns:
                if col.startswith('power_w'):
                    if 'mean' in col:
                        rename_dict[col] = 'daily_power_mean'
                    elif 'max' in col:
                        rename_dict[col] = 'daily_power_max'
                    elif 'min' in col:
                        rename_dict[col] = 'daily_power_min'
                    elif 'std' in col:
                        rename_dict[col] = 'daily_power_std'
                elif col.startswith('current_a'):
                    if 'mean' in col:
                        rename_dict[col] = 'daily_current_mean'
                    elif 'max' in col:
                        rename_dict[col] = 'daily_current_max'
                elif col.startswith('occupied'):
                    rename_dict[col] = 'daily_occupancy_rate'
            
            daily_stats = daily_stats.rename(columns=rename_dict)
            df = pd.merge(df, daily_stats, on=['location', 'date'], how='left')
        
        return df.drop('date', axis=1)
    
    def prepare_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Prepare all features for ML models"""
        df = self.create_time_features(df)
        df = self.create_rolling_features(df)
        df = self.create_aggregated_features(df)
        
        # Select feature columns (excluding target and metadata)
        exclude_cols = ['received_at', 'module', 'sensor', 'source', 'type', 'time_key', 'time_window']
        self.feature_columns = [col for col in df.columns if col not in exclude_cols and df[col].dtype in [np.float64, np.int64]]
        
        return df

