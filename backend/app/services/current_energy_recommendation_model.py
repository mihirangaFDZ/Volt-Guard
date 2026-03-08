"""
Current energy analysis recommendation model.
Trains on the CSV dataset (current_energy_recommendations_dataset.csv) and
returns accurate, user-understandable recommendations for the analytics page.
"""

import pandas as pd
import numpy as np
from pathlib import Path
from typing import Optional, List, Dict, Any
import pickle
import warnings

warnings.filterwarnings("ignore")

try:
    from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
    from sklearn.preprocessing import LabelEncoder, StandardScaler
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, classification_report
except ImportError:
    RandomForestClassifier = None
    RandomForestRegressor = None
    LabelEncoder = None
    StandardScaler = None
    train_test_split = None
    accuracy_score = None
    classification_report = None

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
DATASET_PATH = BACKEND_DIR / "data" / "current_energy_recommendations_dataset.csv"
MODELS_DIR = BACKEND_DIR / "models"
MODEL_PATH = MODELS_DIR / "current_energy_rec_classifier.pkl"
SCALER_PATH = MODELS_DIR / "current_energy_rec_scaler.pkl"
ENCODERS_PATH = MODELS_DIR / "current_energy_rec_encoders.pkl"

# User-facing text for each recommendation type (for accurate, consistent recommendations)
RECOMMENDATION_TEMPLATES = {
    "high_load": {
        "title": "High power use — devices may be overloaded",
        "message": "Your circuit is drawing {current_a:.2f} A ({power_w:.0f} W). This can overload wiring and increase bills.",
        "severity": "high",
        "advice": "Use devices one at a time where possible. Switch off AC, heaters, or heavy appliances when not needed. Do not plug too many high-wattage devices on the same circuit.",
        "mitigation": "Unplug unused appliances, turn off AC when leaving the room, and use power strips to switch off standby devices. Retake a reading after 30 minutes to see the drop.",
    },
    "moderate_load": {
        "title": "Moderate load — room for improvement",
        "message": "Current draw is {current_a:.2f} A ({power_w:.0f} W). You can save energy by turning off devices you are not using.",
        "severity": "medium",
        "advice": "Turn off lights and fans when leaving the room. Unplug chargers and set-top boxes when not in use. Use sleep mode on computers and monitors.",
        "mitigation": "Identify which appliance uses the most (e.g. AC, heater) and reduce its usage or set a timer. Check the reading again after making changes.",
    },
    "rising_consumption": {
        "title": "Consumption is rising",
        "message": "Usage has gone up by {trend_percent_change:.1f}% recently. This usually means new devices are on or something was left running.",
        "severity": "medium",
        "advice": "Check for devices that were recently turned on or left on (AC, heater, water heater, extra lights). Compare with your usual usage pattern.",
        "mitigation": "Switch off or unplug any device you are not using right now. If the rise continues, list all connected devices and turn them off one by one while watching the reading to find the main consumer.",
    },
    "weak_signal": {
        "title": "Weak WiFi signal",
        "message": "The monitoring device has a weak WiFi signal. Readings may be delayed or missing.",
        "severity": "low",
        "advice": "Keep the energy monitor within range of your router. Avoid thick walls or metal between the device and the router.",
        "mitigation": "Move the device closer to the router or add a WiFi extender. This does not reduce energy use but ensures accurate data.",
    },
    "efficient_usage": {
        "title": "Efficient usage",
        "message": "Current consumption ({power_w:.0f} W) is in a good range. Keep up the good habits.",
        "severity": "low",
        "advice": "Continue turning off devices when not in use and using efficient settings on AC and appliances.",
        "mitigation": "No action needed. Keep monitoring to catch any sudden increases.",
    },
}


