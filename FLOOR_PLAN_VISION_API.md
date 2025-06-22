# Floor Plan Analysis with Google Cloud Vision API

## Overview

SafeMad uses Google Cloud Vision API to analyze floor plan images and extract valuable information such as:

- Room identification and layout
- Door and window detection
- Dimension/measurement extraction
- Room type classification

This document explains how to use this feature and how it works under the hood.

## How to Use

### API Endpoint

```
POST /api/analyze-floor-plan
```

Upload a floor plan image to analyze it. The endpoint accepts form data with an image file.

### Example Request (with curl)

```bash
curl -X POST "http://localhost:8000/api/analyze-floor-plan" \
     -H "Content-Type: multipart/form-data" \
     -F "file=@/path/to/your/floorplan.jpg"
```

### Example Response

```json
{
  "detected_rooms": [
    {
      "room_id": 1,
      "default_name": "Living Room",
      "boundaries": {
        "x": 120,
        "y": 80,
        "width": 250,
        "height": 180
      },
      "color": "#FF6B6B",
      "confidence": 0.92,
      "doors": [
        {
          "position": {"x": 150, "y": 80},
          "width": 30,
          "height": 5,
          "confidence": 0.85
        }
      ],
      "windows": [
        {
          "position": {"x": 200, "y": 80},
          "width": 40,
          "height": 5,
          "confidence": 0.78
        }
      ],
      "measurements": [
        {
          "type": "wall",
          "value": "250 cm",
          "position": {"x": 120, "y": 80}
        }
      ]
    },
    {
      "room_id": 2,
      "default_name": "Kitchen",
      "boundaries": { /* ... */ },
      "doors": [ /* ... */ ],
      "windows": [ /* ... */ ],
      "measurements": [ /* ... */ ]
    }
  ],
  "image_dimensions": {
    "width": 800,
    "height": 600
  },
  "processing_method": "google_vision",
  "objects_found": 15,
  "texts_found": 8,
  "total_doors": 4,
  "total_windows": 6,
  "total_measurements": 12
}
```

## How It Works

The analysis pipeline performs several steps:

1. **Vision API Calls**:
   - Object localization to detect architectural elements
   - Text detection to identify room labels and measurements
   - Document text detection for structured information

2. **Room Detection**:
   - Identifies room areas using text labels (like "Kitchen", "Bedroom")
   - Uses object detection as fallback
   - Associates elements with their respective rooms

3. **Door & Window Detection**:
   - Identifies door and window objects using semantic recognition
   - Records position, size and confidence for each

4. **Measurement Extraction**:
   - Finds text matching measurement patterns (e.g., "250 cm", "3.5m")
   - Associates measurements with nearby walls/elements

## Testing Locally

We've provided a test script to try out the Vision API with your own floor plan images:

```bash
python backend/test_vision_api.py path/to/your/floorplan.jpg
```

By default, this runs in "dummy" mode without making real API calls. To use the actual Google Cloud Vision API:

1. Follow the setup in `GOOGLE_CLOUD_SETUP.md`
2. Edit `test_vision_api.py` and set `vision_service.use_dummy = False`
3. Run the test script

## Integration with Vision Pro

To integrate with Vision Pro:
1. Capture floor plan with Vision Pro camera
2. Send image to backend API endpoint
3. Render results in AR/VR environment
4. Allow interaction with detected elements

## Limitations

- Works best with clear, high-contrast floor plans
- May struggle with hand-drawn or very detailed plans  
- Measurement detection depends on clear text labels
- Room boundary detection is approximate

## Next Steps

Future improvements planned:
- More accurate room boundary polygon detection
- 3D spatial mapping for AR/VR
- Material type detection from textures
- Support for multiple floors 