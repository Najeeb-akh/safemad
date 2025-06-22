"""
Floor Plan Detection Helper Functions

Based on the sanatladkat/floor-plan-object-detection repository
Provides utility functions for floor plan analysis and object detection
"""

import streamlit as st
import pandas as pd
from PIL import Image
import numpy as np
import cv2
from typing import Dict, List, Tuple, Any, Optional
import io
import base64

# Object detection labels for floor plans (from the trained model)
FLOOR_PLAN_LABELS = [
    'Column', 'Curtain Wall', 'Dimension', 'Door', 
    'Railing', 'Sliding Door', 'Stair Case', 'Wall', 'Window'
]

def create_detection_summary(object_counts: Dict[str, int]) -> str:
    """
    Create a text summary of detected objects
    
    Args:
        object_counts: Dictionary of object counts by label
        
    Returns:
        Formatted summary string
    """
    if not object_counts:
        return "No objects detected"
    
    total_objects = sum(object_counts.values())
    
    summary_parts = [f"Total objects detected: {total_objects}"]
    
    # Group related objects
    doors = object_counts.get('Door', 0) + object_counts.get('Sliding Door', 0)
    if doors > 0:
        summary_parts.append(f"Doors: {doors}")
    
    windows = object_counts.get('Window', 0)
    if windows > 0:
        summary_parts.append(f"Windows: {windows}")
    
    walls = object_counts.get('Wall', 0)
    if walls > 0:
        summary_parts.append(f"Walls: {walls}")
    
    columns = object_counts.get('Column', 0)
    if columns > 0:
        summary_parts.append(f"Columns: {columns}")
    
    stairs = object_counts.get('Stair Case', 0)
    if stairs > 0:
        summary_parts.append(f"Stairs: {stairs}")
    
    other_objects = []
    for label, count in object_counts.items():
        if label not in ['Door', 'Sliding Door', 'Window', 'Wall', 'Column', 'Stair Case'] and count > 0:
            other_objects.append(f"{label}: {count}")
    
    if other_objects:
        summary_parts.extend(other_objects)
    
    return " | ".join(summary_parts)

def export_results_to_csv(object_counts: Dict[str, int]) -> str:
    """
    Export detection results to CSV format
    
    Args:
        object_counts: Dictionary of object counts
        
    Returns:
        CSV formatted string
    """
    if not object_counts:
        return "Label,Count\nNo objects detected,0"
    
    df = pd.DataFrame(list(object_counts.items()), columns=['Label', 'Count'])
    return df.to_csv(index=False)

def create_detection_dataframe(object_counts: Dict[str, int]) -> pd.DataFrame:
    """
    Create a pandas DataFrame from detection results
    
    Args:
        object_counts: Dictionary of object counts
        
    Returns:
        pandas DataFrame with detection results
    """
    if not object_counts:
        return pd.DataFrame({'Label': ['No objects detected'], 'Count': [0]})
    
    return pd.DataFrame(list(object_counts.items()), columns=['Label', 'Count'])

def annotate_image_with_detections(image: np.ndarray, boxes: List, class_names: Dict, 
                                 confidence_threshold: float = 0.4) -> np.ndarray:
    """
    Annotate image with detection boxes and labels
    
    Args:
        image: Input image as numpy array
        boxes: Detection boxes from YOLO model
        class_names: Dictionary mapping class IDs to names
        confidence_threshold: Minimum confidence for displaying detections
        
    Returns:
        Annotated image as numpy array
    """
    annotated_image = image.copy()
    
    for box in boxes:
        if hasattr(box, 'conf') and box.conf[0] >= confidence_threshold:
            # Get box coordinates
            x1, y1, x2, y2 = box.xyxy[0].cpu().numpy().astype(int)
            confidence = box.conf[0].cpu().numpy()
            class_id = int(box.cls[0].cpu().numpy())
            
            # Get class name
            class_name = class_names.get(class_id, f"Class_{class_id}")
            
            # Draw bounding box
            cv2.rectangle(annotated_image, (x1, y1), (x2, y2), (0, 255, 0), 2)
            
            # Draw label with confidence
            label = f"{class_name}: {confidence:.2f}"
            label_size = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 2)[0]
            
            # Draw label background
            cv2.rectangle(annotated_image, (x1, y1 - label_size[1] - 10), 
                         (x1 + label_size[0], y1), (0, 255, 0), -1)
            
            # Draw label text
            cv2.putText(annotated_image, label, (x1, y1 - 5), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 2)
    
    return annotated_image

