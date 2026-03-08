"""
Data Cleaning Service for Energy Optimization
Cleans and preprocesses energy_readings and occupancy_telemetry data
"""

from datetime import datetime, timedelta
from typing import List, Dict, Optional, Tuple
import pandas as pd
import numpy as np
from pymongo import MongoClient
from database import energy_col, analytics_col


class DataCleaner:
    """Cleans raw sensor data for AI model training"""
    
    def __init__(self, energy_collection=None, occupancy_collection=None):
        self.energy_col = energy_collection or energy_col
        self.occupancy_col = occupancy_collection or analytics_col
    
    def fetch_raw_data(
        self, 
        days: int = 2,
        location: Optional[str] = None,
        module: Optional[str] = None
    ) -> Tuple[List[Dict], List[Dict]]:
        """
        Fetch raw data from MongoDB collections
        
        Args:
            days: Number of days to fetch (default: 2)
            location: Filter by location (optional)
            module: Filter by module (optional)
            
        Returns:
            Tuple of (energy_readings, occupancy_telemetry) lists
        """
        # Calculate date range
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)
        
        # Build query
        query = {
            "received_at": {
                "$gte": start_date,
                "$lte": end_date
            }
        }
        if location:
            query["location"] = location
        if module:
            query["module"] = module
        
        # Fetch energy readings
        energy_data = list(self.energy_col.find(query))
        
        # Fetch occupancy telemetry
        occupancy_data = list(self.occupancy_col.find(query))
        
        print(f"Fetched {len(energy_data)} energy readings and {len(occupancy_data)} occupancy records")
        
        return energy_data, occupancy_data
    
    def clean_energy_data(self, energy_readings: List[Dict]) -> pd.DataFrame:
        """
        Clean energy_readings data
        
        Steps:
        1. Remove invalid/null readings
        2. Handle missing values
        3. Remove outliers (using IQR method)
        4. Standardize timestamp format
        5. Calculate derived metrics
        """
        if not energy_readings:
            return pd.DataFrame()
        
        # Convert to DataFrame
        df = pd.DataFrame(energy_readings)
        
        # Remove _id column
        if '_id' in df.columns:
            df = df.drop(columns=['_id'])
        
        # Parse timestamp
        df['timestamp'] = pd.to_datetime(
            df.get('received_at', pd.Series([None] * len(df))),
            errors='coerce'
        )
        
        # Drop rows with invalid timestamps
        df = df.dropna(subset=['timestamp'])
        
        # Convert numeric columns and clean garbage values
        numeric_cols = ['current_ma', 'current_a', 'rms_a', 'adc_samples', 'vref', 'wifi_rssi']
        for col in numeric_cols:
            if col in df.columns:
                # Convert to numeric, coercing errors to NaN
                df[col] = pd.to_numeric(df[col], errors='coerce')
                
                # Remove negative values for current measurements (garbage values)
                if col in ['current_ma', 'current_a', 'rms_a']:
                    df[col] = df[col].clip(lower=0)  # Set negative values to 0
                
                # Remove unrealistic values (garbage values)
                if col == 'current_a':
                    # ACS712-20A max is 20A, set unrealistic values (>100A) to NaN
                    df.loc[df[col] > 100, col] = np.nan
                elif col == 'current_ma':
                    # Max should be 20000mA (20A)
                    df.loc[df[col] > 20000, col] = np.nan
                elif col == 'vref':
                    # Typical vref is 3.3V or 5V, remove unrealistic values
                    df.loc[(df[col] < 0) | (df[col] > 10), col] = np.nan
                elif col == 'wifi_rssi':
                    # RSSI typically ranges from -100 to 0, remove unrealistic values
                    df.loc[(df[col] < -100) | (df[col] > 0), col] = np.nan
        
        # Fill missing values for key metrics
        if 'current_a' in df.columns:
            # If current_a is missing but current_ma exists, convert
            mask = df['current_a'].isna() & df['current_ma'].notna()
            df.loc[mask, 'current_a'] = df.loc[mask, 'current_ma'] / 1000.0
        
        if 'rms_a' in df.columns:
            # Use current_a if rms_a is missing
            mask = df['rms_a'].isna() & df['current_a'].notna()
            df.loc[mask, 'rms_a'] = df.loc[mask, 'current_a']
        
        # Remove rows where all current values are NaN or zero (garbage/invalid readings)
        if 'current_a' in df.columns:
            # Keep rows where current_a is valid (not NaN and > 0 or at least one current field has data)
            has_valid_current = (
                df['current_a'].notna() | 
                (df.get('current_ma', pd.Series([False] * len(df))) > 0) |
                (df.get('rms_a', pd.Series([False] * len(df))).notna())
            )
            df = df[has_valid_current].copy()
        
        # Remove outliers using IQR method for current_a (only if we have enough data)
        if 'current_a' in df.columns and len(df) > 10:
            valid_current = df['current_a'].dropna()
            if len(valid_current) > 4:
                Q1 = valid_current.quantile(0.25)
                Q3 = valid_current.quantile(0.75)
                IQR = Q3 - Q1
                if IQR > 0:  # Only filter if IQR is meaningful
                    lower_bound = max(0, Q1 - 3 * IQR)  # Don't go below 0
                    upper_bound = Q3 + 3 * IQR
                    
                    # Keep non-outlier rows
                    df = df[
                        (df['current_a'].isna()) |  # Keep NaN values
                        ((df['current_a'] >= lower_bound) & (df['current_a'] <= upper_bound))
                    ].copy()
        
        # Ensure required columns exist
        required_cols = ['module', 'location', 'timestamp']
        missing_cols = [col for col in required_cols if col not in df.columns]
        if missing_cols:
            for col in missing_cols:
                df[col] = None
        
        # Sort by timestamp
        df = df.sort_values('timestamp').reset_index(drop=True)
        
        print(f"Cleaned {len(df)} energy readings (removed outliers and invalid data)")
        
        return df
    
    def clean_occupancy_data(self, occupancy_telemetry: List[Dict]) -> pd.DataFrame:
        """
        Clean occupancy_telemetry data
        
        Steps:
        1. Remove invalid/null readings
        2. Handle missing values
        3. Standardize timestamp format
        4. Create occupancy status (binary)
        """
        if not occupancy_telemetry:
            return pd.DataFrame()
        
        # Convert to DataFrame
        df = pd.DataFrame(occupancy_telemetry)
        
        # Remove _id column
        if '_id' in df.columns:
            df = df.drop(columns=['_id'])
        
        # Parse timestamp
        df['timestamp'] = pd.to_datetime(
            df.get('received_at', pd.Series([None] * len(df))),
            errors='coerce'
        )
        
        # Drop rows with invalid timestamps
        df = df.dropna(subset=['timestamp'])
        
        # Convert numeric columns and clean garbage values
        numeric_cols = ['rcwl', 'pir', 'temperature', 'humidity', 'rssi', 'uptime', 'heap']
        for col in numeric_cols:
            if col in df.columns:
                # Convert to numeric, coercing errors to NaN
                df[col] = pd.to_numeric(df[col], errors='coerce')
                
                # Remove garbage values for specific columns
                if col in ['rcwl', 'pir']:
                    # Binary values: should be 0 or 1 only
                    df[col] = df[col].clip(lower=0, upper=1)
                    df[col] = df[col].fillna(0)  # Fill NaN with 0 (vacant)
                
                elif col == 'temperature':
                    # Remove unrealistic temperatures (outside -10 to 60°C range)
                    df.loc[(df[col] < -10) | (df[col] > 60), col] = np.nan
                
                elif col == 'humidity':
                    # Humidity should be 0-100%
                    df[col] = df[col].clip(lower=0, upper=100)
                
                elif col == 'rssi':
                    # RSSI typically ranges from -100 to 0
                    df.loc[(df[col] < -100) | (df[col] > 0), col] = np.nan
        
        # Create occupancy status (1 if PIR or RCWL is 1, else 0)
        if 'pir' in df.columns and 'rcwl' in df.columns:
            df['is_occupied'] = ((df['pir'] == 1) | (df['rcwl'] == 1)).astype(int)
        elif 'pir' in df.columns:
            df['is_occupied'] = (df['pir'] == 1).astype(int)
        elif 'rcwl' in df.columns:
            df['is_occupied'] = (df['rcwl'] == 1).astype(int)
        else:
            df['is_occupied'] = 0
        
        # Fill missing temperature/humidity with 0 (sensor not available)
        if 'temperature' in df.columns:
            df['temperature'] = df['temperature'].fillna(0)
        if 'humidity' in df.columns:
            df['humidity'] = df['humidity'].fillna(0)
        
        # Ensure required columns exist
        required_cols = ['module', 'location', 'timestamp']
        missing_cols = [col for col in required_cols if col not in df.columns]
        if missing_cols:
            for col in missing_cols:
                df[col] = None
        
        # Sort by timestamp
        df = df.sort_values('timestamp').reset_index(drop=True)
        
        print(f"Cleaned {len(df)} occupancy records")
        
        return df
    
    def merge_datasets(
        self, 
        energy_df: pd.DataFrame, 
        occupancy_df: pd.DataFrame,
        merge_method: str = 'forward_fill'
    ) -> pd.DataFrame:
        """
        Merge energy and occupancy data by location and timestamp
        
        Args:
            energy_df: Cleaned energy DataFrame
            occupancy_df: Cleaned occupancy DataFrame
            merge_method: 'forward_fill' or 'nearest' (default: 'forward_fill')
            
        Returns:
            Merged DataFrame with both energy and occupancy data
        """
        if energy_df.empty and occupancy_df.empty:
            return pd.DataFrame()
        
        if energy_df.empty:
            return occupancy_df
        if occupancy_df.empty:
            return energy_df
        
        # Merge on location and approximate timestamp matching
        # Strategy: For each energy reading, find the closest occupancy reading within 5 minutes
        
        merged_data = []
        
        for location in energy_df['location'].unique():
            location_energy = energy_df[energy_df['location'] == location].copy()
            location_occupancy = occupancy_df[occupancy_df['location'] == location].copy()
            
            if location_occupancy.empty:
                # If no occupancy data, just add energy data with null occupancy
                location_energy['is_occupied'] = None
                location_energy['temperature'] = None
                location_energy['humidity'] = None
                merged_data.append(location_energy)
                continue
            
            # Set timestamp as index for easier merging
            location_energy = location_energy.set_index('timestamp')
            location_occupancy = location_occupancy.set_index('timestamp')
            
            # Reindex occupancy to energy timestamps with forward fill
            occupancy_cols = ['is_occupied', 'temperature', 'humidity']
            available_occupancy_cols = [col for col in occupancy_cols if col in location_occupancy.columns]
            
            if available_occupancy_cols:
                location_occupancy_reindexed = location_occupancy[available_occupancy_cols].reindex(
                    location_energy.index,
                    method=merge_method if merge_method == 'ffill' else 'nearest',
                    limit=1  # Limit to 5 minutes (would need time delta for precise control)
                )
                
                # Merge back
                for col in available_occupancy_cols:
                    location_energy[col] = location_occupancy_reindexed[col].values
            
            location_energy = location_energy.reset_index()
            merged_data.append(location_energy)
        
        # Combine all locations
        if merged_data:
            merged_df = pd.concat(merged_data, ignore_index=True)
            merged_df = merged_df.sort_values('timestamp').reset_index(drop=True)
            print(f"Merged dataset: {len(merged_df)} records")
            return merged_df
        
        return pd.DataFrame()
    
    def create_clean_dataset(
        self,
        days: int = 2,
        location: Optional[str] = None,
        module: Optional[str] = None,
        save_path: Optional[str] = None
    ) -> pd.DataFrame:
        """
        Complete pipeline: fetch, clean, and merge data
        
        Args:
            days: Number of days to process
            location: Filter by location (optional)
            module: Filter by module (optional)
            save_path: Path to save cleaned CSV (optional)
            
        Returns:
            Clean, merged DataFrame ready for ML
        """
        print("=" * 60)
        print("STEP 1: DATA CLEANING PIPELINE")
        print("=" * 60)
        
        # Step 1: Fetch raw data
        print("\n[1/4] Fetching raw data from MongoDB...")
        energy_data, occupancy_data = self.fetch_raw_data(days, location, module)
        
        # Step 2: Clean energy data
        print("\n[2/4] Cleaning energy readings...")
        energy_df = self.clean_energy_data(energy_data)
        
        # Step 3: Clean occupancy data
        print("\n[3/4] Cleaning occupancy telemetry...")
        occupancy_df = self.clean_occupancy_data(occupancy_data)
        
        # Step 4: Merge datasets
        print("\n[4/4] Merging energy and occupancy data...")
        merged_df = self.merge_datasets(energy_df, occupancy_df)
        
        # Save if path provided
        if save_path and not merged_df.empty:
            merged_df.to_csv(save_path, index=False)
            print(f"\n[OK] Clean dataset saved to: {save_path}")
        
        print("\n" + "=" * 60)
        print(f"Clean dataset created: {len(merged_df)} records")
        if not merged_df.empty:
            print(f"Columns: {list(merged_df.columns)}")
            print(f"Date range: {merged_df['timestamp'].min()} to {merged_df['timestamp'].max()}")
        print("=" * 60)
        
        return merged_df