class CurrentEnergyRecommendationModel:
    """Train and predict current energy recommendations from the CSV dataset."""

    def __init__(self):
        self.classifier = None
        self.scaler = StandardScaler() if StandardScaler else None
        self.enc_trend = LabelEncoder() if LabelEncoder else None
        self.enc_signal = LabelEncoder() if LabelEncoder else None
        self.feature_columns = None
        self.savings_regressor = None
        self.wasted_regressor = None

    def _load_dataset(self) -> pd.DataFrame:
        if not DATASET_PATH.exists():
            raise FileNotFoundError(f"Dataset not found: {DATASET_PATH}")
        return pd.read_csv(DATASET_PATH)

    def _prepare_features(self, df: pd.DataFrame) -> tuple:
        df = df.copy()
        df["trend_direction_enc"] = self.enc_trend.transform(
            df["trend_direction"].astype(str)
        )
        df["signal_quality_enc"] = self.enc_signal.transform(
            df["signal_quality"].astype(str)
        )
        feature_cols = [
            "current_a",
            "current_ma",
            "power_w",
            "trend_direction_enc",
            "trend_percent_change",
            "signal_quality_enc",
        ]
        X = df[feature_cols]
        return X, feature_cols

    def train(self, test_size: float = 0.2, random_state: int = 42) -> Dict[str, Any]:
        """Train classifier (and optional regressors) on the CSV dataset."""
        if RandomForestClassifier is None:
            raise RuntimeError("scikit-learn is required. Install with: pip install scikit-learn")

        df = self._load_dataset()
        # Encode categoricals
        self.enc_trend.fit(df["trend_direction"].astype(str).unique())
        self.enc_signal.fit(df["signal_quality"].astype(str).unique())

        X, self.feature_columns = self._prepare_features(df)
        y_type = df["recommendation_type"]
        y_savings = df["estimated_savings_kwh_per_day"]
        y_wasted = df["energy_wasted_kwh_per_day"]

        X_train, X_test, yt_train, yt_test, ys_train, ys_test, yw_train, yw_test = train_test_split(
            X, y_type, y_savings, y_wasted, test_size=test_size, random_state=random_state
        )

        self.scaler.fit(X_train)
        X_train_s = self.scaler.transform(X_train)
        X_test_s = self.scaler.transform(X_test)

        self.classifier = RandomForestClassifier(
            n_estimators=100,
            max_depth=12,
            min_samples_split=5,
            random_state=random_state,
        )
        self.classifier.fit(X_train_s, yt_train)
        y_pred = self.classifier.predict(X_test_s)
        accuracy = accuracy_score(yt_test, y_pred)

        self.savings_regressor = RandomForestRegressor(
            n_estimators=50, max_depth=8, random_state=random_state
        )
        self.wasted_regressor = RandomForestRegressor(
            n_estimators=50, max_depth=8, random_state=random_state
        )
        self.savings_regressor.fit(X_train_s, ys_train)
        self.wasted_regressor.fit(X_train_s, yw_train)

        report = classification_report(yt_test, y_pred, output_dict=True)
        MODELS_DIR.mkdir(parents=True, exist_ok=True)
        with open(MODEL_PATH, "wb") as f:
            pickle.dump(
                {
                    "classifier": self.classifier,
                    "savings_regressor": self.savings_regressor,
                    "wasted_regressor": self.wasted_regressor,
                },
                f,
            )
        with open(SCALER_PATH, "wb") as f:
            pickle.dump(self.scaler, f)
        with open(ENCODERS_PATH, "wb") as f:
            pickle.dump(
                {"trend": self.enc_trend, "signal": self.enc_signal, "feature_columns": self.feature_columns},
                f,
            )
        return {
            "accuracy": float(accuracy),
            "classification_report": report,
            "n_samples": len(df),
        }

    def load_model(self) -> bool:
        """Load trained model from disk. Returns True if loaded."""
        if not MODEL_PATH.exists() or not SCALER_PATH.exists() or not ENCODERS_PATH.exists():
            return False
        try:
            with open(MODEL_PATH, "rb") as f:
                data = pickle.load(f)
            self.classifier = data["classifier"]
            self.savings_regressor = data.get("savings_regressor")
            self.wasted_regressor = data.get("wasted_regressor")
            with open(SCALER_PATH, "rb") as f:
                self.scaler = pickle.load(f)
            with open(ENCODERS_PATH, "rb") as f:
                enc_data = pickle.load(f)
            self.enc_trend = enc_data["trend"]
            self.enc_signal = enc_data["signal"]
            self.feature_columns = enc_data["feature_columns"]
            return True
        except Exception:
            return False

    def predict(
        self,
        current_a: float,
        current_ma: Optional[float] = None,
        power_w: Optional[float] = None,
        trend_direction: str = "stable",
        trend_percent_change: float = 0.0,
        signal_quality: str = "unknown",
    ) -> List[Dict[str, Any]]:
        """
        Return list of recommendation dicts for the analytics page.
        Each dict: title, message, severity, advice, mitigation,
        estimated_savings_kwh_per_day, energy_wasted_kwh_per_day.
        """
        if self.classifier is None and not self.load_model():
            return []

        if power_w is None:
            power_w = current_a * 230.0
        if current_ma is None:
            current_ma = current_a * 1000.0

        # Encode categoricals (handle unseen labels)
        try:
            trend_enc = self.enc_trend.transform([str(trend_direction).lower()])[0]
        except ValueError:
            trend_enc = 0
        try:
            signal_enc = self.enc_signal.transform([str(signal_quality).lower()])[0]
        except ValueError:
            signal_enc = self.enc_signal.transform(["strong"])[0]

        X = np.array(
            [[current_a, current_ma, power_w, trend_enc, trend_percent_change, signal_enc]]
        )
        X_scaled = self.scaler.transform(X)
        rec_type = self.classifier.predict(X_scaled)[0]
        savings = float(self.savings_regressor.predict(X_scaled)[0]) if self.savings_regressor is not None else 0.0
        wasted = float(self.wasted_regressor.predict(X_scaled)[0]) if self.wasted_regressor is not None else 0.0

        # Clamp to non-negative
        savings = max(0.0, savings)
        wasted = max(0.0, wasted)

        template = RECOMMENDATION_TEMPLATES.get(
            rec_type, RECOMMENDATION_TEMPLATES["efficient_usage"]
        )
        format_kw = {
            "current_a": current_a,
            "power_w": power_w,
            "trend_percent_change": trend_percent_change,
        }
        title = template["title"]
        try:
            message = template["message"].format(**format_kw)
        except KeyError:
            message = template["message"]
        return [
            {
                "title": title,
                "message": message,
                "severity": template["severity"],
                "advice": template["advice"],
                "mitigation": template["mitigation"],
                "estimated_savings_kwh_per_day": round(savings, 4),
                "energy_wasted_kwh_per_day": round(wasted, 4),
                "recommendation_type": rec_type,
            }
        ]


def train_current_energy_model(test_size: float = 0.2) -> Dict[str, Any]:
    """Convenience: train and return metrics."""
    model = CurrentEnergyRecommendationModel()
    return model.train(test_size=test_size)
