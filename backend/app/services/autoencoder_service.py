# backend/app/services/autoencoder_service.py
"""
Autoencoder Model for Anomaly Detection in Energy Consumption

An Autoencoder is a neural network that learns to compress (encode) and
reconstruct (decode) normal energy patterns. When it encounters abnormal
data, the reconstruction error is high — indicating an anomaly.

How it works:
1. Encoder compresses input features into a smaller latent representation
2. Decoder reconstructs the original features from the latent representation
3. The model is trained only on normal data, so it learns "what normal looks like"
4. For new data: low reconstruction error = normal, high error = anomaly
"""
import pandas as pd
import numpy as np
from tensorflow.keras.models import Model, load_model
from tensorflow.keras.layers import Input, Dense, Dropout
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import precision_score, recall_score, f1_score
import pickle
from pathlib import Path
from typing import List, Tuple
import warnings
warnings.filterwarnings('ignore')


class AutoencoderAnomalyDetector:
    """
    Autoencoder-based anomaly detection for energy consumption data.

    The model learns to reconstruct normal energy consumption patterns.
    Data points with high reconstruction error are flagged as anomalies.
    """

    def __init__(self, model_dir='models'):
        self.model_dir = Path(model_dir)
        self.model_dir.mkdir(parents=True, exist_ok=True)

        self.model = None
        self.scaler = StandardScaler()
        self.is_trained = False
        self.feature_columns = []
        self.threshold = None  # Reconstruction error threshold for anomaly

    def _build_model(self, input_dim: int) -> Model:
        """
        Build the Autoencoder architecture.

        Architecture:
            Input (N features)
            -> Encoder: Dense(32) -> Dense(16) -> Dense(8) [bottleneck]
            -> Decoder: Dense(16) -> Dense(32) -> Dense(N) [reconstruction]

        The bottleneck layer (8 units) forces the network to learn a
        compressed representation of normal patterns.
        """
        input_layer = Input(shape=(input_dim,))

        # Encoder — progressively compresses the data
        encoded = Dense(32, activation='relu')(input_layer)
        encoded = Dropout(0.2)(encoded)
        encoded = Dense(16, activation='relu')(encoded)
        encoded = Dense(8, activation='relu')(encoded)  # Bottleneck

        # Decoder — reconstructs from compressed representation
        decoded = Dense(16, activation='relu')(encoded)
        decoded = Dropout(0.2)(decoded)
        decoded = Dense(32, activation='relu')(decoded)
        decoded = Dense(input_dim, activation='linear')(decoded)  # Reconstruct original

        autoencoder = Model(inputs=input_layer, outputs=decoded)
        autoencoder.compile(optimizer='adam', loss='mse', metrics=['mae'])

        return autoencoder

    def train(self, df: pd.DataFrame, feature_cols: List[str],
              contamination: float = 0.1, epochs: int = 100, batch_size: int = 32):
        """
        Train the Autoencoder on energy consumption data.

        Strategy:
        1. Use all data for training (unsupervised — no labels needed)
        2. After training, compute reconstruction error on training data
        3. Set threshold at the (1 - contamination) percentile of errors
           so that ~contamination fraction of training data is flagged

        Args:
            df: DataFrame with energy features
            feature_cols: Columns to use as input features
            contamination: Expected fraction of anomalies (default 0.1 = 10%)
            epochs: Training epochs
            batch_size: Batch size for training
        """
        print(f"\n{'='*60}")
        print("Training Autoencoder Anomaly Detection Model")
        print(f"{'='*60}")

        self.feature_columns = feature_cols

        # Prepare data
        X = df[feature_cols].fillna(0).values
        X_scaled = self.scaler.fit_transform(X)

        print(f"Training on {len(X_scaled)} samples with {len(feature_cols)} features")

        # Split for validation (80/20)
        split_idx = int(len(X_scaled) * 0.8)
        X_train = X_scaled[:split_idx]
        X_val = X_scaled[split_idx:]

        print(f"Training samples: {len(X_train)}, Validation samples: {len(X_val)}")

        # Build model
        self.model = self._build_model(input_dim=len(feature_cols))

        print("\nAutoencoder Architecture:")
        self.model.summary()

        # Callbacks
        early_stop = EarlyStopping(
            monitor='val_loss',
            patience=10,
            restore_best_weights=True
        )

        checkpoint = ModelCheckpoint(
            str(self.model_dir / 'autoencoder_best_model.h5'),
            monitor='val_loss',
            save_best_only=True,
            verbose=1
        )

        # Train — the model learns to reconstruct its own input
        print(f"\nTraining for up to {epochs} epochs...")
        history = self.model.fit(
            X_train, X_train,  # Input = Target (reconstruction)
            validation_data=(X_val, X_val),
            epochs=epochs,
            batch_size=batch_size,
            callbacks=[early_stop, checkpoint],
            verbose=1
        )

        # Compute reconstruction errors on full training data
        reconstructions = self.model.predict(X_scaled, verbose=0)
        mse_errors = np.mean(np.square(X_scaled - reconstructions), axis=1)

        # Set threshold: top (contamination * 100)% of errors are anomalies
        self.threshold = float(np.percentile(mse_errors, (1 - contamination) * 100))

        print(f"\n{'='*60}")
        print("Autoencoder Training Results:")
        print(f"{'='*60}")
        print(f"Reconstruction error threshold: {self.threshold:.6f}")
        print(f"Mean reconstruction error: {np.mean(mse_errors):.6f}")
        print(f"Max reconstruction error: {np.max(mse_errors):.6f}")
        print(f"Anomalies in training data: {np.sum(mse_errors > self.threshold)} / {len(mse_errors)}")
        print(f"{'='*60}\n")

        # Save model
        self.save_model()
        self.is_trained = True

        return history

    def detect_anomalies(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Detect anomalies in new data using reconstruction error.

        For each data point:
        1. Pass through the autoencoder
        2. Measure how well it was reconstructed (MSE)
        3. If reconstruction error > threshold, it's an anomaly

        Returns DataFrame with added columns:
        - is_anomaly_ae: 1 if anomaly, 0 if normal
        - anomaly_score_ae: normalized reconstruction error (0 to 1)
        - reconstruction_error: raw MSE
        """
        if not self.is_trained or self.model is None:
            self.load_model()

        if not self.is_trained:
            raise ValueError("Model not trained. Call train() first.")

        # Ensure all feature columns exist
        missing_cols = set(self.feature_columns) - set(df.columns)
        if missing_cols:
            for col in missing_cols:
                df[col] = 0

        X = df[self.feature_columns].fillna(0).values
        X_scaled = self.scaler.transform(X)

        # Get reconstruction and compute error
        reconstructions = self.model.predict(X_scaled, verbose=0)
        mse_errors = np.mean(np.square(X_scaled - reconstructions), axis=1)

        # Classify as anomaly
        df['is_anomaly_ae'] = (mse_errors > self.threshold).astype(int)
        df['reconstruction_error'] = mse_errors

        # Normalize score to 0-1 range for comparability with Isolation Forest
        max_error = max(mse_errors.max(), self.threshold * 2)
        df['anomaly_score_ae'] = np.clip(mse_errors / max_error, 0, 1)

        return df

    def save_model(self):
        """Save trained autoencoder and metadata"""
        model_path = self.model_dir / 'autoencoder_model.h5'
        if self.model:
            self.model.save(model_path)
            print(f"Saved Autoencoder model to {model_path}")

        meta_path = self.model_dir / 'autoencoder_meta.pkl'
        with open(meta_path, 'wb') as f:
            pickle.dump({
                'scaler': self.scaler,
                'feature_columns': self.feature_columns,
                'threshold': self.threshold
            }, f)
        print(f"Saved Autoencoder metadata to {meta_path}")

    def load_model(self) -> bool:
        """Load trained autoencoder and metadata"""
        model_path = self.model_dir / 'autoencoder_model.h5'
        meta_path = self.model_dir / 'autoencoder_meta.pkl'

        if model_path.exists() and meta_path.exists():
            self.model = load_model(model_path)

            with open(meta_path, 'rb') as f:
                data = pickle.load(f)
                self.scaler = data['scaler']
                self.feature_columns = data['feature_columns']
                self.threshold = data['threshold']

            self.is_trained = True
            print(f"Loaded Autoencoder model from {model_path}")
            return True

        return False
