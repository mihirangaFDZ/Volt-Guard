# backend/app/services/create_clean_dataset.py
import sys
from pathlib import Path
import pandas as pd
from datetime import datetime
import json

# Add parent directory to path
backend_dir = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(backend_dir))

from app.services.data_extraction import extract_energy_readings, extract_occupancy_telemetry
from app.services.data_cleaning import DataCleaner
from app.services.feature_engineering import FeatureEngineer

def create_clean_dataset(hours_back=48, output_path='clean_dataset.csv'):
    """Main function to create clean dataset"""
    
    print("Step 1: Extracting raw data...")
    energy_df = extract_energy_readings(hours_back=hours_back)
    occupancy_df = extract_occupancy_telemetry(hours_back=hours_back)
    
    print(f"  - Energy readings: {len(energy_df)} records")
    print(f"  - Occupancy telemetry: {len(occupancy_df)} records")
    
    if len(energy_df) == 0 and len(occupancy_df) == 0:
        print("Warning: No data found. Please check your database connection and data.")
        return None, []
    
    print("\nStep 2: Cleaning data...")
    cleaner = DataCleaner()
    
    clean_energy = None
    clean_occupancy = None
    
    if len(energy_df) > 0:
        clean_energy = cleaner.clean_energy_readings(energy_df)
        print(f"  - Clean energy readings: {len(clean_energy)} records")
    else:
        print("  - No energy readings to clean")
    
    if len(occupancy_df) > 0:
        clean_occupancy = cleaner.clean_occupancy_telemetry(occupancy_df)
        print(f"  - Clean occupancy telemetry: {len(clean_occupancy)} records")
    else:
        print("  - No occupancy telemetry to clean")
    
    print("\nStep 3: Merging datasets...")
    if clean_energy is not None and clean_occupancy is not None:
        merged_df = cleaner.merge_datasets(clean_energy, clean_occupancy, merge_window_minutes=5)
        print(f"  - Merged dataset: {len(merged_df)} records")
    elif clean_energy is not None:
        merged_df = clean_energy
        print(f"  - Using energy data only: {len(merged_df)} records")
    elif clean_occupancy is not None:
        merged_df = clean_occupancy
        print(f"  - Using occupancy data only: {len(merged_df)} records")
    else:
        print("  - No data to merge")
        return None, []
    
    print("\nStep 4: Engineering features...")
    feature_engineer = FeatureEngineer()
    final_df = feature_engineer.prepare_features(merged_df)
    print(f"  - Final dataset: {len(final_df)} records")
    print(f"  - Features: {len(feature_engineer.feature_columns)} columns")
    
    print("\nStep 5: Saving clean dataset...")
    output_file = Path(output_path)
    output_file.parent.mkdir(parents=True, exist_ok=True)
    final_df.to_csv(output_path, index=False)
    print(f"  - Saved to: {output_path}")
    
    # Save metadata
    metadata = {
        'created_at': datetime.now().isoformat(),
        'hours_back': hours_back,
        'num_records': len(final_df),
        'feature_columns': feature_engineer.feature_columns,
        'statistics': {
            'energy': cleaner.energy_stats,
            'occupancy': cleaner.occupancy_stats
        }
    }
    
    metadata_path = output_path.replace('.csv', '_metadata.json')
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"  - Metadata saved to: {metadata_path}")
    
    return final_df, feature_engineer.feature_columns

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description='Create clean dataset from raw data')
    parser.add_argument('--hours', type=int, default=48, help='Hours back to extract data')
    parser.add_argument('--output', type=str, default='clean_dataset.csv', help='Output CSV file path')
    
    args = parser.parse_args()
    
    df, features = create_clean_dataset(hours_back=args.hours, output_path=args.output)
    
    if df is not None:
        print(f"\nDataset Summary:")
        print(df.describe())
        print(f"\nFeature columns ({len(features)}): {features[:10]}...")  # Show first 10
    else:
        print("\nFailed to create dataset. Please check the errors above.")

