#!/usr/bin/env python3
"""
SAM Model Verification Script

Verifies that the downloaded SAM model works correctly
"""

import os
import sys
from pathlib import Path
import torch

def verify_sam_model(model_path: str = "backend/models/sam_vit_l_0b3195.pth"):
    """
    Verify that the SAM model file is valid and can be loaded
    
    Args:
        model_path: Path to the SAM model file
        
    Returns:
        True if model is valid, False otherwise
    """
    print("🎭 SAM Model Verification")
    print("=" * 40)
    
    # Check if file exists
    model_file = Path(model_path)
    if not model_file.exists():
        print(f"❌ Model file not found: {model_path}")
        return False
    
    # Check file size
    file_size_mb = model_file.stat().st_size / (1024 * 1024)
    print(f"📁 Model file: {model_path}")
    print(f"📏 File size: {file_size_mb:.1f} MB")
    
    # Verify file is not empty and has reasonable size
    if file_size_mb < 100:
        print(f"❌ File too small ({file_size_mb:.1f} MB) - likely corrupted")
        return False
    
    if file_size_mb > 3000:
        print(f"⚠️ File very large ({file_size_mb:.1f} MB) - might be wrong model")
    
    # Try to load the model
    try:
        print("🔄 Testing model loading...")
        
        # Check if segment-anything is available
        try:
            from segment_anything import sam_model_registry
            print("✅ segment-anything package available")
        except ImportError:
            print("❌ segment-anything package not installed")
            print("Install with: pip install segment-anything")
            return False
        
        # Try to load the model
        try:
            # Determine model type from filename
            if "vit_h" in model_path:
                model_type = "vit_h"
            elif "vit_l" in model_path:
                model_type = "vit_l" 
            elif "vit_b" in model_path:
                model_type = "vit_b"
            else:
                print("⚠️ Could not determine model type from filename")
                model_type = "vit_l"  # Default
            
            print(f"🤖 Loading as {model_type.upper()} model...")
            
            # Load model (this will fail if file is corrupted)
            sam = sam_model_registry[model_type](checkpoint=model_path)
            print("✅ Model loaded successfully!")
            
            # Test basic functionality
            device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            sam.to(device=device)
            print(f"✅ Model moved to device: {device}")
            
            # Get model info
            total_params = sum(p.numel() for p in sam.parameters())
            print(f"📊 Model parameters: {total_params:,}")
            
            print()
            print("🎉 SAM model verification PASSED!")
            print("Your model is ready to use for room segmentation.")
            
            return True
            
        except Exception as e:
            print(f"❌ Failed to load model: {e}")
            print()
            print("This could mean:")
            print("1. The download was corrupted")
            print("2. Wrong model type selected")
            print("3. Incompatible segment-anything version")
            return False
            
    except Exception as e:
        print(f"❌ Unexpected error during verification: {e}")
        return False

def main():
    """Main function"""
    print("🔍 Checking for SAM models...")
    
    # Look for SAM models in common locations
    possible_models = [
        "backend/models/sam_vit_l_0b3195.pth",
        "backend/models/sam_vit_h_4b8939.pth", 
        "backend/models/sam_vit_b_01ec64.pth",
        "sam_vit_l_0b3195.pth",
        "sam_vit_h_4b8939.pth",
        "sam_vit_b_01ec64.pth"
    ]
    
    found_models = []
    for model_path in possible_models:
        if Path(model_path).exists():
            found_models.append(model_path)
    
    if not found_models:
        print("❌ No SAM models found!")
        print()
        print("Please download a SAM model first:")
        print("python download_sam_model.py")
        return
    
    print(f"✅ Found {len(found_models)} SAM model(s):")
    for model in found_models:
        print(f"  • {model}")
    
    print()
    
    # Verify the first model found
    primary_model = found_models[0]
    print(f"🧪 Verifying primary model: {primary_model}")
    print()
    
    success = verify_sam_model(primary_model)
    
    if success:
        print()
        print("🚀 Ready to test SAM integration!")
        print()
        print("Next steps:")
        print("1. Start your FastAPI server: uvicorn main:app --reload")
        print("2. Check status: curl -X GET 'http://localhost:8000/api/model-status'")
        print("3. Test AI Detect: curl -X POST 'http://localhost:8000/api/analyze-floor-plan-with-sam' -F 'file=@floorplan.jpg'")
    else:
        print()
        print("🔧 Troubleshooting suggestions:")
        print("1. Re-download the model: python download_sam_model.py")
        print("2. Try a different model size (vit_b is smaller)")
        print("3. Check available disk space")
        print("4. Update segment-anything: pip install segment-anything --upgrade")

if __name__ == "__main__":
    main() 