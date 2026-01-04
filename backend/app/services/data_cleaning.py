# backend/app/services/data_cleaning.py
import pandas as pd
import numpy as np
from datetime import datetime
from typing import Tuple

class DataCleaner:
    def __init__(self):
        self.energy_stats = {}
        self.occupancy_stats = {}
    
    def clean_energy_readings(self, df: pd.DataFrame) -> pd.DataFrame:
        """Clean energy readings data"""
        df = df.copy()
        
        # 1. Remove duplicates
        df = df.drop_duplicates(subset=['module', 'location', 'received_at'], keep='last')
        
        # 2. Handle missing values
        # Fill numeric nulls with 0 or median
        numeric_cols = ['current_ma', 'current_a', 'rms_a', 'adc_samples', 'vref', 'wifi_rssi']
        for col in numeric_cols:
            if col in df.columns:
                if col in ['current_ma', 'current_a']:
                    df[col] = df[col].fillna(0)
                else:
                    df[col] = df[col].fillna(df[col].median())
        
        # 3. Remove invalid readings
        # Remove readings where current is negative (unless it's AC RMS)
        df = df[df['current_a'] >= 0]
        
        # Remove garbage values: current_a == 0 AND current_ma == 0 means device not connected
        initial_count = len(df)
        df = df[~((df['current_a'] == 0) & (df['current_ma'] == 0))]
        removed_count = initial_count - len(df)
        if removed_count > 0:
            print(f"  Removed {removed_count} rows where device was not connected (current_a==0 and current_ma==0)")
        
        # Remove outliers using IQR method for current measurements
        if 'current_a' in df.columns:
            Q1 = df['current_a'].quantile(0.25)
            Q3 = df['current_a'].quantile(0.75)
            IQR = Q3 - Q1
            lower_bound = Q1 - 1.5 * IQR
            upper_bound = Q3 + 1.5 * IQR
            df = df[(df['current_a'] >= lower_bound) & (df['current_a'] <= upper_bound)]
        
        # 4. Handle timestamp consistency
        df['received_at'] = pd.to_datetime(df['received_at'], utc=True)
        df = df.sort_values('received_at')
        
        # 5. Calculate derived features
        # Calculate power (assuming standard voltage or use vref if available)
        # Use vref if available, otherwise default to 230V
        df['voltage_v'] = df['vref'].fillna(230.0)  # Default 230V, adjust based on your system
        df['power_w'] = df['current_a'] * df['voltage_v']
        df['power_kwh'] = df['power_w'] / 1000.0
        
        # 6. Extract time features
        df['hour'] = df['received_at'].dt.hour
        df['day_of_week'] = df['received_at'].dt.dayofweek
        df['is_weekend'] = df['day_of_week'].isin([5, 6]).astype(int)
        
        # Store statistics for later use
        self.energy_stats = {
            'mean_current': df['current_a'].mean(),
            'std_current': df['current_a'].std(),
            'mean_power': df['power_w'].mean()
        }
        
        return df
    
    def clean_occupancy_telemetry(self, df: pd.DataFrame) -> pd.DataFrame:
        """Clean occupancy telemetry data"""
        df = df.copy()
        
        # 1. Remove duplicates
        df = df.drop_duplicates(subset=['module', 'location', 'received_at'], keep='last')
        
        # 2. Handle missing values
        df['rcwl'] = df['rcwl'].fillna(0).astype(int)
        df['pir'] = df['pir'].fillna(0).astype(int)
        df['temperature'] = df['temperature'].fillna(df['temperature'].median())
        df['humidity'] = df['humidity'].fillna(df['humidity'].median())
        
        # 3. Create occupancy binary flag
        df['occupied'] = ((df['rcwl'] == 1) | (df['pir'] == 1)).astype(int)
        
        # 4. Handle timestamp
        df['received_at'] = pd.to_datetime(df['received_at'], utc=True)
        df = df.sort_values('received_at')
        
        # 5. Remove invalid sensor readings
        # Temperature and humidity == 0 means sensors are not connected
        initial_count = len(df)
        df = df[~((df['temperature'] == 0) & (df['humidity'] == 0))]
        removed_count = initial_count - len(df)
        if removed_count > 0:
            print(f"  Removed {removed_count} rows where sensors were not connected (temperature==0 and humidity==0)")
        
        # Temperature should be reasonable (-10 to 60°C for indoor)
        df = df[(df['temperature'] >= -10) & (df['temperature'] <= 60)]
        df = df[(df['humidity'] >= 0) & (df['humidity'] <= 100)]
        
        # 6. Extract time features
        df['hour'] = df['received_at'].dt.hour
        df['day_of_week'] = df['received_at'].dt.dayofweek
        df['is_weekend'] = df['day_of_week'].isin([5, 6]).astype(int)
        
        self.occupancy_stats = {
            'mean_temperature': df['temperature'].mean(),
            'mean_humidity': df['humidity'].mean(),
            'occupancy_rate': df['occupied'].mean()
        }
        
        return df
    
    def merge_datasets(self, energy_df: pd.DataFrame, occupancy_df: pd.DataFrame, 
                      merge_window_minutes: int = 5) -> pd.DataFrame:
        """Merge energy and occupancy data based on location and time proximity"""
        
        # Create time windows for merging
        energy_df['time_key'] = energy_df['received_at']
        occupancy_df['time_key'] = occupancy_df['received_at']
        
        # Round timestamps to nearest window
        energy_df['time_window'] = energy_df['received_at'].dt.round(f'{merge_window_minutes}min')
        occupancy_df['time_window'] = occupancy_df['received_at'].dt.round(f'{merge_window_minutes}min')
        
        # Merge on location and time window
        merged_df = pd.merge(
            energy_df,
            occupancy_df[['location', 'time_window', 'occupied', 'temperature', 'humidity', 'rcwl', 'pir']],
            on=['location', 'time_window'],
            how='left',
            suffixes=('_energy', '_occupancy')
        )
        
        # Forward fill occupancy data for missing matches
        merged_df = merged_df.sort_values('received_at')
        merged_df['occupied'] = merged_df['occupied'].ffill().fillna(0)
        merged_df['temperature'] = merged_df['temperature'].ffill().fillna(merged_df['temperature'].mean())
        merged_df['humidity'] = merged_df['humidity'].ffill().fillna(merged_df['humidity'].mean())
        
        return merged_df