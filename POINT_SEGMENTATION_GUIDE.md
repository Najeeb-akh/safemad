# Point-Based Room Segmentation Guide 🎯

## Overview

This guide explains how to use the new **point-based room segmentation** feature that mimics [EfficientViTSAM's `--mode point`](https://github.com/jahongir7174/EfficientViTSAM/tree/master) functionality. 

Just like EfficientViTSAM allows you to run:
```bash
python main.py --image_path ./demo/cat.jpg --output_path ./demo/cat.png --mode point
```

Our implementation allows you to click on specific points in a floor plan and get precise room segmentation masks.

## 🚀 Quick Start

### Method 1: API Endpoint (Recommended)

**Endpoint:** `POST /segment-room-with-points`

```javascript
// Frontend JavaScript example
async function segmentRoomWithPoints(imageFile, clickCoordinates) {
    const formData = new FormData();
    formData.append('file', imageFile);
    formData.append('point_coords', JSON.stringify(clickCoordinates));
    formData.append('multimask_output', true);
    
    const response = await fetch('/api/segment-room-with-points', {
        method: 'POST',
        body: formData
    });
    
    const result = await response.json();
    return result;
}

// Usage: User clicks on image at coordinates [400, 300]
const result = await segmentRoomWithPoints(imageFile, [[400, 300]]);
```

### Method 2: Direct Python Script

```bash
# Test with a single point
python test_point_segmentation.py --image_path demo/floorplan.jpg --points "[[400,300]]"

# Test with multiple points
python test_point_segmentation.py --image_path demo/floorplan.jpg --points "[[400,300],[450,350]]"

# Test with positive and negative points
python test_point_segmentation.py --image_path demo/floorplan.jpg --points "[[400,300],[200,200]]" --labels "[1,0]"
```

## 📍 How Point Coordinates Work

### Coordinate System
- **Origin (0,0)**: Top-left corner of the image
- **X-axis**: Increases from left to right
- **Y-axis**: Increases from top to bottom
- **Format**: `[x, y]` where both are integers

### Point Labels
- **1**: Positive point (include this area in the mask)
- **0**: Negative point (exclude this area from the mask)
- **Default**: All points are positive if no labels provided

### Examples

```json
// Single point in the center of a room
{
    "point_coords": [[400, 300]],
    "point_labels": null  // Auto-positive
}

// Multiple positive points in the same room
{
    "point_coords": [[400, 300], [450, 350], [380, 280]], 
    "point_labels": [1, 1, 1]
}

// Mixed positive and negative points
{
    "point_coords": [[400, 300], [100, 100]],
    "point_labels": [1, 0]  // Include room at 400,300 but exclude area at 100,100
}
```

## 🛠️ API Usage

### Request Format

**Endpoint:** `POST /api/segment-room-with-points`

**Parameters:**
- `file` (File): Floor plan image
- `point_coords` (String): JSON string of coordinates `"[[x1,y1],[x2,y2],...]"`
- `point_labels` (String, Optional): JSON string of labels `"[1,1,0,...]"`
- `multimask_output` (Boolean): Whether to return multiple mask options

**Example with cURL:**
```bash
curl -X POST "http://localhost:8000/api/segment-room-with-points" \
  -F "file=@floorplan.jpg" \
  -F "point_coords=[[400,300],[450,350]]" \
  -F "point_labels=[1,1]" \
  -F "multimask_output=true"
```

### Response Format

```json
{
    "masks": [
        {
            "mask_id": 0,
            "score": 0.995,
            "area": 15000,
            "area_percentage": 12.5,
            "bbox": {"x": 350, "y": 250, "width": 200, "height": 150},
            "centroid": {"x": 425, "y": 325},
            "perimeter": 800,
            "input_points": [[400, 300], [450, 350]],
            "input_labels": [1, 1]
        }
    ],
    "total_masks": 1,
    "segmentation_method": "sam_point_prompt",
    "visualization": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
    "best_mask": { /* Best scoring mask */ },
    "metadata": {
        "sam_model": "vit_l",
        "device": "cuda",
        "multimask_output": true,
        "point_count": 2
    }
}
```

## 🎨 Frontend Integration

### HTML Interface

```html
<div class="point-segmentation-container">
    <canvas id="floorPlanCanvas" width="800" height="600"></canvas>
    <input type="file" id="imageInput" accept="image/*">
    <button id="segmentBtn">Segment Room</button>
    <div id="results"></div>
</div>
```

### JavaScript Implementation

```javascript
class PointSegmentation {
    constructor(canvasId) {
        this.canvas = document.getElementById(canvasId);
        this.ctx = this.canvas.getContext('2d');
        this.points = [];
        this.image = null;
        
        this.canvas.addEventListener('click', this.onCanvasClick.bind(this));
    }
    
    onCanvasClick(event) {
        const rect = this.canvas.getBoundingClientRect();
        const x = Math.round(event.clientX - rect.left);
        const y = Math.round(event.clientY - rect.top);
        
        this.points.push([x, y]);
        this.drawPoint(x, y, this.points.length);
        
        console.log(`Added point ${this.points.length}: [${x}, ${y}]`);
    }
    
    drawPoint(x, y, number) {
        this.ctx.fillStyle = 'green';
        this.ctx.beginPath();
        this.ctx.arc(x, y, 8, 0, 2 * Math.PI);
        this.ctx.fill();
        
        // Add number label
        this.ctx.fillStyle = 'white';
        this.ctx.font = '12px Arial';
        this.ctx.textAlign = 'center';
        this.ctx.fillText(number.toString(), x, y + 4);
    }
    
    async segmentRoom(imageFile) {
        if (this.points.length === 0) {
            alert('Please click on the image to select points first!');
            return;
        }
        
        const formData = new FormData();
        formData.append('file', imageFile);
        formData.append('point_coords', JSON.stringify(this.points));
        formData.append('multimask_output', true);
        
        try {
            const response = await fetch('/api/segment-room-with-points', {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            this.displayResults(result);
            
        } catch (error) {
            console.error('Segmentation failed:', error);
        }
    }
    
    displayResults(result) {
        const resultsDiv = document.getElementById('results');
        
        if (result.visualization) {
            const img = document.createElement('img');
            img.src = result.visualization;
            img.style.maxWidth = '100%';
            resultsDiv.appendChild(img);
        }
        
        // Show mask information
        result.masks.forEach((mask, i) => {
            const maskInfo = document.createElement('div');
            maskInfo.innerHTML = `
                <h4>Mask ${i + 1}</h4>
                <p>Score: ${mask.score.toFixed(3)}</p>
                <p>Area: ${mask.area_percentage.toFixed(1)}% of image</p>
                <p>Center: (${mask.centroid.x}, ${mask.centroid.y})</p>
            `;
            resultsDiv.appendChild(maskInfo);
        });
    }
    
    clearPoints() {
        this.points = [];
        this.redrawCanvas();
    }
}

// Initialize
const segmentation = new PointSegmentation('floorPlanCanvas');

document.getElementById('segmentBtn').addEventListener('click', () => {
    const fileInput = document.getElementById('imageInput');
    if (fileInput.files[0]) {
        segmentation.segmentRoom(fileInput.files[0]);
    }
});
```

## 🔧 Advanced Usage

### Multiple Room Segmentation

```javascript
// Segment different rooms with different point sets
const roomSegments = await Promise.all([
    segmentRoomWithPoints(image, [[400, 300]]),  // Living room
    segmentRoomWithPoints(image, [[600, 200]]),  // Kitchen  
    segmentRoomWithPoints(image, [[200, 400]])   // Bedroom
]);
```

### Refinement with Negative Points

```javascript
// First, get initial segmentation
let result = await segmentRoomWithPoints(image, [[400, 300]]);

// If the mask includes unwanted areas, add negative points
result = await segmentRoomWithPoints(image, [
    [400, 300],  // Original positive point
    [350, 250]   // Negative point to exclude this area
], [1, 0]);
```

### Batch Processing

```javascript
async function processMultipleImages(images, pointSets) {
    const results = [];
    
    for (let i = 0; i < images.length; i++) {
        const result = await segmentRoomWithPoints(images[i], pointSets[i]);
        results.push(result);
    }
    
    return results;
}
```

## 📊 Understanding Results

### Mask Quality Scores
- **0.9 - 1.0**: Excellent segmentation
- **0.8 - 0.9**: Good segmentation
- **0.7 - 0.8**: Fair segmentation
- **< 0.7**: Poor segmentation (consider adding more points)

### Visualization Features
- **Green stars**: Positive points (include)
- **Red stars**: Negative points (exclude)
- **Colored overlays**: Segmentation masks
- **Multiple panels**: Original + mask options

## 🚨 Troubleshooting

### Common Issues

#### 1. "SAM service not available"
```bash
# Install SAM
pip install segment-anything

# Download model
python download_sam_model.py
```

#### 2. Poor segmentation quality
- **Add more points** in the target area
- **Use negative points** to exclude unwanted areas
- **Check point coordinates** are within image bounds
- **Try different points** in the room center

#### 3. Points not registering correctly
```javascript
// Ensure coordinates are relative to image, not canvas
const scaleX = image.width / canvas.width;
const scaleY = image.height / canvas.height;
const actualX = Math.round(clickX * scaleX);
const actualY = Math.round(clickY * scaleY);
```

#### 4. API errors
```bash
# Check server logs
tail -f backend.log

# Verify file format
file your_image.jpg  # Should show image format

# Test with curl
curl -F "file=@test.jpg" -F "point_coords=[[400,300]]" localhost:8000/api/segment-room-with-points
```

## 🆚 EfficientViTSAM Comparison

| Feature | EfficientViTSAM | Our Implementation |
|---------|-----------------|-------------------|
| Point-based segmentation | ✅ `--mode point` | ✅ API endpoint |
| Multiple masks | ✅ | ✅ |
| Visualization | ✅ | ✅ Enhanced |
| Negative points | ✅ | ✅ |
| Batch processing | ❌ | ✅ |
| Web interface | ❌ | ✅ |
| REST API | ❌ | ✅ |

## 📝 Examples

### Example 1: Living Room Segmentation
```bash
python test_point_segmentation.py \
  --image_path floorplan.jpg \
  --points "[[500,300]]"
```

### Example 2: Kitchen with Exclusion
```bash
python test_point_segmentation.py \
  --image_path floorplan.jpg \
  --points "[[600,200],[550,150]]" \
  --labels "[1,0]"
```

### Example 3: Multiple Rooms
```bash
# Process each room separately for better accuracy
python test_point_segmentation.py --image_path floorplan.jpg --points "[[400,300]]"  # Living room
python test_point_segmentation.py --image_path floorplan.jpg --points "[[600,200]]"  # Kitchen
python test_point_segmentation.py --image_path floorplan.jpg --points "[[200,400]]"  # Bedroom
```

## 🔗 Related Documentation

- [SAM Integration Guide](SAM_INTEGRATION_GUIDE.md)
- [Enhanced Floor Plan Service](ENHANCED_MODEL_INTEGRATION.md)
- [Original EfficientViTSAM](https://github.com/jahongir7174/EfficientViTSAM)

## 🎉 Success! 

You now have EfficientViTSAM-style point-based segmentation integrated into your floor plan system! Users can click on any area of a floor plan and get precise room segmentation masks, just like the original project demonstrates with `--mode point`. 