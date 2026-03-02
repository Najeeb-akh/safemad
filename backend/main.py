from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from typing import List, Optional
import uvicorn
from datetime import timedelta
import logging
import os
from . import auth
from .routers import material_detection
from .routers import floor_plan
from .routers import annotation

from .routers import wall_thickness
from .routers import structured_data
from .routers import structured_safety_router

# Configure logging for debugging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
    ]
)

# Set specific logger levels
logging.getLogger("uvicorn.access").setLevel(logging.INFO)
logging.getLogger("uvicorn.error").setLevel(logging.INFO)

logger = logging.getLogger(__name__)
logger.info("🔍 [MAIN DEBUG] Starting SafeMad API with DEBUG logging enabled")

app = FastAPI(
    title="SafeMad API",
    description="AI-Powered Emergency Shelter Finder API",
    version="1.0.0"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(material_detection.router, prefix="/api", tags=["material"])
app.include_router(floor_plan.router, prefix="/api", tags=["floor_plan"])
app.include_router(annotation.router, prefix="/api", tags=["annotation"])
app.include_router(wall_thickness.router, prefix="/api", tags=["wall_thickness"])

# New structured data system routers
app.include_router(structured_data.router, prefix="/api/structured-data", tags=["structured_data"])
app.include_router(structured_safety_router.router, prefix="/api/structured-safety", tags=["structured_safety"])

# Basic models
class UserBase(BaseModel):
    email: str
    full_name: str

class UserCreate(UserBase):
    password: str

class User(UserBase):
    id: int
    is_active: bool

    class Config:
        from_attributes = True

class HomeAnalysis(BaseModel):
    id: int
    user_id: int
    floor_plan_url: str
    safety_scores: dict
    recommendations: List[str]

# Authentication routes
@app.post("/token", response_model=auth.Token)
# async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
#     user = auth.authenticate_user(form_data.username, form_data.password)
#     if not user:
#         raise HTTPException(
#             status_code=status.HTTP_401_UNAUTHORIZED,
#             detail="Incorrect email or password",
#             headers={"WWW-Authenticate": "Bearer"},
#         )
#     access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
#     access_token = auth.create_access_token(
#         data={"sub": user["email"]}, expires_delta=access_token_expires
#     )
#     return {"access_token": access_token, "token_type": "bearer"}

# Basic routes
@app.get("/")
async def root():
    return {"message": "Welcome to SafeMad API"}

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

# User routes
@app.post("/users/", response_model=User)
async def create_user(user: UserCreate):
    # For dummy auth, just return success
    return {
        "id": 1,
        "email": user.email,
        "full_name": user.full_name,
        "is_active": True
    }

@app.get("/users/me", response_model=User)
async def read_users_me(current_user: dict = Depends(auth.get_current_user)):
    return {
        "id": 1,
        "email": current_user["email"],
        "full_name": current_user["full_name"],
        "is_active": current_user["is_active"]
    }

# Home analysis routes
@app.post("/homes/analyze")
async def analyze_home(current_user: dict = Depends(auth.get_current_user)):
    # TODO: Implement home analysis
    raise HTTPException(status_code=501, detail="Not implemented")

@app.get("/homes/{home_id}/safety-scores")
async def get_safety_scores(home_id: int, current_user: dict = Depends(auth.get_current_user)):
    # TODO: Implement safety scores retrieval
    raise HTTPException(status_code=501, detail="Not implemented")

if __name__ == "__main__":
    # When running as module (python -m backend.main), use full module path
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True) 