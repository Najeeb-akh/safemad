# Migration Guide: From Unstructured to Structured Safety Assessment System

This guide explains how to migrate from the old unstructured safety assessment system to the new structured data system that provides better organization, analysis capabilities, and data integrity.

## Overview

The new structured data system organizes all floor plan information into clearly defined categories:
- **General Objects**: Walls, doors, windows, columns (with location, size, material/thickness)
- **Rooms & MAMAD**: Room-specific data with wall thickness, door/window counts, MAMAD features
- **Staircases**: Separate category for staircase objects
- **User Interactions**: Complete audit trail of all user interactions

## Key Benefits

✅ **Better Organization**: Clear separation of object types instead of mixed storage  
✅ **Complete Audit Trail**: Track all user interactions and modifications  
✅ **Analysis-Ready**: Consistent data structure for safety algorithms  
✅ **Source Tracking**: Know whether data came from AI detection or user input  
✅ **Israeli Standards**: Built-in support for Israeli building materials and MAMAD features  

## Backend Migration

### 1. New Services Available

#### StructuredSafetyAssessmentService
Replaces the old unstructured safety assessment logic:

```python
from backend.services.structured_safety_assessment_service import StructuredSafetyAssessmentService

# Initialize service
service = StructuredSafetyAssessmentService()

# Convert old assessment to structured format
analysis_id = service.convert_unstructured_assessment_to_structured(
    old_assessment_data=old_data,
    annotation_id=annotation_id
)

# Submit assessment using structured data
result = service.submit_structured_safety_assessment(
    analysis_id=analysis_id,
    room_assessments=room_assessments
)
```

#### StructuredDataService
Handles all structured data operations:

```python
from backend.services.structured_data_service import StructuredDataService

service = StructuredDataService()

# Convert and store structured data
analysis_id = service.convert_and_store_data(
    ai_detections=ai_results,
    user_annotations=user_annotations,
    user_assessments=assessments
)

# Update objects
service.update_object(
    analysis_id=analysis_id,
    object_id=room_id,
    updates={'wall_thickness_cm': 25.0}
)
```

### 2. New API Endpoints

#### Primary Structured Endpoints
- `POST /api/structured-safety/submit-assessment` - Submit safety assessments
- `POST /api/structured-safety/generate-heatmap` - Generate heatmaps  
- `GET /api/structured-safety/assessment-results/{analysis_id}` - Get results
- `GET /api/structured-safety/room-analysis/{analysis_id}` - Get room analysis
- `POST /api/structured-data/convert-and-store` - Create structured data

#### Compatibility Endpoints (for gradual migration)
- `POST /api/structured-safety/submit-room-safety-assessment` - Auto-converts old format
- `POST /api/structured-safety/generate-explosive-risk-heatmap` - Auto-converts old format

### 3. Old Endpoints Status

Old endpoints are **deprecated but still functional** with automatic conversion:

```python
# OLD (deprecated but working)
POST /api/submit-room-safety-assessment
POST /api/generate-explosive-risk-heatmap

# NEW (recommended)
POST /api/structured-safety/submit-assessment  
POST /api/structured-safety/generate-heatmap
```

## Mobile App Migration

### 1. New Service Available

```dart
import '../services/structured_safety_service.dart';

// Create structured data from detection results
String analysisId = await StructuredSafetyService.createStructuredDataFromDetections(
  enhancedResults: detectionResults,
  userAnnotations: userAnnotations,
  userAssessments: assessments,
);

// Submit assessment using structured data
Map<String, dynamic> result = await StructuredSafetyService.submitStructuredSafetyAssessment(
  analysisId: analysisId,
  roomAssessments: roomAssessments,
);

// Generate heatmap using structured data
Map<String, dynamic> heatmap = await StructuredSafetyService.generateStructuredHeatmap(analysisId);
```

### 2. Compatibility Methods

For gradual migration, use compatibility methods that automatically convert to structured format:

```dart
// Compatibility method - automatically converts to structured format
Map<String, dynamic> result = await StructuredSafetyService.submitRoomSafetyAssessmentCompatibility(
  annotationId: annotationId,
  roomSafetyData: roomData,
);

// Check if conversion was successful
if (result.containsKey('_migration_info')) {
  String newAnalysisId = result['_migration_info']['analysis_id'];
  print('Converted to structured format with ID: $newAnalysisId');
}
```

