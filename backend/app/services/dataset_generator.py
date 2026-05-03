"""
Clean Dataset Generator
Combines data cleaning and feature engineering to create ML-ready datasets
"""

import pandas as pd
from typing import Optional, Tuple
from pathlib import Path
from datetime import datetime

from .data_cleaner import DataCleaner
from .feature_engineer import FeatureEngineer


class DatasetGenerator:
    """Generates clean, feature-engineered datasets for ML"""
    
    def __init__(self):
        self.cleaner = DataCleaner()
        self.feature_engineer = FeatureEngineer()
    
    def generate_clean_dataset(
        self,
        days: int = 2,
        location: Optional[str] = None,
        module: Optional[str] = None,
        save_path: Optional[str] = None,
        save_featured_path: Optional[str] = None
    ) -> Tuple[pd.DataFrame, pd.DataFrame]:
        """
        Complete pipeline: clean data and create features
        
        Args:
            days: Number of days to process
            location: Filter by location (optional)
            module: Filter by module (optional)
            save_path: Path to save cleaned (non-featured) CSV
            save_featured_path: Path to save featured dataset CSV
            
        Returns:
            Tuple of (cleaned_df, featured_df)
        """
        print("\n" + "=" * 70)
        print("GENERATING CLEAN DATASET FOR AI MODEL")
        print("=" * 70)
        
        # Step 1: Clean data
        cleaned_df = self.cleaner.create_clean_dataset(
            days=days,
            location=location,
            module=module,
            save_path=save_path
        )
        
        if cleaned_df.empty:
            print("\n[WARNING] No data available for the specified criteria")
            return pd.DataFrame(), pd.DataFrame()
        
        # Step 2: Feature engineering
        featured_df = self.feature_engineer.create_all_features(cleaned_df)
        
        # Save featured dataset
        if save_featured_path and not featured_df.empty:
            featured_df.to_csv(save_featured_path, index=False)
            print(f"\n[OK] Featured dataset saved to: {save_featured_path}")
        
        # Print summary
        self._print_dataset_summary(cleaned_df, featured_df)
        
        return cleaned_df, featured_df
    
    def _print_dataset_summary(self, cleaned_df: pd.DataFrame, featured_df: pd.DataFrame):
        """Print summary statistics of the dataset"""
        print("\n" + "=" * 70)
        print("DATASET SUMMARY")
        print("=" * 70)
        
        if cleaned_df.empty:
            print("No data available")
            return
        
        print(f"\nRecords: {len(featured_df)}")
        print(f"Date Range: {featured_df['timestamp'].min()} to {featured_df['timestamp'].max()}")
        
        if 'location' in featured_df.columns:
            locations = featured_df['location'].unique()
            print(f"Locations: {len(locations)} ({', '.join(map(str, locations[:5]))}{'...' if len(locations) > 5 else ''})")
        
        # Energy statistics
        if 'energy_watts' in featured_df.columns:
            energy_stats = featured_df['energy_watts'].describe()
            print(f"\nEnergy Statistics (Watts):")
            print(f"   Mean: {energy_stats['mean']:.2f}")
            print(f"   Std: {energy_stats['std']:.2f}")
            print(f"   Min: {energy_stats['min']:.2f}")
            print(f"   Max: {energy_stats['max']:.2f}")
        
        # Occupancy statistics
        if 'is_occupied' in featured_df.columns:
            occupancy_stats = featured_df['is_occupied'].value_counts()
            total = len(featured_df)
            occupied_pct = (occupancy_stats.get(1, 0) / total * 100) if total > 0 else 0
            vacant_pct = (occupancy_stats.get(0, 0) / total * 100) if total > 0 else 0
            print(f"\nOccupancy Statistics:")
            print(f"   Occupied: {occupancy_stats.get(1, 0)} ({occupied_pct:.1f}%)")
            print(f"   Vacant: {occupancy_stats.get(0, 0)} ({vacant_pct:.1f}%)")
        
        # Feature columns
        feature_cols = self.feature_engineer.get_feature_columns(featured_df)
        print(f"\nFeatures: {len(feature_cols)} columns")
        print(f"   Sample features: {', '.join(feature_cols[:10])}{'...' if len(feature_cols) > 10 else ''}")
        
        print("=" * 70)


def create_dataset_script(
    days: int = 2,
    location: Optional[str] = None,
    module: Optional[str] = None,
    output_dir: str = "data"
):
    """
    Standalone script to generate clean dataset
    
    Usage:
        from app.services.dataset_generator import create_dataset_script
        create_dataset_script(days=2)
    """
    # Create output directory
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    # Generate timestamps for filenames
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    cleaned_path = output_path / f"cleaned_dataset_{timestamp}.csv"
    featured_path = output_path / f"featured_dataset_{timestamp}.csv"
    
    # Generate dataset
    generator = DatasetGenerator()
    cleaned_df, featured_df = generator.generate_clean_dataset(
        days=days,
        location=location,
        module=module,
        save_path=str(cleaned_path),
        save_featured_path=str(featured_path)
    )
    
    return cleaned_df, featured_df

