"""
Test script for AI energy optimization recommendations
Usage: python scripts/test_recommendations.py
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.energy_optimizer import EnergyOptimizer
from app.services.dataset_generator import DatasetGenerator


def main():
    """Test the recommendations system"""
    print("=" * 70)
    print("AI Energy Optimization Recommendations Test")
    print("=" * 70)
    
    try:
        # Initialize optimizer and load model
        print("\n[1/3] Loading trained model...")
        optimizer = EnergyOptimizer()
        
        if not optimizer.load_model():
            print("\n[ERROR] Model not found. Please train the model first:")
            print("  python scripts/train_optimization_model.py")
            sys.exit(1)
        
        print("[OK] Model loaded successfully")
        
        # Generate clean dataset
        print("\n[2/3] Generating clean dataset...")
        generator = DatasetGenerator()
        _, df = generator.generate_clean_dataset(days=2)
        
        if df.empty:
            print("\n[ERROR] No data available")
            sys.exit(1)
        
        print(f"[OK] Dataset created: {len(df)} records")
        
        # Get latest reading info
        if len(df) > 0:
            latest = df.iloc[-1]
            if 'energy_watts' in latest.index:
                print(f"   Latest energy: {latest['energy_watts']:.2f} Watts")
            if 'is_occupied' in latest.index:
                occupied = "Yes" if latest['is_occupied'] == 1 else "No"
                print(f"   Room occupied: {occupied}")
            if 'temperature' in latest.index and latest['temperature'] is not None:
                print(f"   Temperature: {latest['temperature']:.1f}°C")
        
        # Generate recommendations
        print("\n[3/3] Generating recommendations...")
        recommendations = optimizer.generate_recommendations(
            df,
            threshold_high=1000.0,  # High energy threshold
            threshold_low=100.0     # Low energy threshold
        )
        
        print(f"[OK] Generated {len(recommendations)} recommendations\n")
        
        # Display recommendations
        if recommendations:
            print("=" * 70)
            print("RECOMMENDATIONS")
            print("=" * 70)
            
            for i, rec in enumerate(recommendations, 1):
                severity = rec['severity'].upper()
                title = rec['title']
                message = rec['message']
                savings = rec['estimated_savings']
                
                print(f"\n[{severity}] {title}")
                print(f"   {message}")
                if savings > 0:
                    print(f"   Estimated savings: {savings:.2f} kWh/day")
        else:
            print("\nNo recommendations at this time.")
            print("Current energy consumption is within optimal range.")
        
        # Show predictions
        print("\n" + "=" * 70)
        print("ENERGY PREDICTIONS")
        print("=" * 70)
        
        predictions = optimizer.predict(df)
        if len(predictions) > 0:
            latest_pred = predictions[-1]
            print(f"\nPredicted energy consumption: {latest_pred:.2f} Watts")
            
            if len(df) > 0 and 'energy_watts' in df.columns:
                current_energy = df.iloc[-1]['energy_watts']
                print(f"Current energy consumption: {current_energy:.2f} Watts")
                diff = latest_pred - current_energy
                if abs(diff) > 1:
                    trend = "increasing" if diff > 0 else "decreasing"
                    print(f"Trend: {trend} by {abs(diff):.2f} Watts")
        
        print("\n" + "=" * 70)
        print("[OK] Test completed successfully!")
        print("=" * 70)
        
    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