### 3. Updated Screen Constructors

Screens now accept optional `analysisId` parameter:

```dart
// SafetyResultsScreen now accepts analysisId
SafetyResultsScreen(
  safetyReport: result,
  annotationId: annotationId,
  analysisId: result['analysis_id'], // New parameter
)

// EnhancedSafetyHeatmapScreen now accepts analysisId  
EnhancedSafetyHeatmapScreen(
  rooms: rooms,
  architecturalElements: elements,
  annotationId: annotationId,
  analysisId: analysisId, // New parameter
)
```

## Migration Strategy

### Phase 1: Compatibility Mode (Current)
- Old endpoints automatically convert to structured format
- Mobile app uses compatibility methods
- No breaking changes for existing code
- Migration info logged in responses

### Phase 2: Gradual Migration
- Update Enhanced Detection Results Screen to create structured data
- Pass `analysisId` through the assessment flow
- Use new structured endpoints directly
- Remove compatibility method calls

### Phase 3: Full Migration
- Remove old endpoint implementations
- Remove compatibility methods
- Update all screens to require `analysisId`
- Clean up deprecated code

## Data Structure Comparison

### Old Unstructured Format
```json
{
  "rooms": [
    {
      "id": "room1",
      "name": "Living Room", 
      "walls": [...],
      "doors": [...],
      "windows": [...],
      "user_responses": {...}
    }
  ]
}
```

### New Structured Format
```json
{
  "analysis_id": "structured_123",
  "general_objects": [
    {
      "object_id": "wall_1",
      "object_type": "wall",
      "location": {...},
      "size": {...},
      "material": "concrete",
      "thickness_cm": 25.0,
      "indoor_outdoor": "indoor"
    }
  ],
  "rooms": [
    {
      "room_id": "room_1", 
      "name": "Living Room",
      "wall_thickness_cm": 25.0,
      "doors_count": 2,
      "windows_count": 3,
      "walls": ["wall_1", "wall_2"],
      "user_assessments": {...}
    }
  ],
  "user_interaction_log": [...]
}
```

## Migration Checklist

### Backend
- [ ] Add structured safety assessment service
- [ ] Add structured data router  
- [ ] Update main.py to include new routers
- [ ] Update old endpoints to use compatibility mode
- [ ] Test conversion from old to new format

### Mobile App  
- [ ] Add structured safety service
- [ ] Update room safety assessment screen to use structured service
- [ ] Update enhanced heatmap screen to accept analysisId
- [ ] Update safety results screen to accept analysisId
- [ ] Test compatibility mode functionality

### Testing
- [ ] Verify old endpoints still work with auto-conversion
- [ ] Test new structured endpoints directly
- [ ] Verify migration info is logged correctly
- [ ] Test heatmap generation with both old and new data
- [ ] Validate data integrity after conversion

## Troubleshooting

### Common Issues

1. **Missing analysisId Parameter**
   - Use compatibility methods that auto-convert
   - Check response for `_migration_info` field

2. **Conversion Errors**
   - Check server logs for conversion details
   - Verify old data format is valid
   - Use fallback methods if structured conversion fails

3. **Heatmap Generation Issues**
   - Ensure analysisId is passed correctly
   - Check compatibility mode logs
   - Verify structured data was created successfully

### Debugging

Enable debug logging to track migration:

```python
# Backend logging
print(f"✅ Converted to structured format with analysis_id: {analysis_id}")
print(f"⚠️ Using fallback method - conversion failed")
```

```dart
// Mobile logging
print('🔄 Using compatibility mode for safety assessment');
print('✅ Successfully converted to structured format');
print('⚠️ Used fallback method - consider providing analysis_id');
```

## Benefits Realized

After migration, you'll have:

1. **Clearer Data Organization**: Objects properly categorized by type
2. **Complete Audit Trail**: Every user interaction tracked
3. **Better Analysis**: Consistent data structure for safety algorithms  
4. **Source Tracking**: Know AI vs user-created data
5. **Israeli Standards**: Built-in MAMAD and material support
6. **Easier Maintenance**: Well-defined data models and services

## Support

For migration support:
- Check server logs for conversion details
- Use compatibility endpoints during transition
- Refer to `backend/STRUCTURED_DATA_README.md` for detailed API documentation
- Test with the demonstration script in `backend/example_structured_data_usage.py` 