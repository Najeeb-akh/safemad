# Structured Data System for Floor Plan Analysis

## Overview

This document describes the new structured data organization system that takes all the information from AI detections, user annotations, and user logs, and organizes them into a clean, structured format for analysis and storage.

## Problem Statement

Previously, data was stored in various unstructured formats:
- AI detections mixed different object types together
- User annotations were stored as drawing data without clear categorization  
- Room assessments were separate from object data
- No clear separation between rooms, walls, doors, windows, etc.
- Difficult to perform comprehensive safety analysis
- No audit trail for user modifications

## Solution: Structured Data Organization

### Core Principles

1. **Clear Object Separation**: Different types of objects (rooms, walls, doors, etc.) are stored in separate, well-defined structures
2. **Comprehensive Information**: All relevant information for each object is stored together
3. **Source Tracking**: Every object tracks whether it came from AI detection or user input
4. **Audit Trail**: All user interactions and modifications are logged
5. **Analysis-Ready Format**: Data is structured for easy safety analysis and reporting

### Data Structure Organization

#### 📊 Main Container: `FloorPlanStructuredData`

```python
FloorPlanStructuredData
├── analysis_id: str                    # Unique identifier
├── user_id: str                        # User who created this
├── timestamp: datetime                 # When analysis was created
├── floor_plan_metadata: dict           # Image info, dimensions, etc.
├── general_objects: List[GeneralObject]    # Walls, doors, windows, columns
├── rooms: List[RoomObject]             # Rooms and MAMAD
├── staircases: List[StaircaseObject]   # Staircases and stairwells
├── user_logs: List[dict]               # All user interactions
├── house_boundary: dict                # Overall house boundary
├── house_materials: dict               # Construction materials
├── safety_analysis: dict               # Safety assessment results
└── summary_statistics: dict            # Object counts, confidence, etc.
```

#### 🏠 Room Objects (`RoomObject`)

For rooms and MAMAD (protected rooms):

```python
RoomObject
├── room_id: str                        # Unique identifier
├── name: str                           # Room name
├── room_type: str                      # living_room, bedroom, kitchen, etc.
├── location: BaseObjectLocation        # Position on floor plan
├── size: BaseObjectSize                # Dimensions and area
├── detection_metadata: DetectionMetadata  # How it was detected
├── wall_thickness_cm: float            # Wall thickness
├── wall_material: WallMaterial         # Construction material
├── doors_count: int                    # Number of doors
├── windows_count: int                  # Number of windows
├── doors: List[str]                    # IDs of door objects
├── windows: List[str]                  # IDs of window objects
├── walls: List[str]                    # IDs of wall objects
├── floor_plan_reference: dict          # Coordinates and boundaries
├── accessibility_score: float          # Safety accessibility rating
├── has_multiple_exits: bool            # Multiple exit points
├── emergency_egress_rating: str        # poor, limited, good
├── is_mamad: bool                      # Protected room flag
├── mamad_features: dict                # MAMAD-specific properties
├── user_assessments: dict              # User safety assessments
└── manual_measurements: dict           # User measurements
```

#### 🧱 General Objects (`GeneralObject`)

For walls, doors, windows, columns, and other structural elements:

```python
GeneralObject
├── object_id: str                      # Unique identifier
├── name: str                           # Object name/label
├── object_type: ObjectType             # wall, door, window, column, etc.
├── location: BaseObjectLocation        # Position on floor plan
├── size: BaseObjectSize                # Dimensions and area
├── location_context: LocationContext   # indoor, outdoor, semi_outdoor
├── detection_metadata: DetectionMetadata  # How it was detected
├── wall_material: WallMaterial         # (if wall) Construction material
├── wall_thickness_cm: float            # (if wall) Thickness in cm
├── is_load_bearing: bool               # (if wall) Structural importance
├── user_notes: str                     # User annotations
├── safety_rating: float                # User safety rating
├── connected_objects: List[str]        # Related object IDs
└── parent_room_id: str                 # Room this belongs to
```

