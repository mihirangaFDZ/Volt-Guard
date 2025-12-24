from pydantic import BaseModel

class Prediction(BaseModel):
    device_id: str
    predicted_energy_kwh: float
    confidence_score: float
    prediction_type: str
