"""
Occupancy telemetry analysis recommendation model for the Environment section.
Trains on occupancy_telemetry_recommendations_dataset.csv (1500 rows) and returns
actionable environment recommendations from temperature, humidity, rcwl, pir, rssi.
"""

import pandas as pd
import numpy as np
from pathlib import Path
from typing import Optional, List, Dict, Any
import pickle
import warnings

warnings.filterwarnings("ignore")

try:
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.preprocessing import StandardScaler
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, classification_report
except ImportError:
    RandomForestClassifier = None
    StandardScaler = None
    train_test_split = None
    accuracy_score = None
    classification_report = None

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
DATASET_PATH = BACKEND_DIR / "data" / "occupancy_telemetry_recommendations_dataset.csv"
MODELS_DIR = BACKEND_DIR / "models"
MODEL_PATH = MODELS_DIR / "occupancy_telemetry_rec_classifier.pkl"
SCALER_PATH = MODELS_DIR / "occupancy_telemetry_rec_scaler.pkl"
ENCODERS_PATH = MODELS_DIR / "occupancy_telemetry_rec_encoders.pkl"

FEATURE_COLUMNS = ["rcwl", "pir", "rssi", "temperature", "humidity"]

# User-facing text for each environment recommendation type
RECOMMENDATION_TEMPLATES = {
    "turn_off_ac_vacant": {
        "title": "Turn off AC in vacant room",
        "message": "Room has been vacant with temperature at {temperature:.1f}°C. Turning off AC can save energy.",
        "severity": "high",
        "advice": "Use smart AC scheduling or motion-based automation to turn off cooling when the room is unoccupied.",
        "mitigation": "Set AC to eco/sleep when leaving, or use a timer. Check again after 30 minutes.",
    },
    "align_motion_sensing": {
        "title": "Align motion sensing",
        "message": "RCWL detected motion while PIR did not in recent readings. Sensor may need repositioning.",
        "severity": "medium",
        "advice": "Ensure both sensors have a clear view of the same area. Avoid placing near fans or windows with moving curtains.",
        "mitigation": "Reposition the sensor unit to reduce false motion and improve occupancy detection.",
    },
    "check_link_quality": {
        "title": "Check link quality",
        "message": "RSSI is {rssi} dBm — signal is weak or fair. Readings may be delayed or missing.",
        "severity": "medium",
        "advice": "Keep the sensor within range of the gateway. Avoid thick walls or metal between device and gateway.",
        "mitigation": "Move the sensor closer to the gateway or add a repeater for reliable telemetry.",
    },
    "weak_signal_env": {
        "title": "Weak sensor signal",
        "message": "Very weak RSSI ({rssi} dBm). Environment data may be incomplete.",
        "severity": "medium",
        "advice": "Improve wireless link to avoid gaps in temperature and occupancy data.",
        "mitigation": "Relocate sensor or gateway to strengthen the connection.",
    },
    "comfort_guardrails": {
        "title": "Comfort guardrails",
        "message": "Current conditions {temperature:.1f}°C / {humidity:.0f}% RH are in the comfort band (24–27°C when occupied).",
        "severity": "low",
        "advice": "Keep 24–27°C when occupied; allow 29–30°C when vacant to save energy.",
        "mitigation": "No action needed. Keep monitoring to maintain comfort and efficiency.",
    },
    "review_comfort_drift": {
        "title": "Review comfort drift",
        "message": "Current reading {temperature:.1f}°C / {humidity:.0f}% RH. Review if trend drifts from your target.",
        "severity": "low",
        "advice": "Compare with your usual comfort range and adjust HVAC if needed.",
        "mitigation": "Check thermostat settings and occupancy patterns over the day.",
    },
    "high_humidity_risk": {
        "title": "High humidity — mold and comfort risk",
        "message": "Humidity is {humidity:.0f}% at {temperature:.1f}°C. High humidity can cause mold and discomfort.",
        "severity": "high",
        "advice": "Use dehumidification or improve ventilation. Keep humidity below 60–65% where possible.",
        "mitigation": "Run exhaust fans, open windows when outside is drier, or use a dehumidifier.",
    },
    "low_humidity": {
        "title": "Low humidity — dry air",
        "message": "Humidity is {humidity:.0f}%. Dry air can cause discomfort and static.",
        "severity": "low",
        "advice": "Consider a humidifier or ventilation from a more humid zone.",
        "mitigation": "Increase humidity to 40–50% for comfort if needed.",
    },
    "high_temp_occupied": {
        "title": "Room too warm while occupied",
        "message": "Temperature is {temperature:.1f}°C and room is occupied. Cooling may improve comfort.",
        "severity": "medium",
        "advice": "Lower AC setpoint or improve airflow. Target 24–27°C for comfort.",
        "mitigation": "Adjust AC or fans and recheck after 15–20 minutes.",
    },
    "low_temp_occupied": {
        "title": "Room too cool while occupied",
        "message": "Temperature is {temperature:.1f}°C and room is occupied. Slight heating or less cooling may help.",
        "severity": "low",
        "advice": "Raise AC setpoint or reduce cooling to avoid overcooling.",
        "mitigation": "Set temperature to 24–26°C and avoid excessive cooling.",
    },
    "comfort_ok": {
        "title": "Comfort conditions OK",
        "message": "Environment is {temperature:.1f}°C / {humidity:.0f}% RH — within a comfortable range.",
        "severity": "low",
        "advice": "Continue current settings. Turn off or reduce HVAC when the room is vacant.",
        "mitigation": "No action needed. Keep monitoring for changes.",
    },
}


