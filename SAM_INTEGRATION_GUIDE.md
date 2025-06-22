# SAM + YOLO Integration Guide

## Overview

This guide covers the integration of **SAM (Segment Anything Model)** with your existing **Enhanced YOLO** floor plan detection to create a powerful **AI Detect** button functionality.

## 🎯 What the AI Detect Button Does

When users click the **AI Detect** button in your frontend, it triggers a complete two-stage analysis:

### Stage 1: YOLO Architectural Detection 🏗️
- Detects **doors, windows, walls, stairs, columns** using the GitHub repository model
- Identifies **9 different architectural elements** with high precision
- Provides **bounding boxes, confidence scores, and positioning**

### Stage 2: SAM Room Segmentation 🎭  
- Uses SAM to **intelligently segment rooms** based on YOLO detections
- **Guided by architectural elements** for better accuracy
- Creates **precise room boundaries** and **semantic understanding**

### Stage 3: Combined Analysis 🔗
- **Merges YOLO and SAM results** for comprehensive insights
- Calculates **accessibility scores, safety features, room connectivity**
- Provides **enhanced room analysis** for emergency planning

## 🚀 Quick Setup

### 1. Install Dependencies
```bash
pip install segment-anything supervision transformers tqdm requests
```

### 2. Download SAM Model
```bash
python download_sam_model.py
```
This will:
- Show you available SAM models (ViT-H, ViT-L, ViT-B)
- Download your chosen model to `backend/models/`
- Verify the download integrity

**Recommendation**: Use `vit_l` for best balance of quality and speed.

### 3. Restart Your Server
```bash
cd backend
uvicorn main:app --reload
```

### 4. Test Integration
```bash
curl -X GET "http://localhost:8000/api/model-status"
```
Look for `"ai_detect_ready": true` in the response.

## 📡 API Endpoints

### Main AI Detect Endpoint
```http
POST /api/analyze-floor-plan-with-sam
```

**Parameters:**
- `file`: Floor plan image (JPG, PNG, etc.)
- `confidence`: YOLO confidence threshold (default: 0.4)
- `enable_sam`: Enable SAM room segmentation (default: true)

**Example Usage:**
```bash
curl -X POST "http://localhost:8000/api/analyze-floor-plan-with-sam" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@floorplan.jpg" \
  -F "confidence=0.4" \
  -F "enable_sam=true"
```

### Response Format
```json
{
  "processing_method": "enhanced_yolo_plus_sam_integration",
  "combined_analysis": true,
  
  "architectural_elements": [
    {
      "type": "Door",
      "confidence": 0.85,
      "bbox": {"x1": 100, "y1": 200, "x2": 150, "y2": 300},
      "center": {"x": 125, "y": 250}
    }
  ],
  
  "room_segments": [
    {
      "room_id": 0,
      "room_name": "Room 1", 
      "area_pixels": 15000,
      "room_type": "Large Room",
      "estimated_function": "Living Room",
      "door_count": 2,
      "accessibility_score": 0.8
    }
  ],
  
  "enhanced_rooms": [
    {
      "room_id": 0,
      "accessibility_score": 0.8,
      "safety_features": {
        "exit_count": 2,
        "has_multiple_exits": true,
        "emergency_egress": "good"
      },
      "room_connectivity": {
        "connection_level": "standard",
        "connectivity_score": 0.67
      }
    }
  ],
  
  "sam_visualization": "data:image/png;base64,iVBORw0KGg...",
  "annotated_image_base64": "data:image/png;base64,iVBORw0KGg...",
  
  "element_counts": {
    "Door": 3,
    "Window": 5, 
    "Wall": 12
  },
  
  "total_sam_rooms": 4,
  "analysis_summary": "Total objects detected: 20 | Doors: 3 | Windows: 5 | SAM detected 4 distinct room segments"
}
```

## 🎨 Frontend Integration

### For Your AI Detect Button
```javascript
async function triggerAIDetect(imageFile) {
  const formData = new FormData();
  formData.append('file', imageFile);
  formData.append('confidence', 0.4);
  formData.append('enable_sam', true);
  
  try {
    const response = await fetch('/api/analyze-floor-plan-with-sam', {
      method: 'POST',
      body: formData
    });
    
    const results = await response.json();
    
    // Display architectural elements (YOLO)
    displayArchitecturalElements(results.architectural_elements);
    
    // Display room segments (SAM) 
    displayRoomSegments(results.room_segments);
    
    // Show enhanced analysis
    displayEnhancedRooms(results.enhanced_rooms);
    
    // Show visualizations
    showAnnotatedImage(results.annotated_image_base64);
    showRoomSegmentation(results.sam_visualization);
    
  } catch (error) {
    console.error('AI Detect failed:', error);
  }
}
```