#### 🏢 Staircase Objects (`StaircaseObject`)

For staircases and stairwells:

```python
StaircaseObject
├── staircase_id: str                   # Unique identifier
├── name: str                           # Staircase name
├── location: BaseObjectLocation        # Position on floor plan
├── size: BaseObjectSize                # Dimensions
├── detection_metadata: DetectionMetadata  # How it was detected
├── number_of_steps: int                # Step count
├── floor_connections: List[str]        # Connected floors
├── stair_width_cm: float               # Width measurement
├── has_handrails: bool                 # Safety features
├── emergency_exit_capability: bool     # Can be used for evacuation
├── accessibility_compliant: bool       # ADA compliance
└── floor_plan_reference: dict          # Coordinates and boundaries
```

### Detection Metadata

Every object includes metadata about how it was detected:

```python
DetectionMetadata
├── detection_source: DetectionSource   # ai_yolo, user_drawn, etc.
├── confidence: float                   # Detection confidence (0-1)
├── detection_timestamp: datetime       # When detected
├── ai_model_version: str               # AI model used
├── user_verified: bool                 # User confirmed this object
└── user_modified: bool                 # User changed this object
```

### Location and Size Information

Standardized location and size data for all objects:

```python
BaseObjectLocation
├── floor_plan_coordinates: dict        # x, y coordinates
├── relative_position: str              # top_left, center, etc.
├── bounding_box: dict                  # x1, y1, x2, y2
└── center_point: dict                  # center coordinates

BaseObjectSize  
├── area_pixels: float                  # Area in pixels
├── area_square_meters: float           # Estimated real area
├── width_pixels: float                 # Width in pixels
├── height_pixels: float                # Height in pixels
├── width_meters: float                 # Estimated real width
├── height_meters: float                # Estimated real height
└── perimeter: float                    # Perimeter measurement
```

## Data Conversion Process

### Input Sources

1. **AI Detections** (from `enhanced_detection_results_screen.dart`):
   - YOLO object detection results
   - SAM segmentation data
   - Room boundaries and classifications
   - Architectural element locations

2. **User Annotations** (from user drawing):
   - User-drawn rooms, walls, doors, windows
   - MAMAD annotations
   - Staircase markings
   - House boundary drawings

3. **User Assessments** (from safety assessments):
   - Wall materials and thickness
   - Door and window counts
   - Safety equipment locations
   - MAMAD features and capabilities

### Conversion Process

```python
# Example conversion
def convert_existing_data():
    structured_data = create_from_existing_data(
        ai_detections=yolo_sam_results,
        user_annotations=flutter_drawings,
        user_assessments=safety_questionnaire_data
    )
    
    analysis_id = structured_data_service.convert_and_store_data(
        ai_detections=ai_detections,
        user_annotations=user_annotations,
        user_assessments=user_assessments,
        user_id="user_123",
        floor_plan_metadata=image_metadata
    )
    
    return analysis_id
```

## API Usage

### Store Structured Data

```http
POST /api/structured-data/convert-and-store
Content-Type: application/json

{
  "ai_detections": {
    "detected_rooms": [...],
    "architectural_elements": [...],
    "processing_method": "enhanced_floor_plan_yolo_sam"
  },
  "user_annotations": [
    {
      "id": "annotation_1",
      "tool": "mamad",
      "points": [...],
      "roomData": {...}
    }
  ],
  "user_assessments": {
    "room_1": {
      "wall_material": "concrete_blocks",
      "wall_thickness": 25.0,
      "doors_count": 2
    }
  },
  "user_id": "user_123"
}
```

### Retrieve for Analysis

```http
GET /api/structured-data/analysis/{analysis_id}/for-safety-analysis
```

Returns analysis-ready data:

