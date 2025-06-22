"""
Floor Plan Object Detection Module

A standalone, reusable module for detecting architectural elements in floor plan images
using YOLOv8. This module can be easily integrated into any Python project.

Usage:
    from floor_plan_detector import FloorPlanDetector
    
    detector = FloorPlanDetector('path/to/model.pt')
    results = detector.detect_objects('path/to/image.jpg', confidence=0.4)
"""

import torch
import warnings
import os
from ultralytics import YOLO
from PIL import Image
import numpy as np
import pandas as pd
from typing import List, Dict, Union, Optional, Tuple
import cv2

class FloorPlanDetector:
    """
    A class for detecting architectural elements in floor plan images using YOLOv8.
    """
    
    # Default available labels for floor plan detection
    DEFAULT_LABELS = [
        'Column', 'Curtain Wall', 'Dimension', 'Door', 
        'Railing', 'Sliding Door', 'Stair Case', 'Wall', 'Window'
    ]
    
    def __init__(self, model_path: str):
        """
        Initialize the FloorPlanDetector with a trained YOLO model.
        
        Args:
            model_path (str): Path to the trained YOLO model file (.pt)
        """
        self.model_path = model_path
        self.model = None
        self._load_model()
    
    def _setup_torch_safe_loading(self):
        """
        Setup PyTorch safe loading to handle weights_only issue in PyTorch 2.6+
        """
        try:
            # Method 1: Try to import and add actual classes to safe globals
            try:
                from ultralytics.nn.tasks import DetectionModel
                from ultralytics.nn.modules.block import C2f, SPPF
                from ultralytics.nn.modules.conv import Conv
                from ultralytics.nn.modules.head import Detect
                from collections import OrderedDict
                
                # Add actual class objects to safe globals
                torch.serialization.add_safe_globals([
                    DetectionModel, C2f, SPPF, Conv, Detect, OrderedDict,
                    torch._utils._rebuild_tensor_v2,
                    torch.nn.modules.conv.Conv2d,
                    torch.nn.modules.batchnorm.BatchNorm2d,
                    torch.nn.modules.activation.SiLU,
                    torch.nn.modules.pooling.MaxPool2d,
                    torch.nn.modules.upsampling.Upsample
                ])
            except ImportError:
                # If imports fail, use string names as fallback
                torch.serialization.add_safe_globals([
                    'ultralytics.nn.tasks.DetectionModel',
                    'ultralytics.nn.modules.block.C2f',
                    'ultralytics.nn.modules.block.SPPF',
                    'ultralytics.nn.modules.conv.Conv',
                    'ultralytics.nn.modules.head.Detect',
                    'collections.OrderedDict'
                ])
        except Exception as e:
            print(f"Warning: Could not setup safe globals: {e}")
    
    def _load_model(self):
        """
        Load the YOLO model with proper error handling.
        """
        try:
            self._setup_torch_safe_loading()
            
            # Suppress warnings about weights_only
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                self.model = YOLO(self.model_path)
            
            print(f"✅ Floor plan model loaded successfully from {self.model_path}")
            
        except Exception as e:
            print(f"Safe globals approach failed: {e}")
            print("Trying alternative loading method...")
            
            try:
                # Try loading with monkey patching torch.load
                original_load = torch.load
                def patched_load(*args, **kwargs):
                    kwargs['weights_only'] = False
                    return original_load(*args, **kwargs)
                
                torch.load = patched_load
                
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    self.model = YOLO(self.model_path)
                
                # Restore original torch.load
                torch.load = original_load
                
                print(f"✅ Floor plan model loaded successfully using alternative method from {self.model_path}")
                
            except Exception as e2:
                raise RuntimeError(f"Failed to load model: {e2}. Try updating ultralytics: pip install ultralytics --upgrade")
    
    def detect_objects(self, 
                      image_input: Union[str, np.ndarray, Image.Image], 
                      confidence: float = 0.4,
                      selected_labels: Optional[List[str]] = None) -> Dict:
        """
        Detect objects in a floor plan image.
        
        Args:
            image_input: Path to image file, numpy array, or PIL Image
            confidence: Confidence threshold (0.0 to 1.0)
            selected_labels: List of labels to detect. If None, detects all available labels.
        
        Returns:
            Dictionary containing detection results with keys:
            - 'detections': Raw YOLO detection results
            - 'filtered_boxes': Filtered bounding boxes based on selected labels
            - 'object_counts': Dictionary of object counts by label
            - 'annotated_image': Image with detection annotations (numpy array)
        """
        if self.model is None:
            raise RuntimeError("Model not loaded. Please check model path and try again.")
        
        # Handle different input types
        if isinstance(image_input, str):
            image = Image.open(image_input)
        elif isinstance(image_input, np.ndarray):
            image = Image.fromarray(image_input)
        elif isinstance(image_input, Image.Image):
            image = image_input
        else:
            raise ValueError("image_input must be a file path, numpy array, or PIL Image")
        
        # Use all labels if none specified
        if selected_labels is None:
            selected_labels = self.DEFAULT_LABELS
        
        # Run detection
        results = self.model.predict(image, conf=confidence)
        
        # Filter boxes based on selected labels
        filtered_boxes = []
        if results[0].boxes is not None:
            filtered_boxes = [
                box for box in results[0].boxes 
                if self.model.names[int(box.cls)] in selected_labels
            ]
        
        # Update results with filtered boxes
        results[0].boxes = filtered_boxes
        
        # Generate annotated image
        annotated_image = results[0].plot()[:, :, ::-1]  # Convert BGR to RGB
        
        # Count objects
        object_counts = self.count_objects(filtered_boxes)
        
        return {
            'detections': results,
            'filtered_boxes': filtered_boxes,
            'object_counts': object_counts,
            'annotated_image': annotated_image
        }
    
    def count_objects(self, boxes) -> Dict[str, int]:
        """
        Count detected objects by label.
        
        Args:
            boxes: List of detection boxes
        
        Returns:
            Dictionary with object counts by label
        """
        object_counts = {}
        for box in boxes:
            label = self.model.names[int(box.cls)]
            object_counts[label] = object_counts.get(label, 0) + 1
        return object_counts
    
    def get_available_labels(self) -> List[str]:
        """
        Get all available labels that the model can detect.
        
        Returns:
            List of available label names
        """
        if self.model is None:
            return self.DEFAULT_LABELS
        return list(self.model.names.values())
    
    def export_results_to_csv(self, object_counts: Dict[str, int], filename: str = 'detection_results.csv'):
        """
        Export detection results to CSV file.
        
        Args:
            object_counts: Dictionary of object counts
            filename: Output CSV filename
        """
        df = pd.DataFrame(list(object_counts.items()), columns=['Label', 'Count'])
        df.to_csv(filename, index=False)
        print(f"Results exported to {filename}")
    
    def export_results_to_dict(self, object_counts: Dict[str, int]) -> str:
        """
        Export detection results to CSV string format.
        
        Args:
            object_counts: Dictionary of object counts
        
        Returns:
            CSV formatted string
        """
        df = pd.DataFrame(list(object_counts.items()), columns=['Label', 'Count'])
        return df.to_csv(index=False)
    
    def detect_batch(self, 
                    image_paths: List[str], 
                    confidence: float = 0.4,
                    selected_labels: Optional[List[str]] = None) -> List[Dict]:
        """
        Detect objects in multiple images.
        
        Args:
            image_paths: List of paths to image files
            confidence: Confidence threshold
            selected_labels: List of labels to detect
        
        Returns:
            List of detection result dictionaries
        """
        results = []
        for image_path in image_paths:
            try:
                result = self.detect_objects(image_path, confidence, selected_labels)
                result['image_path'] = image_path
                results.append(result)
            except Exception as e:
                print(f"Error processing {image_path}: {e}")
                results.append({'image_path': image_path, 'error': str(e)})
        
        return results


# Utility functions for easy integration
def quick_detect(model_path: str, 
                image_path: str, 
                confidence: float = 0.4,
                selected_labels: Optional[List[str]] = None) -> Dict:
    """
    Quick detection function for single image processing.
    
    Args:
        model_path: Path to YOLO model file
        image_path: Path to image file
        confidence: Confidence threshold
        selected_labels: List of labels to detect
    
    Returns:
        Detection results dictionary
    """
    detector = FloorPlanDetector(model_path)
    return detector.detect_objects(image_path, confidence, selected_labels)


def create_detector_from_existing_project(project_dir: str) -> FloorPlanDetector:
    """
    Create detector from existing floor plan detection project.
    
    Args:
        project_dir: Path to existing project directory
    
    Returns:
        FloorPlanDetector instance
    """
    model_path = os.path.join(project_dir, 'best.pt')
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model file not found at {model_path}")
    
    return FloorPlanDetector(model_path) 