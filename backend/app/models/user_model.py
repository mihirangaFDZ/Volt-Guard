from datetime import datetime
from pydantic import BaseModel

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
