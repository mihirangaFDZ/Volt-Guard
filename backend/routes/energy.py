from fastapi import APIRouter, Depends
from database import energy_col
from app.models.energy_model import EnergyReading
from utils.jwt_handler import get_current_user

router = APIRouter(
    prefix="/energy",
    tags=["Energy"],
    dependencies=[Depends(get_current_user)],
)

@router.post("/")
def add_energy(data: EnergyReading):
    energy_col.insert_one(data.dict())
    return {"message": "Energy data stored"}

@router.get("/latest")
def get_latest_energy():
    data = list(energy_col.find({}, {"_id": 0}).sort("timestamp", -1).limit(10))
    return list(data)
