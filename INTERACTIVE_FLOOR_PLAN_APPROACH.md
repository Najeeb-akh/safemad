# Interactive Floor Plan Annotation Approach

## Overview

Instead of using Google Vision API for automatic room detection, this approach lets users manually annotate their floor plans for more accurate and controlled room identification.

## Benefits of Interactive Annotation

### 🎯 **Accuracy**
- Users know exactly what each room is
- No AI misidentification errors
- Perfect room boundaries

### 💰 **Cost Effective**
- No Google Cloud API costs
- No external dependencies
- Completely free to use

### 🎨 **User Control**
- Custom room shapes (rectangles, polygons)
- Room naming and categorization
- Color coding for easy identification

### 📊 **Rich Data**
- Room area calculations
- Detailed safety analysis per room
- Customized emergency plans

## How It Works

### 1. Upload Floor Plan
```dart
// User uploads or takes a photo of their floor plan
_getImage(ImageSource.gallery) // or ImageSource.camera
```

### 2. Choose Annotation Method
- **Draw Rooms** (Interactive) - Manual annotation
- **Auto Detect** (Legacy) - Google Vision API fallback

### 3. Interactive Drawing Tools
- **Rectangle Tool**: For standard rectangular rooms
- **Polygon Tool**: For irregular room shapes
- **Room Type Selection**: Kitchen, Bedroom, Living Room, etc.

### 4. Room Management
- Edit room names and types
- Delete unwanted annotations
- Color-coded room identification

### 5. Save & Analyze
- Automatic area calculations
- Safety analysis per room type
- Generated emergency evacuation plans

## API Endpoints

### Save Annotations
```
POST /api/save-floor-plan-annotations
```
```json
{
  "rooms": [
    {
      "id": "room_1",
      "name": "Master Bedroom",
      "type": "Bedroom",
      "color": 4291821312,
      "boundary": {
        "type": "rectangle",
        "topLeft": {"x": 100, "y": 150},
        "bottomRight": {"x": 300, "y": 250}
      }
    }
  ],
  "imageSize": {
    "width": 800,
    "height": 600
  }
}
```

### Get Safety Report
```
GET /api/safety-report/{annotation_id}
```
Returns comprehensive safety analysis with:
- Overall safety score
- Room-specific recommendations
- Emergency evacuation plan
- Risk assessments

### Get Room Analysis
```
GET /api/room-safety-analysis/{annotation_id}
```
Returns detailed safety features for each room.

## Room Types & Safety Analysis

The system provides intelligent safety recommendations based on room types:

### 🛏️ **Bedrooms**
- **Fire Safety**: High priority
- **Recommendations**: Smoke detectors, clear exit paths, escape ladders for upper floors

### 🍳 **Kitchen**
- **Fire Safety**: High priority  
- **Recommendations**: Fire extinguisher, proper ventilation, keep exits clear

### 🛁 **Bathroom**
- **Accessibility**: Special consideration
- **Recommendations**: Non-slip surfaces, adequate lighting, grab bars

### 🛋️ **Living Areas**
- **Fire Safety**: Medium priority
- **Recommendations**: Furniture placement, secure heavy items, lighting

## Migration from Google Vision

### Before (Google Vision)
```python
# Automatic detection - less accurate
detected_rooms = vision_service.analyze_floor_plan(image_bytes)
```

### After (Interactive)
```python
# User-annotated - highly accurate
annotations = annotation_service.save_annotations(user_id, user_data)
safety_report = annotation_service.generate_safety_report(annotation_id)
```

## Getting Started

1. **Run the Backend**
   ```bash
   cd backend
   python -m uvicorn main:app --reload
   ```

2. **Run the Flutter App**
   ```bash
   cd mobile
   flutter run
   ```

3. **Upload Floor Plan**
   - Take photo or upload image
   - Choose "Draw Rooms" option

4. **Annotate Your Floor Plan**
   - Select room type from dropdown
   - Choose rectangle or polygon tool
   - Draw room boundaries
   - Edit names as needed

5. **Save & Get Analysis**
   - Tap save button
   - Receive detailed safety report
   - Get customized emergency plan

## Technical Features

### Flutter Frontend
- Custom painting with `CustomPainter`
- Gesture detection for drawing
- Real-time preview of annotations
- Cross-platform support (iOS, Android, Web)

### FastAPI Backend
- RESTful API endpoints
- Room area calculations using shoelace formula
- Intelligent safety analysis algorithms
- Emergency plan generation

### Data Processing
- Coordinate normalization across different screen sizes
- Polygon and rectangle boundary support
- Room type-based safety scoring
- Comprehensive reporting system

## Future Enhancements

- [ ] Zoom and pan functionality
- [ ] Undo/redo drawing actions
- [ ] Room template library
- [ ] 3D visualization
- [ ] Voice annotations
- [ ] Collaborative editing
- [ ] PDF export of safety reports

This interactive approach provides much more accurate and useful data for the AI model while giving users complete control over their floor plan annotation! 