```json
{
  "success": true,
  "analysis_data": {
    "rooms": [
      {
        "id": "room_1",
        "name": "Living Room",
        "is_mamad": false,
        "wall_thickness_cm": 25.0,
        "wall_material": "concrete_blocks",
        "doors_count": 2,
        "windows_count": 3,
        "accessibility_score": 8.5,
        "mamad_features": null
      }
    ],
    "walls": [...],
    "doors": [...],
    "windows": [...],
    "summary": {
      "total_objects": 15,
      "mamad_count": 1,
      "ai_confidence": 0.85
    }
  }
}
```

### Update Objects

```http
PUT /api/structured-data/analysis/{analysis_id}/object
Content-Type: application/json

{
  "object_id": "room_1",
  "updates": {
    "wall_thickness_cm": 30.0,
    "user_notes": "Updated after manual measurement"
  },
  "user_action": "manual_measurement_update"
}
```

## Benefits of Structured Organization

### 🎯 For Safety Analysis

- **Clear Object Types**: Easily access all walls, doors, windows separately
- **Complete Information**: All relevant data for each object in one place
- **Material Tracking**: Know exactly what materials are used where
- **MAMAD Identification**: Clearly identify and analyze protected rooms
- **Egress Analysis**: Track all doors and windows for evacuation routes

### 📊 For Data Management

- **Consistent Structure**: Same format regardless of detection source
- **Audit Trail**: Complete log of user interactions and modifications
- **Version Control**: Track changes over time
- **Data Integrity**: Validated data types and relationships

### 🔍 For User Experience

- **Better Organization**: Users can easily find and modify specific objects
- **Clear Categorization**: No confusion between different object types
- **Progress Tracking**: See what has been verified vs. AI-detected
- **Comprehensive View**: All object information in one structured format

## Example Data Flow

1. **User uploads floor plan** → Enhanced detection results generated
2. **AI detects objects** → Raw YOLO/SAM data created  
3. **User draws annotations** → User annotations captured
4. **User completes assessments** → Safety assessment data collected
5. **Data conversion** → All data converted to structured format
6. **Storage** → Structured data stored with analysis ID
7. **Analysis** → Safety algorithms use structured data
8. **Updates** → User modifications tracked and logged

## Migration from Old System

To convert existing unstructured data:

```python
# Convert existing detection results
analysis_id = structured_data_service.convert_and_store_data(
    ai_detections=old_detection_results,
    user_annotations=old_user_drawings,
    user_assessments=old_safety_data,
    user_id=user_id
)

# Get converted structured data
structured_data = structured_data_service.get_structured_data(analysis_id)

# Use for safety analysis
analysis_ready_data = structured_data_service.get_objects_for_analysis(analysis_id)
```

## Integration Points

### With Enhanced Detection Results Screen

The Flutter screen should send data in this format:

```dart
// When saving annotations
final structuredDataRequest = {
  'ai_detections': _result.toJson(),
  'user_annotations': _userAnnotations,
  'user_assessments': _roomSafetyData,
  'user_id': currentUserId,
  'floor_plan_metadata': {
    'image_dimensions': _imageDimensions,
    'upload_timestamp': DateTime.now().toIso8601String(),
  }
};

// Send to structured data API
final response = await http.post(
  Uri.parse('$API_BASE_URL/api/structured-data/convert-and-store'),
  headers: {'Content-Type': 'application/json'},
  body: json.encode(structuredDataRequest),
);
```

### With Safety Analysis

Safety algorithms can now work with clean, organized data:

```python
def analyze_room_safety(analysis_id: str):
    # Get structured data
    data = structured_data_service.get_objects_for_analysis(analysis_id)
    
    # Analyze each room
    for room in data['rooms']:
        # Check MAMAD features
        if room['is_mamad']:
            analyze_mamad_compliance(room['mamad_features'])
        
        # Check egress routes
        analyze_egress_routes(room['doors_count'], room['windows_count'])
        
        # Check wall protection
        analyze_wall_protection(room['wall_material'], room['wall_thickness_cm'])
    
    # Analyze overall house structure
    analyze_house_materials(data['house_data']['materials'])
```

This structured approach makes the entire system much more organized, maintainable, and powerful for safety analysis! 