def calculate_room_area_estimates(elements: List[Dict[str, Any]], 
                                img_width: int, img_height: int) -> Dict[str, float]:
    """
    Calculate rough room area estimates based on detected elements
    
    Args:
        elements: List of detected architectural elements
        img_width: Image width in pixels
        img_height: Image height in pixels
        
    Returns:
        Dictionary with area estimates
    """
    # This is a simplified estimation - in reality would need more sophisticated analysis
    total_image_area = img_width * img_height
    
    # Find walls to estimate room boundaries
    walls = [e for e in elements if e.get('type') == 'Wall']
    
    if not walls:
        return {'estimated_total_area': 0.0, 'coverage_percentage': 0.0}
    
    # Calculate total wall area
    wall_area = sum(e.get('area', 0) for e in walls)
    
    # Rough estimate: assume walls represent about 10-15% of total floor space
    estimated_floor_area = wall_area * 8  # Rough multiplier
    coverage_percentage = min(100.0, (estimated_floor_area / total_image_area) * 100)
    
    return {
        'estimated_total_area': estimated_floor_area,
        'coverage_percentage': coverage_percentage,
        'wall_area': wall_area,
        'total_elements': len(elements)
    }

def classify_space_type(elements: List[Dict[str, Any]]) -> Tuple[str, float]:
    """
    Classify the type of space based on detected elements
    
    Args:
        elements: List of detected architectural elements
        
    Returns:
        Tuple of (space_type, confidence_score)
    """
    if not elements:
        return ("Unknown", 0.0)
    
    # Count different types of elements
    element_counts = {}
    for element in elements:
        elem_type = element.get('type', 'Unknown')
        element_counts[elem_type] = element_counts.get(elem_type, 0) + 1
    
    doors = element_counts.get('Door', 0) + element_counts.get('Sliding Door', 0)
    windows = element_counts.get('Window', 0)
    stairs = element_counts.get('Stair Case', 0)
    walls = element_counts.get('Wall', 0)
    columns = element_counts.get('Column', 0)
    
    # Classification logic based on element combinations
    if stairs > 0:
        if doors > 2 and windows > 1:
            return ("Multi-level Residential", 0.8)
        else:
            return ("Building with Stairs", 0.7)
    
    if columns > 2 and walls > 3:
        return ("Open Office/Commercial", 0.75)
    
    if doors >= 3 and windows >= 2:
        return ("Residential Apartment", 0.8)
    
    if doors == 1 and windows >= 1:
        return ("Single Room", 0.7)
    
    if walls > 4 and doors >= 2:
        return ("Multi-room Layout", 0.75)
    
    return ("General Floor Plan", 0.6)

