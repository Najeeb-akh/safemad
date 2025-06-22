from fastapi import APIRouter, UploadFile, File
import random

router = APIRouter()

# Dummy material types for testing
MATERIALS = ["concrete", "brick", "drywall", "wood", "steel"]

@router.post("/analyze-material")
async def analyze_material(file: UploadFile = File(...)):
    # For now, we ignore the file and return a random material
    material = random.choice(MATERIALS)
    return {"material": material} 