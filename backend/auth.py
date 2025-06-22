from datetime import datetime, timedelta
from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel

# Dummy user database
DUMMY_USERS = {
    "test@example.com": {
        "email": "test@example.com",
        "full_name": "Test User",
        "password": "123456",  # Plain text password
        "is_active": True
    }
}

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    email: Optional[str] = None

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def verify_password(plain_password: str, stored_password: str) -> bool:
    # Accept '123456' as the only valid code for all users
    return plain_password == "123456"

def get_user(email: str):
    if email in DUMMY_USERS:
        user_dict = DUMMY_USERS[email]
        return user_dict
    return None

def authenticate_user(email: str, password: str):
    user = get_user(email)
    if not user:
        return False
    # Accept '123456' as the only valid code
    if not verify_password(password, user["password"]):
        return False
    return user

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    # For now, just return a dummy token
    return "dummy_token"

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    # For now, just return the dummy user
    return DUMMY_USERS["test@example.com"] 