class OccupancyTelemetryRecommendationModel:
    """Train and predict environment recommendations from occupancy telemetry features."""

    def __init__(self):
        self.classifier = None
        self.scaler = StandardScaler() if StandardScaler else None
        self.feature_columns = FEATURE_COLUMNS

    def _load_dataset(self) -> pd.DataFrame:
        if not DATASET_PATH.exists():
            raise FileNotFoundError(f"Dataset not found: {DATASET_PATH}")
        return pd.read_csv(DATASET_PATH)

    def _prepare_features(self, df: pd.DataFrame) -> np.ndarray:
        df = df.copy()
        for col in FEATURE_COLUMNS:
            if col not in df.columns:
                raise ValueError(f"Missing column: {col}")
        X = df[FEATURE_COLUMNS].fillna({"rssi": -70})
        return X

    def train(self, test_size: float = 0.2, random_state: int = 42) -> Dict[str, Any]:
        """Train classifier on the occupancy telemetry CSV dataset."""
        if RandomForestClassifier is None:
            raise RuntimeError("scikit-learn is required. Install with: pip install scikit-learn")

        df = self._load_dataset()
        X = self._prepare_features(df)
        y = df["recommendation_type"]

        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=random_state
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
        self.classifier.fit(X_train_s, y_train)
        y_pred = self.classifier.predict(X_test_s)
        accuracy = float(accuracy_score(y_test, y_pred))
        report = classification_report(y_test, y_pred, output_dict=True)

        MODELS_DIR.mkdir(parents=True, exist_ok=True)
        with open(MODEL_PATH, "wb") as f:
            pickle.dump(self.classifier, f)
        with open(SCALER_PATH, "wb") as f:
            pickle.dump(self.scaler, f)
        with open(ENCODERS_PATH, "wb") as f:
            pickle.dump({"feature_columns": self.feature_columns}, f)

        return {"accuracy": accuracy, "classification_report": report, "n_samples": len(df)}

    def load_model(self) -> bool:
        """Load trained model from disk. Returns True if loaded."""
        if not MODEL_PATH.exists() or not SCALER_PATH.exists() or not ENCODERS_PATH.exists():
            return False
        try:
            with open(MODEL_PATH, "rb") as f:
                self.classifier = pickle.load(f)
            with open(SCALER_PATH, "rb") as f:
                self.scaler = pickle.load(f)
            with open(ENCODERS_PATH, "rb") as f:
                data = pickle.load(f)
            self.feature_columns = data.get("feature_columns", FEATURE_COLUMNS)
            return True
        except Exception:
            return False

    def predict(
        self,
        temperature: float,
        humidity: float,
        rcwl: int = 0,
        pir: int = 0,
        rssi: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """
        Return list of environment recommendation dicts for the analytics Environment section.
        Each dict: title, message, severity, advice, mitigation.
        """
        if self.classifier is None and not self.load_model():
            return []

        if rssi is None:
            rssi = -70

        X = np.array([[rcwl, pir, rssi, float(temperature), float(humidity)]])
        X_scaled = self.scaler.transform(X)
        rec_type = self.classifier.predict(X_scaled)[0]

        template = RECOMMENDATION_TEMPLATES.get(
            rec_type, RECOMMENDATION_TEMPLATES["comfort_ok"]
        )
        format_kw = {
            "temperature": temperature,
            "humidity": humidity,
            "rssi": rssi,
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
                "recommendation_type": rec_type,
            }
        ]


def train_occupancy_telemetry_model(test_size: float = 0.2) -> Dict[str, Any]:
    """Convenience: train and return metrics."""
    model = OccupancyTelemetryRecommendationModel()
    return model.train(test_size=test_size)
