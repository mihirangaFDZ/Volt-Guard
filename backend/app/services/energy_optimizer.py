"""
AI-Driven Energy Optimization Model
Trains models to predict energy consumption and generate optimization recommendations
"""

import pandas as pd
import numpy as np
from typing import Optional, Dict, List, Tuple
from pathlib import Path
import pickle
from datetime import datetime
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import warnings
warnings.filterwarnings('ignore')

from .dataset_generator import DatasetGenerator
from .feature_engineer import FeatureEngineer


class EnergyOptimizer:
    """AI model for energy optimization and prediction"""
    
    def __init__(self):
        self.generator = DatasetGenerator()
        self.feature_engineer = FeatureEngineer()
        self.model = None
        self.scaler = StandardScaler()
        self.feature_columns = []
        self.model_path = Path("models/energy_optimizer.pkl")
        self.scaler_path = Path("models/scaler.pkl")
        self.metadata_path = Path("models/metadata.pkl")
        
        # Create models directory
        self.model_path.parent.mkdir(parents=True, exist_ok=True)
    
    def prepare_data(
        self,
        df: pd.DataFrame,
        target_column: str = 'energy_watts'
    ) -> Tuple[pd.DataFrame, pd.Series, List[str]]:
        """
        Prepare data for training
        
        Args:
            df: Featured DataFrame
            target_column: Column to predict
            
        Returns:
            Tuple of (X, y, feature_columns)
        """
        if df.empty:
            raise ValueError("DataFrame is empty")
        
        # Get feature columns
        feature_cols = self.feature_engineer.get_feature_columns(df)
        
        # Remove target from features if present
        feature_cols = [col for col in feature_cols if col != target_column]
        
        # Select features that exist in DataFrame
        available_features = [col for col in feature_cols if col in df.columns]
        
        if not available_features:
            raise ValueError("No feature columns available")
        
        # Prepare X and y
        X = df[available_features].copy()
        y = df[target_column].copy()
        
        # Handle missing values
        X = X.fillna(0)
        y = y.fillna(0)
        
        # Remove infinite values
        X = X.replace([np.inf, -np.inf], 0)
        y = y.replace([np.inf, -np.inf], 0)
        
        return X, y, available_features
    
    def train_model(
        self,
        days: int = 2,
        location: Optional[str] = None,
        module: Optional[str] = None,
        model_type: str = 'random_forest',
        test_size: float = 0.2,
        target_column: str = 'energy_watts'
    ) -> Dict:
        """
        Train energy optimization model
        
        Args:
            days: Number of days of data to use
            location: Filter by location (optional)
            module: Filter by module (optional)
            model_type: 'random_forest' or 'gradient_boosting'
            test_size: Proportion of data for testing
            target_column: Column to predict
            
        Returns:
            Dictionary with training results and metrics
        """
        print("\n" + "=" * 70)
        print("STEP 4: AI MODEL TRAINING")
        print("=" * 70)
        
        # Step 1: Generate clean dataset
        print("\n[1/4] Generating clean dataset...")
        _, featured_df = self.generator.generate_clean_dataset(
            days=days,
            location=location,
            module=module
        )
        
        if featured_df.empty:
            raise ValueError("No data available for training")
        
        # Step 2: Prepare data
        print("\n[2/4] Preparing data for training...")
        X, y, feature_cols = self.prepare_data(featured_df, target_column)
        self.feature_columns = feature_cols
        
        print(f"   Features: {len(feature_cols)}")
        print(f"   Samples: {len(X)}")
        print(f"   Target: {target_column}")
        
        # Step 3: Split data
        print("\n[3/4] Splitting data into train/test sets...")
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42
        )
        
        print(f"   Train samples: {len(X_train)}")
        print(f"   Test samples: {len(X_test)}")
        
        # Step 4: Scale features
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)
        
        # Step 5: Train model
        print(f"\n[4/4] Training {model_type} model...")
        
        if model_type == 'random_forest':
            self.model = RandomForestRegressor(
                n_estimators=100,
                max_depth=10,
                min_samples_split=5,
                min_samples_leaf=2,
                random_state=42,
                n_jobs=-1
            )
        elif model_type == 'gradient_boosting':
            self.model = GradientBoostingRegressor(
                n_estimators=100,
                max_depth=5,
                learning_rate=0.1,
                random_state=42
            )
        else:
            raise ValueError(f"Unknown model_type: {model_type}")
        
        self.model.fit(X_train_scaled, y_train)
        
        # Step 6: Evaluate model
        print("\nEvaluating model...")
        y_train_pred = self.model.predict(X_train_scaled)
        y_test_pred = self.model.predict(X_test_scaled)
        
        train_mae = mean_absolute_error(y_train, y_train_pred)
        test_mae = mean_absolute_error(y_test, y_test_pred)
        train_rmse = np.sqrt(mean_squared_error(y_train, y_train_pred))
        test_rmse = np.sqrt(mean_squared_error(y_test, y_test_pred))
        train_r2 = r2_score(y_train, y_train_pred)
        test_r2 = r2_score(y_test, y_test_pred)
        
        print(f"\nModel Performance:")
        print(f"   Train MAE: {train_mae:.2f} Watts")
        print(f"   Test MAE: {test_mae:.2f} Watts")
        print(f"   Train RMSE: {train_rmse:.2f} Watts")
        print(f"   Test RMSE: {test_rmse:.2f} Watts")
        print(f"   Train R²: {train_r2:.4f}")
        print(f"   Test R²: {test_r2:.4f}")
        
        # Step 7: Feature importance
        if hasattr(self.model, 'feature_importances_'):
            feature_importance = pd.DataFrame({
                'feature': feature_cols,
                'importance': self.model.feature_importances_
            }).sort_values('importance', ascending=False)
            
            print(f"\nTop 10 Most Important Features:")
            for i, row in feature_importance.head(10).iterrows():
                print(f"   {row['feature']}: {row['importance']:.4f}")
        
        # Step 8: Save model
        self.save_model()
        
        results = {
            'train_mae': train_mae,
            'test_mae': test_mae,
            'train_rmse': train_rmse,
            'test_rmse': test_rmse,
            'train_r2': train_r2,
            'test_r2': test_r2,
            'n_samples': len(X),
            'n_features': len(feature_cols),
            'feature_columns': feature_cols,
            'model_type': model_type
        }
        
        print("\n[OK] Model training complete!")
        print("=" * 70)
        
        return results
    
    def save_model(self):
        """Save trained model and scaler"""
        # Save model
        with open(self.model_path, 'wb') as f:
            pickle.dump(self.model, f)
        
        # Save scaler
        with open(self.scaler_path, 'wb') as f:
            pickle.dump(self.scaler, f)
        
        # Save metadata
        metadata = {
            'feature_columns': self.feature_columns,
            'timestamp': datetime.now().isoformat()
        }
        with open(self.metadata_path, 'wb') as f:
            pickle.dump(metadata, f)
        
        print(f"\n[OK] Model saved to: {self.model_path}")
    
    def load_model(self) -> bool:
        """Load trained model and scaler"""
        try:
            if not self.model_path.exists():
                return False
            
            with open(self.model_path, 'rb') as f:
                self.model = pickle.load(f)
            
            with open(self.scaler_path, 'rb') as f:
                self.scaler = pickle.load(f)
            
            with open(self.metadata_path, 'rb') as f:
                metadata = pickle.load(f)
                self.feature_columns = metadata.get('feature_columns', [])
            
            return True
        except Exception as e:
            print(f"Error loading model: {e}")
            return False
    
    def predict(self, df: pd.DataFrame) -> np.ndarray:
        """
        Predict energy consumption for new data
        
        Args:
            df: DataFrame with features (will be feature-engineered if needed)
            
        Returns:
            Array of predictions
        """
        if self.model is None:
            if not self.load_model():
                raise ValueError("Model not trained. Please train the model first.")
        
        # Feature engineering if needed
        if 'energy_watts' not in df.columns or 'hour' not in df.columns:
            df = self.feature_engineer.create_all_features(df)
        
        # Prepare features
        X, _, _ = self.prepare_data(df, target_column='energy_watts')
        
        # Select only the features the model was trained on
        available_features = [col for col in self.feature_columns if col in X.columns]
        X = X[available_features].copy()
        
        # Fill missing features with 0
        for col in self.feature_columns:
            if col not in X.columns:
                X[col] = 0
        
        # Ensure correct order
        X = X[self.feature_columns]
        
        # Scale and predict
        X_scaled = self.scaler.transform(X)
        predictions = self.model.predict(X_scaled)
        
        return predictions
    
    def generate_recommendations(
        self,
        df: pd.DataFrame,
        threshold_high: float = 1000.0,
        threshold_low: float = 100.0
    ) -> List[Dict]:
        """
        Generate energy optimization recommendations based on energy and occupancy data
        
        Args:
            df: Current data to analyze (includes both energy and occupancy telemetry)
            threshold_high: High energy threshold (Watts)
            threshold_low: Low energy threshold (Watts)
            
        Returns:
            List of recommendation dictionaries with detailed information
        """
        if df.empty:
            return []
        
        # Feature engineering
        if 'energy_watts' not in df.columns or 'hour' not in df.columns:
            df = self.feature_engineer.create_all_features(df)
        
        # Predict energy consumption
        predictions = self.predict(df)
        df['predicted_energy'] = predictions
        
        recommendations = []
        
        # Latest reading
        latest = df.iloc[-1] if len(df) > 0 else None
        if latest is None:
            return recommendations
        
        # Analyze recent data for patterns (last 10 readings)
        recent_df = df.tail(10) if len(df) >= 10 else df
        avg_energy = recent_df['energy_watts'].mean() if 'energy_watts' in recent_df.columns else 0
        avg_temp = recent_df['temperature'].mean() if 'temperature' in recent_df.columns else None
        avg_humidity = recent_df['humidity'].mean() if 'humidity' in recent_df.columns else None
        occupancy_rate = recent_df['is_occupied'].mean() if 'is_occupied' in recent_df.columns else 0
        
        # Get location and module info
        location = latest.get('location', 'Unknown')
        module = latest.get('module', 'Unknown')
        current_energy = latest.get('energy_watts', 0)
        current_temp = latest.get('temperature', None)
        current_humidity = latest.get('humidity', None)
        is_occupied = latest.get('is_occupied', 0)
        rcwl = latest.get('rcwl', None)
        pir = latest.get('pir', None)
        
        # Calculate vacancy duration (how many recent readings were vacant)
        if 'is_occupied' in recent_df.columns:
            vacant_count = (recent_df['is_occupied'] == 0).sum()
            occupied_count = (recent_df['is_occupied'] == 1).sum()
        else:
            vacant_count = 0
            occupied_count = 0
        
        # Recommendation 1: High energy consumption when vacant
        if is_occupied == 0 and current_energy > threshold_high:
            vacancy_hours = vacant_count * 0.5  # Assuming readings every 30 minutes
            recommendations.append({
                'type': 'high_priority',
                'title': 'Turn off unused devices',
                'message': f'Room is vacant but consuming {current_energy:.2f}W. Turn off AC and other devices to save energy.',
                'estimated_savings': current_energy * 24 / 1000,  # kWh per day
                'severity': 'high',
                'location': location,
                'module': module,
                'current_energy_watts': current_energy,
                'current_temperature': current_temp,
                'current_humidity': current_humidity,
                'is_occupied': bool(is_occupied),
                'vacancy_duration_minutes': int(vacancy_hours * 60),
                'rcwl': rcwl,
                'pir': pir,
            })
        
        # Recommendation 2: Optimize AC temperature when occupied
        if current_temp is not None and current_temp > 30 and is_occupied == 1:
            if current_energy > threshold_high * 0.7:
                recommendations.append({
                    'type': 'medium_priority',
                    'title': 'Optimize AC temperature',
                    'message': f'Temperature is {current_temp:.1f}°C while occupied. Consider setting AC to 24-27°C for better efficiency.',
                    'estimated_savings': current_energy * 0.2 * 24 / 1000,  # 20% savings
                    'severity': 'medium',
                    'location': location,
                    'module': module,
                    'current_energy_watts': current_energy,
                    'current_temperature': current_temp,
                    'current_humidity': current_humidity,
                    'is_occupied': bool(is_occupied),
                    'rcwl': rcwl,
                    'pir': pir,
                })
        
        # Recommendation 3: High humidity with high energy
        if current_humidity is not None and current_humidity > 70 and current_energy > threshold_high * 0.8:
            recommendations.append({
                'type': 'medium_priority',
                'title': 'Optimize humidity control',
                'message': f'High humidity ({current_humidity:.0f}%) detected with high energy consumption. Consider adjusting AC settings or using dehumidifier.',
                'estimated_savings': current_energy * 0.15 * 24 / 1000,  # 15% savings
                'severity': 'medium',
                'location': location,
                'module': module,
                'current_energy_watts': current_energy,
                'current_temperature': current_temp,
                'current_humidity': current_humidity,
                'is_occupied': bool(is_occupied),
                'rcwl': rcwl,
                'pir': pir,
            })
        
        # Recommendation 4: Motion sensor mismatch (RCWL vs PIR)
        if rcwl is not None and pir is not None:
            if rcwl == 1 and pir == 0:
                # Check how often this mismatch occurs in recent readings
                mismatch_count = 0
                if 'rcwl' in recent_df.columns and 'pir' in recent_df.columns:
                    mismatch_count = ((recent_df['rcwl'] == 1) & (recent_df['pir'] == 0)).sum()
                
                if mismatch_count >= 3:  # If it happens frequently
                    recommendations.append({
                        'type': 'low_priority',
                        'title': 'Motion sensor alignment',
                        'message': f'RCWL detected motion while PIR didn\'t in {mismatch_count} recent readings. Consider repositioning sensors for better accuracy.',
                        'estimated_savings': 0,
                        'severity': 'low',
                        'location': location,
                        'module': module,
                        'current_energy_watts': current_energy,
                        'current_temperature': current_temp,
                        'current_humidity': current_humidity,
                        'is_occupied': bool(is_occupied),
                        'vacancy_duration_minutes': int(vacant_count * 30) if is_occupied == 0 else None,
                        'rcwl': rcwl,
                        'pir': pir,
                    })
        
        # Recommendation 5: Extended vacancy with energy consumption
        if is_occupied == 0 and vacant_count >= 6:  # Vacant for at least 3 hours (assuming 30min intervals)
            if current_energy > threshold_low:
                recommendations.append({
                    'type': 'high_priority',
                    'title': 'Extended vacancy detected',
                    'message': f'Room has been vacant for extended period ({int(vacant_count * 0.5)} hours) but still consuming {current_energy:.2f}W. Consider automated shutoff.',
                    'estimated_savings': current_energy * 24 / 1000,  # kWh per day
                    'severity': 'high',
                    'location': location,
                    'module': module,
                    'current_energy_watts': current_energy,
                    'current_temperature': current_temp,
                    'current_humidity': current_humidity,
                    'is_occupied': bool(is_occupied),
                    'vacancy_duration_minutes': int(vacant_count * 30),
                    'rcwl': rcwl,
                    'pir': pir,
                })
        
        # Recommendation 6: Low energy prediction - good efficiency
        if latest.get('predicted_energy', 0) < threshold_low and current_energy < threshold_low:
            recommendations.append({
                'type': 'info',
                'title': 'Energy efficiency is good',
                'message': f'Current energy consumption ({current_energy:.2f}W) is within optimal range. Keep monitoring for best practices.',
                'estimated_savings': 0,
                'severity': 'low',
                'location': location,
                'module': module,
                'current_energy_watts': current_energy,
                'current_temperature': current_temp,
                'current_humidity': current_humidity,
                'is_occupied': bool(is_occupied),
                'rcwl': rcwl,
                'pir': pir,
            })
        
        return recommendations

