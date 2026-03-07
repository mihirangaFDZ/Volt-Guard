from datetime import datetime
from pydantic import BaseModel, Field, model_validator
from typing import Optional

class User(BaseModel):
    user_id: str
    name: str
    email: str
    role: str = "user"
    created_at: datetime = Field(default_factory=datetime.utcnow)
    password: str  
    
class loginReq(BaseModel):
    user_id: Optional[str] = None
    email: Optional[str] = None
    password: str

    @model_validator(mode="after")
    def validate_login_identifier(self):
        if not self.user_id and not self.email:
            raise ValueError("Either user_id or email is required")
        return self


class UpdateUserReq(BaseModel):
    name: Optional[str] = None
    email: Optional[str] = None
