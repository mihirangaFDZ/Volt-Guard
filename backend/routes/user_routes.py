from fastapi import APIRouter
from database import user_col
from app.models.user_model import User
from utils.security import hash_password

router = APIRouter(prefix="/users", tags=["Users"])

@router.post("/")
def add_user(data: User):
    user_data = data.dict()

    # hash the password before saving
    user_data["password"] = hash_password(user_data["password"])

    user_col.insert_one(user_data)

    return {"message": "User created successfully"}

@router.get("/")
def get_users():
    data = list(user_col.find({}, {"_id": 0}).limit(10))
    return list(data)

@router.get("/{user_id}")
def get_user(user_id: str):
    return user_col.find_one({"user_id": user_id}, {"_id": 0})