def generate_layout_insights(elements: List[Dict[str, Any]], 
                           img_width: int, img_height: int) -> Dict[str, Any]:
    """
    Generate insights about the floor plan layout
    
    Args:
        elements: List of detected architectural elements
        img_width: Image width in pixels
        img_height: Image height in pixels
        
    Returns:
        Dictionary with layout insights
    """
    if not elements:
        return {"insights": ["No architectural elements detected"]}
    
    insights = []
    
    # Count elements
    doors = len([e for e in elements if e.get('type') in ['Door', 'Sliding Door']])
    windows = len([e for e in elements if e.get('type') == 'Window'])
    walls = len([e for e in elements if e.get('type') == 'Wall'])
    stairs = len([e for e in elements if e.get('type') == 'Stair Case'])
    columns = len([e for e in elements if e.get('type') == 'Column'])
    
    # Generate insights based on element analysis
    if doors == 0:
        insights.append("⚠️ No doors detected - may need manual verification")
    elif doors == 1:
        insights.append("🚪 Single entrance/exit detected")
    else:
        insights.append(f"🚪 Multiple access points: {doors} doors detected")
    
    if windows == 0:
        insights.append("⚠️ No windows detected - interior space or basement level")
    elif windows < 3:
        insights.append(f"🪟 Limited natural light: {windows} windows")
    else:
        insights.append(f"🪟 Good natural light: {windows} windows detected")
    
    if stairs > 0:
        insights.append(f"🏗️ Multi-level structure: {stairs} staircase(s) detected")
    
    if columns > 0:
        insights.append(f"🏛️ Structural columns detected: {columns} columns")
    
    if walls > 6:
        insights.append("🏠 Complex layout with multiple rooms/spaces")
    elif walls < 3:
        insights.append("📐 Open plan or simple layout")
    
    # Space classification
    space_type, confidence = classify_space_type(elements)
    insights.append(f"🏷️ Classified as: {space_type} (confidence: {confidence:.1%})")
    
    # Area estimation
    area_info = calculate_room_area_estimates(elements, img_width, img_height)
    if area_info['coverage_percentage'] > 0:
        insights.append(f"📏 Estimated coverage: {area_info['coverage_percentage']:.1f}% of image")
    
    return {
        "insights": insights,
        "space_type": space_type,
        "confidence": confidence,
        "element_summary": {
            "doors": doors,
            "windows": windows,
            "walls": walls,
            "stairs": stairs,
            "columns": columns
        },
        "area_estimates": area_info
    }

def convert_image_to_base64(image: np.ndarray) -> str:
    """
    Convert numpy image array to base64 string for web display
    
    Args:
        image: Image as numpy array
        
    Returns:
        Base64 encoded image string
    """
    # Convert from RGB to BGR if needed (OpenCV uses BGR)
    if len(image.shape) == 3 and image.shape[2] == 3:
        image_pil = Image.fromarray(image)
    else:
        image_pil = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    
    # Convert to bytes
    buffer = io.BytesIO()
    image_pil.save(buffer, format='PNG')
    img_bytes = buffer.getvalue()
    
    # Encode to base64
    img_base64 = base64.b64encode(img_bytes).decode()
    return f"data:image/png;base64,{img_base64}"

def validate_floor_plan_image(image_bytes: bytes) -> Tuple[bool, str]:
    """
    Validate if uploaded image is suitable for floor plan detection
    
    Args:
        image_bytes: Image data as bytes
        
    Returns:
        Tuple of (is_valid, message)
    """
    try:
        image = Image.open(io.BytesIO(image_bytes))
        width, height = image.size
        
        # Check image dimensions
        if width < 100 or height < 100:
            return False, "Image too small. Please upload an image at least 100x100 pixels."
        
        if width > 4000 or height > 4000:
            return False, "Image too large. Please upload an image smaller than 4000x4000 pixels."
        
        # Check aspect ratio
        aspect_ratio = max(width, height) / min(width, height)
        if aspect_ratio > 10:
            return False, "Image aspect ratio too extreme. Please use a more balanced image."
        
        # Check if image has multiple channels (color)
        if image.mode not in ['RGB', 'RGBA', 'L']:
            return False, "Unsupported image format. Please use RGB, RGBA, or grayscale images."
        
        return True, "Image is valid for floor plan detection."
        
    except Exception as e:
        return False, f"Error validating image: {str(e)}"

def optimize_detection_confidence(elements: List[Dict[str, Any]], 
                                target_elements: int = 10) -> float:
    """
    Suggest optimal confidence threshold based on detection results
    
    Args:
        elements: List of detected elements with confidence scores
        target_elements: Target number of elements to detect
        
    Returns:
        Suggested confidence threshold
    """
    if not elements:
        return 0.3  # Default low confidence if no detections
    
    # Get all confidence scores
    confidences = [e.get('confidence', 0.5) for e in elements if 'confidence' in e]
    
    if not confidences:
        return 0.4  # Default confidence
    
    confidences.sort(reverse=True)
    
    # If we have fewer elements than target, suggest lower confidence
    if len(confidences) < target_elements:
        return max(0.2, min(confidences) - 0.1)
    
    # If we have too many elements, suggest higher confidence
    if len(confidences) > target_elements * 1.5:
        return min(0.8, confidences[target_elements] + 0.1)
    
    # Otherwise, use median confidence
    return confidences[len(confidences) // 2] 