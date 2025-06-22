# Enhanced Floor Plan Model Integration

This document describes the integration of the enhanced YOLOv8 floor plan detection model into the SafeMad Flutter application.

## Overview

The enhanced model provides superior detection of architectural elements including:
- **Doors** (regular and sliding)
- **Windows**
- **Walls**
- **Stairs**
- **Columns**
- **Railing**
- **Curtain walls**
- **Dimensions**

This information is crucial for generating accurate safety heatmaps and emergency planning.

## Architecture

### Backend Integration

The enhanced model is integrated through several components:

1. **Enhanced Floor Plan Service** (`backend/services/enhanced_floor_plan_service.py`)
   - Handles the specialized YOLOv8 model
   - Processes architectural element detection
   - Generates room clusters based on spatial proximity
   - Provides detailed element analysis

2. **Vision Service** (`backend/services/vision_service.py`)
   - Orchestrates different detection methods
   - Auto-selects the best available method
   - Falls back gracefully when enhanced model is unavailable

3. **API Endpoints** (`backend/routers/floor_plan.py`)
   - `/api/analyze-floor-plan` - Main analysis endpoint
   - `/api/set-floor-plan-model` - Model configuration
   - `/api/model-status` - Service status

### Flutter Integration

The Flutter app includes:

1. **Enhanced Floor Plan Service** (`mobile/lib/services/enhanced_floor_plan_service.dart`)
   - API client for enhanced model
   - Data models for detection results
   - Error handling and status management

2. **Enhanced Detection Results Screen** (`mobile/lib/screens/enhanced_detection_results_screen.dart`)
   - Detailed visualization of detection results
   - Room-by-room analysis
   - Architectural element breakdown
   - Integration with safety assessment

3. **Enhanced Model Configuration Screen** (`mobile/lib/screens/enhanced_model_config_screen.dart`)
   - Model setup and configuration
   - Status monitoring
   - Setup instructions

4. **Updated Home Mapping Screen** (`mobile/lib/screens/home_mapping_screen.dart`)
   - Method selection (Auto/Enhanced/YOLO/Google Vision)
   - Confidence threshold adjustment
   - Real-time status monitoring

## Setup Instructions

### 1. Backend Setup

```bash
# Install dependencies
cd backend
pip install -r requirements.txt

# Ensure you have the enhanced model file
# Place your best.pt file in the models directory
mkdir -p models
# Copy your trained model to models/best.pt

# Start the backend server
uvicorn main:app --reload
```

### 2. Model Configuration

The enhanced model can be configured in several ways:

#### Option A: Via API (Recommended)
```bash
curl -X POST "http://localhost:8000/api/set-floor-plan-model?model_path=/path/to/models/best.pt"
```

#### Option B: Via Flutter App
1. Open the SafeMad app
2. Navigate to Home Mapping screen
3. Tap the settings icon (⚙️)
4. Enter the model path and tap "Set Model"

#### Option C: Via Setup Script
```bash
python setup_enhanced_model.py
```

### 3. Flutter App Setup

```bash
# Navigate to mobile directory
cd mobile

# Install dependencies
flutter pub get

# Run the app
flutter run
```

## Usage

### 1. Model Status Check

The app automatically checks model status on startup:

- **Green**: Enhanced model loaded and ready
- **Orange**: Enhanced model available but not loaded
- **Red**: Enhanced model unavailable

### 2. Floor Plan Analysis

1. **Upload Floor Plan**: Use camera or gallery
2. **Select Method**: Choose from available options
   - **Auto**: Automatically selects best method
   - **Enhanced**: Uses specialized floor plan model
   - **YOLO**: Uses YOLO + Computer Vision
   - **Google Vision**: Uses Google Cloud Vision API
3. **Adjust Confidence**: For enhanced method (0.1-0.9)
4. **Analyze**: Process the floor plan

### 3. Results Review

The enhanced detection results screen shows:

