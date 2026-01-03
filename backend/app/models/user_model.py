from datetime import datetime
from pydantic import BaseModel
from typing import Optional

class User(BaseModel):
    user_id: str
    name: str
    email: str
    role: str
    created_at: datetime
    password: str  
    
class loginReq(BaseModel):
    email: str
    password: str


class UpdateUserReq(BaseModel):
    name: Optional[str] = None
    email: Optional[str] = None
