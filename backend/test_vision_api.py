#!/usr/bin/env python3
"""
Test script for Google Cloud Vision API floor plan analysis
"""
import asyncio
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend.services.vision_service import vision_service

async def test_vision_api(image_path):
    """Test the vision API with a sample floor plan image"""
    print(f"Testing Google Cloud Vision API with image: {image_path}")
    
    # Check if file exists
    if not os.path.exists(image_path):
        print(f"Error: File {image_path} does not exist")
        return
    
    # Read image file
    with open(image_path, "rb") as image_file:
        image_bytes = image_file.read()
    
    # Process with Vision API
    result = await vision_service.analyze_floor_plan(image_bytes)
    
    # Print results
    print("\n=== Floor Plan Analysis Results ===")
    print(f"Processing method: {result['processing_method']}")
    print(f"Image dimensions: {result['image_dimensions']['width']}x{result['image_dimensions']['height']}")
    
    if 'total_doors' in result:
        print(f"Total doors detected: {result['total_doors']}")
    if 'total_windows' in result:
        print(f"Total windows detected: {result['total_windows']}")
    if 'total_measurements' in result:
        print(f"Total measurements detected: {result['total_measurements']}")
    
    # Print room details
    print(f"\nDetected {len(result['detected_rooms'])} rooms:")
    for room in result['detected_rooms']:
        print(f"\nRoom ID: {room['room_id']} - {room['default_name']}")
        print(f"  Position: x={room['boundaries']['x']}, y={room['boundaries']['y']}")
        print(f"  Size: {room['boundaries']['width']}x{room['boundaries']['height']}")
        print(f"  Confidence: {room['confidence']:.2f}")
        print(f"  Doors: {len(room['doors'])}")
        print(f"  Windows: {len(room['windows'])}")
        print(f"  Measurements: {len(room['measurements'])}")
        
        # Print detailed elements
        if len(room['doors']) > 0:
            print("  Door details:")
            for door in room['doors']:
                print(f"    - Position: x={door['position']['x']}, y={door['position']['y']}, Width: {door['width']}")
                
        if len(room['windows']) > 0:
            print("  Window details:")
            for window in room['windows']:
                print(f"    - Position: x={window['position']['x']}, y={window['position']['y']}, Width: {window['width']}")
                
        if len(room['measurements']) > 0:
            print("  Measurement details:")
            for measurement in room['measurements']:
                print(f"    - {measurement['value']} at x={measurement['position']['x']}, y={measurement['position']['y']}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 backend/test_vision_api.py <path_to_floor_plan_image>")
        sys.exit(1)
        
    image_path = sys.argv[1]
    asyncio.run(test_vision_api(image_path)) 