- **Summary**: Total counts of rooms, doors, windows, walls
- **Room List**: All detected rooms with confidence scores
- **Room Details**: Detailed analysis of selected room
  - Architectural elements (doors, windows, walls)
  - Estimated dimensions
  - Room boundaries
  - Detection confidence

### 4. Safety Assessment

From the results screen, proceed to safety assessment:

- Room-specific safety questions
- Integration with detected architectural elements
- Enhanced safety scoring based on actual layout

## API Endpoints

### Analysis Endpoint
```
POST /api/analyze-floor-plan
Parameters:
- file: Floor plan image
- method: 'auto' | 'enhanced' | 'yolo' | 'google_vision'
- confidence: 0.1-0.9 (for enhanced method)
```

### Model Configuration
```
POST /api/set-floor-plan-model?model_path=<path>
GET /api/model-status
```

## Data Models

### Enhanced Floor Plan Result
```dart
class EnhancedFloorPlanResult {
  final List<DetectedRoom> detectedRooms;
  final List<ArchitecturalElement> architecturalElements;
  final Map<String, int> imageDimensions;
  final String processingMethod;
  final double detectionConfidence;
  final int totalDoors;
  final int totalWindows;
  final int totalWalls;
  final int totalStairs;
  final Map<String, int> elementCounts;
  final String analysisSummary;
  final String? error;
}
```

### Detected Room
```dart
class DetectedRoom {
  final String roomId;
  final String defaultName;
  final Map<String, dynamic> boundaries;
  final double confidence;
  final List<ArchitecturalElement> architecturalElements;
  final String description;
  final String detectionMethod;
  final List<ArchitecturalElement> doors;
  final List<ArchitecturalElement> windows;
  final List<ArchitecturalElement> walls;
  final Map<String, double> estimatedDimensions;
}
```

### Architectural Element
```dart
class ArchitecturalElement {
  final String type;
  final double confidence;
  final Map<String, int> bbox;
  final Map<String, int> center;
  final Map<String, int> dimensions;
  final int area;
  final String relativePosition;
}
```

## Testing

### Integration Test
```bash
python test_enhanced_integration.py
```

This script tests:
- API connectivity
- Model status endpoints
- Enhanced analysis functionality
- Flutter service endpoints

### Manual Testing
1. Start backend: `uvicorn backend.main:app --reload`
2. Start Flutter app: `cd mobile && flutter run`
3. Upload a floor plan image
4. Test different analysis methods
5. Verify results in enhanced detection screen

## Troubleshooting

### Common Issues

1. **Model Not Loading**
   - Check model file path
   - Verify model file exists and is valid
   - Check file permissions

2. **API Connection Errors**
   - Ensure backend is running on port 8000
   - Check CORS configuration
   - Verify network connectivity

3. **Analysis Failures**
   - Check image format (JPEG, PNG supported)
   - Verify image size (not too large)
   - Check model confidence threshold

4. **Flutter App Issues**
   - Run `flutter pub get` to install dependencies
   - Check for any linter errors
   - Verify API base URL in service

### Debug Information

Enable debug logging:
```bash
# Backend
uvicorn main:app --reload --log-level debug

# Flutter
flutter run --debug
```

## Performance Considerations

### Model Loading
- Enhanced model is ~50MB
- Loads once on startup
- Cached in memory for subsequent requests

### Analysis Speed
- Enhanced method: 2-5 seconds per image
- YOLO method: 1-3 seconds per image
- Google Vision: 3-8 seconds per image

### Memory Usage
- Model: ~200MB RAM
- Processing: ~100MB per analysis
- Total: ~300MB for enhanced detection

## Future Enhancements

1. **Real-time Processing**: Stream processing for video input
2. **Batch Processing**: Multiple floor plans simultaneously
3. **Model Updates**: Automatic model version management
4. **Cloud Deployment**: Scalable cloud-based processing
5. **Mobile Optimization**: On-device model inference

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review the test scripts
3. Check backend logs for errors
4. Verify model file integrity

## License

This integration is part of the SafeMad project. See the main project license for details. 