### Display Room Segments
```javascript
function displayRoomSegments(segments) {
  segments.forEach(room => {
    console.log(`Room ${room.room_id}: ${room.estimated_function}`);
    console.log(`  Area: ${room.area_percentage.toFixed(1)}% of floor plan`);
    console.log(`  Doors: ${room.door_count}`);
    console.log(`  Accessibility: ${room.accessibility_score.toFixed(2)}`);
    console.log(`  Safety: ${room.safety_features.emergency_egress}`);
  });
}
```

## 🔧 Configuration Options

### SAM Model Selection
Edit `backend/services/sam_room_segmentation_service.py`:
```python
# Choose model type based on your needs:
# 'vit_h' - Best quality, slowest (2.5GB)
# 'vit_l' - Balanced quality/speed (1.25GB) ← Recommended
# 'vit_b' - Fastest, smallest (375MB)

sam_service = SAMRoomSegmentationService(model_type="vit_l")
```

### YOLO Confidence Tuning
```python
# Lower confidence = more detections (might include false positives)
# Higher confidence = fewer detections (might miss some elements)

# For detailed analysis: 0.3-0.4
# For conservative analysis: 0.5-0.7
confidence = 0.4
```

### SAM Segmentation Parameters
Edit the `SamAutomaticMaskGenerator` settings:
```python
self.mask_generator = SamAutomaticMaskGenerator(
    model=sam,
    points_per_side=16,          # More points = finer segmentation
    pred_iou_thresh=0.7,         # Higher = cleaner segments
    stability_score_thresh=0.8,   # Higher = more stable segments
    min_mask_region_area=1000,   # Minimum room size in pixels
)
```

## 📊 Analysis Features

### 1. Architectural Element Detection
- **Doors & Sliding Doors**: Entry/exit points
- **Windows**: Natural light sources
- **Walls**: Room boundaries and structure
- **Stairs**: Multi-level access
- **Columns**: Structural elements

### 2. Room Segmentation
- **Automatic room detection** using SAM
- **Intelligent boundary detection**
- **Room type classification** (Large Room, Small Room, etc.)
- **Function estimation** (Living Room, Bedroom, etc.)

### 3. Safety Analysis
- **Accessibility scoring** based on door count and room size
- **Emergency egress evaluation** (good/limited/poor)
- **Room connectivity analysis**
- **Exit availability assessment**

### 4. Enhanced Insights
- **Space utilization** percentage
- **Room interconnectivity** mapping
- **Safety feature identification**
- **Optimization suggestions**

## 🚨 Troubleshooting

### Common Issues

#### 1. "SAM not available"
```bash
pip install segment-anything
```

#### 2. "SAM checkpoint not found"
```bash
python download_sam_model.py
```

#### 3. "CUDA out of memory"
```python
# In sam_room_segmentation_service.py, force CPU usage:
self.device = torch.device('cpu')
```

#### 4. "Model loading failed"
- Check if SAM model file exists in `backend/models/`
- Verify file size matches expected size
- Re-download with `python download_sam_model.py`

#### 5. "Poor segmentation quality"
- Try different SAM model (vit_h for best quality)
- Adjust confidence threshold
- Check image quality and resolution

### Debug Endpoints
```bash
# Check overall status
GET /api/model-status

# Test YOLO only
POST /api/analyze-floor-plan?method=enhanced

# Test combined system
POST /api/analyze-floor-plan-with-sam
```

## 🎯 Performance Tips

### 1. Model Selection
- **Production**: Use `vit_l` (good balance)
- **High accuracy**: Use `vit_h` (slower but better)
- **Speed priority**: Use `vit_b` (faster but less accurate)

### 2. Image Optimization
- **Resize large images** to max 2000x2000 pixels
- **Use high contrast** floor plans for better detection
- **Ensure clear architectural lines**

### 3. Hardware Recommendations
- **GPU**: NVIDIA GPU with 4GB+ VRAM for vit_l
- **CPU**: Use CPU mode for systems without GPU
- **RAM**: 8GB+ recommended for smooth operation

## 🔮 Future Enhancements

### Planned Features
1. **Interactive room editing** in frontend
2. **3D room visualization** 
3. **Furniture detection** integration
4. **Building code compliance** checking
5. **Emergency evacuation** route planning

### API Extensions
1. **Batch processing** for multiple floor plans
2. **Progressive loading** for large images
3. **Real-time updates** via WebSocket
4. **Export capabilities** (DXF, PDF)

## 📝 Summary

The SAM + YOLO integration provides:

✅ **Complete floor plan analysis** in one API call
✅ **Architectural element detection** with high precision  
✅ **Intelligent room segmentation** using state-of-the-art AI
✅ **Enhanced safety analysis** for emergency planning
✅ **Ready-to-use visualizations** for frontend display
✅ **Scalable architecture** for future enhancements

Your **AI Detect** button now provides comprehensive floor plan intelligence, combining the best of architectural element detection and semantic room understanding! 🚀 