from fastapi import APIRouter, HTTPException
from database import db
from app.models.user_model import loginReq
from utils.security import verify_password
from utils.jwt_handler import create_access_token

router = APIRouter(prefix="/auth", tags=["Authentication"])

@router.post("/login")
def login(data: loginReq):
    query = {"user_id": data.user_id} if data.user_id else {"email": data.email}
    user = db.users.find_one(query)

    if not user:
        raise HTTPException(status_code=401, detail="Invalid user ID/email or password")

    if not verify_password(data.password, user["password"]):
        raise HTTPException(status_code=401, detail="Invalid user ID/email or password")

    token = create_access_token({
        "user_id": user["user_id"],
        "role": user["role"]
    })

    return {
        "access_token": token,
        "token_type": "bearer",
        "user_name": user["name"],
        "user_id": user["user_id"],
        "role": user.get("role", "user")
    }
