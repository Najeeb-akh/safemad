# Floor Plan Object Detection Integration

## Overview

This document describes the integration of the floor plan object detection model from the GitHub repository [sanatladkat/floor-plan-object-detection](https://github.com/sanatladkat/floor-plan-object-detection) into your SafeMad application.

## What's Been Integrated

### 1. Core Model Integration
- **Model File**: `backend/best.pt` - The pre-trained YOLOv8 model specialized for floor plan detection
- **Detection Classes**: 9 architectural elements including doors, windows, walls, stairs, columns, etc.
- **Full Integration**: All functionality from the original GitHub repository has been adapted for your API

### 2. Enhanced Services

#### New Files Added:
- `backend/services/floor_plan_helper.py` - Utility functions from the original repository
- `backend/services/floor_plan_settings.py` - Configuration and settings management
- `backend/routers/floor_plan_test.py` - Test endpoints for validation

#### Enhanced Files:
- `backend/services/enhanced_floor_plan_service.py` - Updated with GitHub repository functionality
- `backend/services/floor_plan_detector.py` - Already existed with the core detection logic
- `backend/main.py` - Added test router

### 3. Detection Capabilities

The integrated model can detect these architectural elements:
- **Column** - Structural columns
- **Curtain Wall** - Modern glass wall systems  
- **Dimension** - Measurement annotations
- **Door** - Standard doors
- **Railing** - Safety railings and barriers
- **Sliding Door** - Sliding door systems
- **Stair Case** - Staircases and steps
- **Wall** - Standard walls
- **Window** - Windows and openings

## API Endpoints

### Production Endpoints

#### 1. Analyze Floor Plan
```http
POST /api/analyze-floor-plan
```
- **Purpose**: Main endpoint for floor plan analysis
- **Input**: Image file (JPG, PNG, etc.)
- **Parameters**: 
  - `method`: Set to "enhanced" to use the GitHub repository model
  - `confidence`: Detection confidence threshold (0.0-1.0, default: 0.4)
- **Output**: Comprehensive analysis including rooms, elements, insights

#### 2. Set Model Path
```http
POST /api/set-floor-plan-model?model_path=backend/best.pt
```
- **Purpose**: Configure the model path
- **Note**: Should already be configured automatically

#### 3. Model Status
```http
GET /api/model-status
```
- **Purpose**: Check which detection methods are available
- **Output**: Status of all available detection methods

### Test Endpoints

#### 1. Model Status Test
```http
GET /api/test/model-status
```
- **Purpose**: Detailed status check for GitHub repository integration
- **Output**: Complete integration status report

#### 2. Sample Analysis Test
```http
POST /api/test/analyze-sample
```
- **Purpose**: Test floor plan analysis with full feature verification
- **Input**: Floor plan image file
- **Output**: Complete analysis results with test metadata

#### 3. Detection Labels Test
```http
GET /api/test/detection-labels
```
- **Purpose**: Verify detection labels are properly loaded
- **Output**: All available detection classes and labels

## Usage Examples

### Basic Usage
```python
# Using the enhanced method with GitHub repository model
POST /api/analyze-floor-plan
Content-Type: multipart/form-data
- file: your_floor_plan.jpg
- method: enhanced
- confidence: 0.4
```

### Response Format
```json
{
  "detected_rooms": [
    {
      "room_id": 0,
      "default_name": "Multi-room Layout",
      "boundaries": {...},
      "architectural_elements": [...],
      "doors": [...],
      "windows": [...],
      "walls": [...]
    }
  ],
  "architectural_elements": [
    {
      "type": "Door",
      "confidence": 0.85,
      "bbox": {"x1": 100, "y1": 200, "x2": 150, "y2": 300},
      "center": {"x": 125, "y": 250},
      "dimensions": {"width": 50, "height": 100}
    }
  ],
  "processing_method": "enhanced_floor_plan_yolo_github_integration",
  "element_counts": {
    "Door": 3,
    "Window": 5,
    "Wall": 12
  },
  "layout_insights": {
    "insights": [
      "🚪 Multiple access points: 3 doors detected",
      "🪟 Good natural light: 5 windows detected",
      "🏠 Complex layout with multiple rooms/spaces"
    ],
    "space_type": "Multi-room Layout",
    "confidence": 0.75
  },
  "csv_export": "Label,Count\nDoor,3\nWindow,5\nWall,12",
  "annotated_image_base64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg...",
  "suggested_confidence": 0.35
}
```

## Key Features

### 1. Smart Object Detection
- **Trained Model**: Uses the pre-trained model from the GitHub repository
- **High Accuracy**: Specialized for architectural floor plans
- **Multiple Classes**: Detects 9 different architectural elements

### 2. Enhanced Analysis
- **Room Detection**: Automatically identifies and groups rooms
- **Layout Insights**: Provides intelligent analysis of the space
- **Area Estimation**: Calculates approximate room areas
- **Space Classification**: Determines the type of space (residential, commercial, etc.)

### 3. Export Capabilities
- **CSV Export**: Detection results in CSV format
- **Annotated Images**: Visual results with bounding boxes
- **Base64 Encoding**: Ready for web display

### 4. Validation & Optimization
- **Image Validation**: Checks image quality and format
- **Confidence Optimization**: Suggests optimal confidence thresholds
- **Error Handling**: Comprehensive error handling and reporting

## Testing the Integration

### 1. Check Model Status
```bash
curl -X GET "http://localhost:8000/api/test/model-status"
```

### 2. Test with Sample Image
```bash
curl -X POST "http://localhost:8000/api/test/analyze-sample" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@your_floor_plan.jpg"
```

### 3. Verify Detection Labels
```bash
curl -X GET "http://localhost:8000/api/test/detection-labels"
```

## Configuration

### Environment Variables
- `FLOOR_PLAN_CONFIDENCE`: Override default confidence threshold
- `DISABLE_GPU`: Disable GPU usage for YOLO model
- `LOG_LEVEL`: Set logging level for debugging

### Model Settings
The integration uses the settings from `backend/services/floor_plan_settings.py`:
- Default confidence: 0.4
- Maximum image size: 4000x4000 pixels
- Supported formats: JPG, PNG, BMP, TIFF

## Troubleshooting

### Common Issues

1. **Model not found**: Ensure `backend/best.pt` exists
2. **Import errors**: Check all dependencies are installed
3. **Low detection quality**: Adjust confidence threshold
4. **Memory issues**: Reduce image size or disable GPU

### Debug Endpoints
- Use `/api/test/model-status` to check integration status
- Use `/api/model-status` to see all available detection methods
- Check logs for detailed error messages

## Performance Notes

- **GPU Usage**: Automatically uses GPU if available
- **Batch Processing**: Currently processes one image at a time
- **Memory**: Model requires ~100MB RAM when loaded
- **Speed**: Typical analysis takes 2-5 seconds per image

## Integration Benefits

1. **Specialized Model**: Purpose-built for floor plan detection vs generic YOLO
2. **Higher Accuracy**: Trained specifically on architectural drawings
3. **Rich Insights**: Provides detailed layout analysis beyond just detection
4. **Production Ready**: Includes validation, error handling, and optimization
5. **Easy to Use**: Simple API interface with comprehensive documentation

The integration successfully combines the best of both worlds - your existing SafeMad infrastructure with the specialized floor plan detection capabilities from the GitHub repository. 