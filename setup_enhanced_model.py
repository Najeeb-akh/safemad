#!/usr/bin/env python3
"""
Setup script for the Enhanced Floor Plan Detection Model

This script helps you set up and test the specialized YOLOv8 floor plan model.
"""

import os
import sys
import subprocess
import requests
import json
from pathlib import Path

def check_dependencies():
    """Check if required dependencies are installed."""
    print("🔍 Checking dependencies...")
    
    try:
        import ultralytics
        print(f"✅ ultralytics version: {ultralytics.__version__}")
        
        if ultralytics.__version__ != "8.2.8":
            print(f"⚠️  Expected ultralytics==8.2.8, found {ultralytics.__version__}")
            print("   Run: pip install ultralytics==8.2.8")
            return False
            
    except ImportError:
        print("❌ ultralytics not found. Run: pip install ultralytics==8.2.8")
        return False
    
    try:
        import torch
        print(f"✅ PyTorch version: {torch.__version__}")
        print(f"✅ CUDA available: {torch.cuda.is_available()}")
    except ImportError:
        print("❌ PyTorch not found. Run: pip install torch torchvision")
        return False
    
    try:
        import cv2
        print(f"✅ OpenCV version: {cv2.__version__}")
    except ImportError:
        print("❌ OpenCV not found. Run: pip install opencv-python")
        return False
    
    return True

def create_models_directory():
    """Create models directory if it doesn't exist."""
    models_dir = Path("models")
    models_dir.mkdir(exist_ok=True)
    print(f"📁 Created/verified models directory: {models_dir.absolute()}")
    return models_dir

def check_model_file(model_path):
    """Check if the model file exists and is valid."""
    model_file = Path(model_path)
    
    if not model_file.exists():
        print(f"❌ Model file not found: {model_file.absolute()}")
        print(f"   Please place your best.pt file at: {model_file.absolute()}")
        return False
    
    file_size = model_file.stat().st_size / (1024 * 1024)  # MB
    print(f"✅ Model file found: {model_file.absolute()} ({file_size:.1f} MB)")
    
    if file_size < 40 or file_size > 60:
        print(f"⚠️  Expected ~50MB model file, found {file_size:.1f}MB")
    
    return True

def test_model_loading(model_path):
    """Test if the model can be loaded successfully."""
    print("🧪 Testing model loading...")
    
    try:
        from ultralytics import YOLO
        model = YOLO(model_path)
        print("✅ Model loaded successfully!")
        
        # Check model classes
        if hasattr(model, 'names'):
            classes = list(model.names.values())
            print(f"✅ Model classes ({len(classes)}): {', '.join(classes)}")
            
            expected_classes = [
                'Column', 'Curtain Wall', 'Dimension', 'Door', 
                'Railing', 'Sliding Door', 'Stair Case', 'Wall', 'Window'
            ]
            
            if len(classes) == 9 and all(cls in classes for cls in expected_classes):
                print("✅ All expected architectural classes found!")
            else:
                print(f"⚠️  Expected 9 architectural classes, found: {classes}")
        
        return True
        
    except Exception as e:
        print(f"❌ Failed to load model: {e}")
        return False

def test_api_connection():
    """Test if the SafeMad API is running."""
    print("🌐 Testing API connection...")
    
    try:
        response = requests.get("http://localhost:8000/api/model-status", timeout=5)
        print(f"✅ API is running (status: {response.status_code})")
        return True
    except requests.exceptions.ConnectionError:
        print("⚠️  API not running. Start with: uvicorn backend.main:app --reload")
        return False
    except Exception as e:
        print(f"❌ API error: {e}")
        return False

def set_model_via_api(model_path):
    """Set the model path via API."""
    print("🚀 Setting model via API...")
    
    try:
        response = requests.post(
            f"http://localhost:8000/api/set-floor-plan-model?model_path={model_path}",
            timeout=10
        )
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Model set successfully: {result.get('message', 'OK')}")
            return True
        else:
            print(f"❌ Failed to set model (status: {response.status_code})")
            print(f"   Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Failed to set model via API: {e}")
        return False

def verify_model_status():
    """Verify the model status via API."""
    print("✅ Verifying model status...")
    
    try:
        response = requests.get("http://localhost:8000/api/model-status", timeout=5)
        
        if response.status_code == 200:
            status = response.json()
            print(f"✅ Model Status:")
            print(f"   Loaded: {status.get('model_loaded', False)}")
            print(f"   Path: {status.get('model_path', 'N/A')}")
            print(f"   Classes: {status.get('num_classes', 'N/A')}")
            return status.get('model_loaded', False)
        else:
            print(f"❌ Failed to get model status (status: {response.status_code})")
            return False
            
    except Exception as e:
        print(f"❌ Failed to get model status: {e}")
        return False

def main():
    """Main setup function."""
    print("🚀 Enhanced Floor Plan Model Setup")
    print("=" * 50)
    
    # Check dependencies
    if not check_dependencies():
        print("\n❌ Setup failed: Missing dependencies")
        sys.exit(1)
    
    # Create models directory
    models_dir = create_models_directory()
    
    # Check for model file
    model_path = models_dir / "best.pt"
    
    if not check_model_file(model_path):
        print("\n📋 Next steps:")
        print(f"1. Download/copy your best.pt file to: {model_path.absolute()}")
        print("2. Re-run this setup script")
        sys.exit(1)
    
    # Test model loading
    if not test_model_loading(str(model_path)):
        print("\n❌ Setup failed: Model loading error")
        sys.exit(1)
    
    # Test API connection
    api_running = test_api_connection()
    
    if api_running:
        # Set model via API
        if set_model_via_api(str(model_path)):
            verify_model_status()
        else:
            print("\n⚠️  Could not set model via API")
    
    print("\n🎉 Setup Complete!")
    print("\n📋 Next steps:")
    
    if not api_running:
        print("1. Start the SafeMad API:")
        print("   cd backend && uvicorn main:app --reload")
        print(f"2. Set the model: curl -X POST 'http://localhost:8000/api/set-floor-plan-model?model_path={model_path}'")
    
    print("3. Test with a floor plan:")
    print(f"   python test_enhanced_floor_plan.py {model_path} your_floorplan.jpg 0.4")
    
    print("\n4. Use via API:")
    print("   curl -X POST 'http://localhost:8000/api/analyze-floor-plan?method=enhanced' -F 'file=@floorplan.jpg'")
    
    print("\n📖 See ENHANCED_MODEL_SETUP.md for detailed usage instructions")

if __name__ == "__main__":
    main() 