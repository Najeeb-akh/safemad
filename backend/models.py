from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, JSON, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from .database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    full_name = Column(String)
    hashed_password = Column(String)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    homes = relationship("HomeAnalysis", back_populates="owner")

class HomeAnalysis(Base):
    __tablename__ = "home_analyses"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    floor_plan_url = Column(String)
    safety_scores = Column(JSON)
    recommendations = Column(JSON)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    owner = relationship("User", back_populates="homes")
    materials = relationship("MaterialAnalysis", back_populates="home")

class MaterialAnalysis(Base):
    __tablename__ = "material_analyses"

    id = Column(Integer, primary_key=True, index=True)
    home_id = Column(Integer, ForeignKey("home_analyses.id"))
    image_url = Column(String)
    material_type = Column(String)
    confidence_score = Column(Integer)
    wall_thickness = Column(Integer, nullable=True)  # in mm
    created_at = Column(DateTime, default=datetime.utcnow)
    
    home = relationship("HomeAnalysis", back_populates="materials") 