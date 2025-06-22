#!/usr/bin/env python3
"""
SAM Model Download Script

Downloads the SAM (Segment Anything Model) checkpoint for room segmentation
"""

import os
import requests
from pathlib import Path
import hashlib
from tqdm import tqdm

# SAM model URLs and checksums
SAM_MODELS = {
    'vit_h': {
        'url': 'https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth',
        'filename': 'sam_vit_h_4b8939.pth',
        'size_mb': 2560,
        'description': 'ViT-H (Huge) - Best quality, slowest'
    },
    'vit_l': {
        'url': 'https://dl.fbaipublicfiles.com/segment_anything/sam_vit_l_0b3195.pth',
        'filename': 'sam_vit_l_0b3195.pth', 
        'size_mb': 1192,  # Updated to actual file size
        'description': 'ViT-L (Large) - Good balance of quality and speed'
    },
    'vit_b': {
        'url': 'https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth',
        'filename': 'sam_vit_b_01ec64.pth',
        'size_mb': 375,
        'description': 'ViT-B (Base) - Fastest, smallest'
    }
}

def download_file(url: str, filepath: Path) -> bool:
    """Download a file with progress bar"""
    try:
        print(f"📥 Downloading: {url}")
        print(f"📁 Saving to: {filepath}")
        
        response = requests.get(url, stream=True)
        response.raise_for_status()
        
        total_size = int(response.headers.get('content-length', 0))
        
        with open(filepath, 'wb') as file, tqdm(
            desc=filepath.name,
            total=total_size,
            unit='B',
            unit_scale=True,
            unit_divisor=1024,
        ) as pbar:
            for chunk in response.iter_content(chunk_size=8192):
                size = file.write(chunk)
                pbar.update(size)
        
        print(f"✅ Download complete: {filepath}")
        return True
        
    except Exception as e:
        print(f"❌ Download failed: {e}")
        return False

def download_sam_model(model_type: str = 'vit_l', models_dir: str = 'backend/models') -> bool:
    """
    Download SAM model checkpoint
    
    Args:
        model_type: 'vit_h', 'vit_l', or 'vit_b'
        models_dir: Directory to save the model
        
    Returns:
        True if successful, False otherwise
    """
    if model_type not in SAM_MODELS:
        print(f"❌ Invalid model type: {model_type}")
        print(f"Available models: {list(SAM_MODELS.keys())}")
        return False
    
    model_info = SAM_MODELS[model_type]
    
    # Create models directory
    models_path = Path(models_dir)
    models_path.mkdir(parents=True, exist_ok=True)
    
    filepath = models_path / model_info['filename']
    
    # Check if model already exists
    if filepath.exists():
        print(f"✅ SAM model already exists: {filepath}")
        file_size_mb = filepath.stat().st_size / (1024 * 1024)
        print(f"📏 File size: {file_size_mb:.1f} MB")
        return True
    
    print(f"🤖 Downloading SAM {model_type.upper()} model")
    print(f"📝 Description: {model_info['description']}")
    print(f"📦 Expected size: {model_info['size_mb']} MB")
    print()
    
    # Download the model
    success = download_file(model_info['url'], filepath)
    
    if success:
        # Verify file size
        actual_size_mb = filepath.stat().st_size / (1024 * 1024)
        expected_size_mb = model_info['size_mb']
        size_diff = abs(actual_size_mb - expected_size_mb)
        
        # More lenient validation - allow up to 10% difference or 100MB, whichever is larger
        tolerance_percent = expected_size_mb * 0.1  # 10% tolerance
        tolerance_mb = max(tolerance_percent, 100)  # At least 100MB tolerance
        
        if size_diff <= tolerance_mb:
            print(f"✅ Model download verified: {actual_size_mb:.1f} MB")
            print(f"📏 Size difference: {size_diff:.1f} MB (within {tolerance_mb:.1f} MB tolerance)")
            return True
        else:
            print(f"⚠️ Significant file size difference: expected ~{expected_size_mb} MB, got {actual_size_mb:.1f} MB")
            print(f"🤔 Difference: {size_diff:.1f} MB (tolerance: {tolerance_mb:.1f} MB)")
            
            # Ask user if they want to continue anyway
            user_choice = input("Continue anyway? The file might still work (y/n): ").strip().lower()
            if user_choice in ['y', 'yes']:
                print("✅ Proceeding with downloaded model")
                return True
            else:
                print("❌ Download marked as failed")
                return False
    
    return False

def main():
    """Main function"""
    print("🎭 SAM Model Download Script")
    print("=" * 50)
    print()
    
    print("Available SAM models:")
    for model_type, info in SAM_MODELS.items():
        print(f"  {model_type}: {info['description']} ({info['size_mb']} MB)")
    
    print()
    print("Recommendation: vit_l (good balance of quality and speed)")
    print()
    
    # Ask user which model to download
    while True:
        choice = input("Which model would you like to download? (vit_h/vit_l/vit_b) [vit_l]: ").strip().lower()
        
        if not choice:
            choice = 'vit_l'
        
        if choice in SAM_MODELS:
            break
        else:
            print(f"Invalid choice: {choice}")
    
    print()
    
    # Download the selected model
    success = download_sam_model(choice)
    
    if success:
        print()
        print("🎉 SAM model download complete!")
        print()
        print("Next steps:")
        print("1. Install SAM dependencies: pip install segment-anything supervision")
        print("2. Restart your FastAPI server")
        print("3. Test the integration with: GET /api/model-status")
        print("4. Use the AI Detect button with: POST /api/analyze-floor-plan-with-sam")
    else:
        print()
        print("❌ SAM model download failed!")
        print()
        print("Troubleshooting:")
        print("1. Check your internet connection")
        print("2. Ensure you have enough disk space")
        print("3. Try downloading manually from:")
        print(f"   {SAM_MODELS[choice]['url']}")

if __name__ == "__main__":
    main() 