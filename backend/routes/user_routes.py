from fastapi import APIRouter, Depends, HTTPException
from database import user_col
from app.models.user_model import UpdateUserReq, User
from utils.security import hash_password
from utils.jwt_handler import get_current_user

router = APIRouter(prefix="/users", tags=["Users"])


def _sanitize_user(doc: dict | None):
    if not doc:
        return None
    doc.pop("_id", None)
    doc.pop("password", None)
    return doc

@router.post("/signup")
def add_user(data: User):
    existing_user = user_col.find_one({"email": data.email})
    if existing_user:
        return {"message": "Email already registered",
                "success": False,
                "statusCode": 400
                }


    user_data = data.dict()
    user_data["password"] = hash_password(user_data["password"])

    user_col.insert_one(user_data)

    return {"message": "User created successfully"}

@router.get("/")
def get_users():
    data = list(user_col.find({}, {"_id": 0}).limit(10))
    return list(data)

@router.get("/{user_id}")
def get_user(user_id: str, current_user=Depends(get_current_user)):
    # Only allow the user themselves or an admin
    if current_user.get("role") != "admin" and current_user.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    user = user_col.find_one({"user_id": user_id})
    user = _sanitize_user(user)

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return user


@router.put("/{user_id}")
def update_user(user_id: str, payload: UpdateUserReq, current_user=Depends(get_current_user)):
    if current_user.get("role") != "admin" and current_user.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    update = {k: v for k, v in payload.dict().items() if v is not None}
    if not update:
        raise HTTPException(status_code=400, detail="No fields to update")

    # Prevent email collision
    if "email" in update:
        existing = user_col.find_one({"email": update["email"], "user_id": {"$ne": user_id}})
        if existing:
            raise HTTPException(status_code=400, detail="Email already registered")

    result = user_col.update_one({"user_id": user_id}, {"$set": update})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="User not found")

    user = user_col.find_one({"user_id": user_id})
    user = _sanitize_user(user)
    return {"success": True, "data": user}
