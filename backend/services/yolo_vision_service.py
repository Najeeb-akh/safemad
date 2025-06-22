import cv2
import numpy as np
import matplotlib.pyplot as plt
from sklearn.cluster import DBSCAN
import json
import os
import io
from typing import List, Dict, Any, Optional
from PIL import Image
import torch
from ultralytics import YOLO
import logging

# Set up logging
logging.getLogger('ultralytics').setLevel(logging.WARNING)

class YOLOFloorPlanAnalyzer:
    def __init__(self, debug=False):
        self.debug = debug
        self.results = {}
        self.yolo_model = None
        self._initialize_yolo()
        
    def _initialize_yolo(self):
        """Initialize YOLO model for object detection"""
        try:
            # Try to load a pre-trained YOLO model
            # You can use yolov8n.pt (nano), yolov8s.pt (small), yolov8m.pt (medium), etc.
            self.yolo_model = YOLO('yolov8n.pt')  # This will download if not present
            print("✅ YOLO model initialized successfully")
        except Exception as e:
            print(f"⚠️ Could not initialize YOLO model: {e}")
            print("📥 Downloading YOLOv8 model...")
            try:
                self.yolo_model = YOLO('yolov8n.pt')
                print("✅ YOLO model downloaded and initialized")
            except Exception as e2:
                print(f"❌ Failed to initialize YOLO: {e2}")
                self.yolo_model = None
    
    def load_and_preprocess(self, image_bytes: bytes):
        """Load and preprocess the image from bytes"""
        print("Loading and preprocessing image...")
        
        # Convert bytes to numpy array
        nparr = np.frombuffer(image_bytes, np.uint8)
        self.original = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if self.original is None:
            raise ValueError("Could not decode image from bytes")
            
        # Get image dimensions
        self.img_height, self.img_width = self.original.shape[:2]
        print(f"Image dimensions: {self.img_width}x{self.img_height}")
        
        # Convert to grayscale
        gray = cv2.cvtColor(self.original, cv2.COLOR_BGR2GRAY)
        
        # Apply different thresholding techniques
        # Method 1: Simple threshold
        _, thresh_simple = cv2.threshold(gray, 127, 255, cv2.THRESH_BINARY_INV)
        
        # Method 2: Adaptive threshold (usually better for floor plans)
        thresh_adaptive = cv2.adaptiveThreshold(
            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
            cv2.THRESH_BINARY_INV, 11, 2
        )
        
        # Method 3: Otsu's threshold
        _, thresh_otsu = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
        
        # Choose adaptive threshold (usually works best for floor plans)
        self.binary = thresh_adaptive
        
        # Clean up noise
        kernel = np.ones((2, 2), np.uint8)
        self.binary = cv2.morphologyEx(self.binary, cv2.MORPH_CLOSE, kernel)
        self.binary = cv2.morphologyEx(self.binary, cv2.MORPH_OPEN, kernel)
        
        print("✅ Image preprocessing completed")
        return self.binary
    
    def yolo_object_detection(self):
        """Use YOLO to detect objects in the floor plan"""
        print("Running YOLO object detection...")
        
        if self.yolo_model is None:
            print("⚠️ YOLO model not available, skipping YOLO detection")
            return []
        
        try:
            # Run YOLO inference
            results = self.yolo_model(self.original, verbose=False)
            
            detected_objects = []
            
            for result in results:
                boxes = result.boxes
                if boxes is not None:
                    for box in boxes:
                        # Get box coordinates
                        x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                        confidence = box.conf[0].cpu().numpy()
                        class_id = int(box.cls[0].cpu().numpy())
                        class_name = self.yolo_model.names[class_id]
                        
                        # Filter for relevant objects (furniture, fixtures, etc.)
                        relevant_objects = [
                            'chair', 'couch', 'bed', 'dining table', 'toilet', 'sink', 
                            'refrigerator', 'oven', 'microwave', 'tv', 'laptop', 
                            'mouse', 'keyboard', 'book', 'clock', 'vase', 'scissors',
                            'teddy bear', 'hair drier', 'toothbrush', 'bathtub'
                        ]
                        
                        if class_name in relevant_objects and confidence > 0.3:
                            center_x = int((x1 + x2) / 2)
                            center_y = int((y1 + y2) / 2)
                            width = int(x2 - x1)
                            height = int(y2 - y1)
                            
                            detected_objects.append({
                                'class_name': class_name,
                                'confidence': float(confidence),
                                'bbox': [int(x1), int(y1), int(x2), int(y2)],
                                'center': [center_x, center_y],
                                'width': width,
                                'height': height,
                                'area': width * height
                            })
            
            print(f"✅ YOLO detected {len(detected_objects)} relevant objects")
            return detected_objects
            
        except Exception as e:
            print(f"❌ YOLO detection failed: {e}")
            return []
    
    def detect_walls_and_structure(self):
        """Detect walls and structural elements using computer vision"""
        print("Detecting walls and structure...")
        
        # Create kernels for line detection
        # Horizontal lines (walls)
        horizontal_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (40, 1))
        horizontal_lines = cv2.morphologyEx(self.binary, cv2.MORPH_OPEN, horizontal_kernel)
        
        # Vertical lines (walls)
        vertical_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, 40))
        vertical_lines = cv2.morphologyEx(self.binary, cv2.MORPH_OPEN, vertical_kernel)
        
        # Combine to get all walls
        self.walls = cv2.bitwise_or(horizontal_lines, vertical_lines)
        
        print("✅ Wall detection completed")
        return self.walls
    
    def detect_rooms_with_cv(self):
        """Detect rooms using computer vision contour analysis"""
        print("Detecting rooms using computer vision...")
        
        # Create mask without walls to find enclosed spaces
        room_mask = cv2.bitwise_not(self.walls)
        
        # Fill small holes with more aggressive closing
        kernel_small = np.ones((3, 3), np.uint8)
        kernel_large = np.ones((7, 7), np.uint8)
        
        # Multiple passes of morphological operations
        room_mask = cv2.morphologyEx(room_mask, cv2.MORPH_CLOSE, kernel_small)
        room_mask = cv2.morphologyEx(room_mask, cv2.MORPH_CLOSE, kernel_large)
        room_mask = cv2.morphologyEx(room_mask, cv2.MORPH_OPEN, kernel_small)
        
        # Find contours (potential rooms)
        contours, hierarchy = cv2.findContours(
            room_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        
        rooms = []
        
        # More lenient area thresholds for architectural drawings
        total_area = self.img_width * self.img_height
        min_area = total_area * 0.001  # 0.1% of image (more lenient)
        max_area = total_area * 0.6    # 60% of image (more lenient)
        
        print(f"   Total image area: {total_area}")
        print(f"   Room area range: {min_area:.0f} - {max_area:.0f} pixels")
        print(f"   Found {len(contours)} potential contours")
        
        for i, contour in enumerate(contours):
            area = cv2.contourArea(contour)
            
            if min_area < area < max_area:
                # Get bounding rectangle
                x, y, w, h = cv2.boundingRect(contour)
                center = (x + w//2, y + h//2)
                
                # Calculate properties
                aspect_ratio = w / h if h > 0 else 0
                
                # Additional filtering for reasonable room shapes
                if aspect_ratio > 0.1 and aspect_ratio < 10:  # Not too thin
                    room_data = {
                        'id': i,
                        'center': center,
                        'bbox': (x, y, w, h),
                        'area': area,
                        'aspect_ratio': aspect_ratio,
                        'contour_points': len(contour),
                        'detection_method': 'computer_vision'
                    }
                    
                    rooms.append(room_data)
                    print(f"   Room {i}: area={area:.0f}, ratio={aspect_ratio:.2f}, bbox={w}x{h}")
        
        print(f"✅ Computer vision detected {len(rooms)} potential rooms")
        return rooms
    
    def classify_rooms_with_yolo_context(self, cv_rooms, yolo_objects):
        """Classify rooms using YOLO object context"""
        print("Classifying rooms using YOLO object context...")
        
        classified_rooms = []
        
        for room in cv_rooms:
            x, y, w, h = room['bbox']
            room_center = room['center']
            
            # Find YOLO objects within this room
            objects_in_room = []
            for obj in yolo_objects:
                obj_center = obj['center']
                # Check if object center is within room bounds
                if (x <= obj_center[0] <= x + w and 
                    y <= obj_center[1] <= y + h):
                    objects_in_room.append(obj)
            
            # Classify room based on objects found
            room_type = self._classify_room_by_objects(objects_in_room, room['area'], room['aspect_ratio'])
            
            # Generate room description
            description = self._generate_room_description(room_type, room, objects_in_room)
            
            classified_room = {
                'room_id': room['id'],
                'default_name': room_type,
                'boundaries': {
                    'x': x,
                    'y': y,
                    'width': w,
                    'height': h
                },
                'center': room_center,
                'area_pixels': room['area'],
                'aspect_ratio': room['aspect_ratio'],
                'confidence': self._calculate_room_confidence(objects_in_room, room_type),
                'objects_detected': objects_in_room,
                'description': description,
                'detection_method': 'yolo_enhanced_cv',
                'estimated_dimensions': self._estimate_room_dimensions(w, h, room['area'])
            }
            
            classified_rooms.append(classified_room)
        
        print(f"✅ Classified {len(classified_rooms)} rooms using YOLO context")
        return classified_rooms
    
    def _classify_room_by_objects(self, objects, area, aspect_ratio):
        """Classify room type based on detected objects"""
        if not objects:
            return self._classify_room_basic(area, aspect_ratio)
        
        # Count object types
        object_counts = {}
        for obj in objects:
            obj_type = obj['class_name']
            object_counts[obj_type] = object_counts.get(obj_type, 0) + 1
        
        # Classification logic based on objects
        if any(obj in object_counts for obj in ['toilet', 'sink', 'bathtub']):
            return 'Bathroom'
        elif any(obj in object_counts for obj in ['bed', 'teddy bear']):
            return 'Bedroom'
        elif any(obj in object_counts for obj in ['refrigerator', 'oven', 'microwave', 'sink']):
            return 'Kitchen'
        elif any(obj in object_counts for obj in ['couch', 'tv', 'dining table']):
            if 'dining table' in object_counts:
                return 'Dining Room'
            else:
                return 'Living Room'
        elif any(obj in object_counts for obj in ['laptop', 'mouse', 'keyboard']):
            return 'Office'
        else:
            return self._classify_room_basic(area, aspect_ratio)
    
    def _classify_room_basic(self, area, aspect_ratio):
        """Basic room classification based on size and shape"""
        # Calculate relative area compared to total image
        total_area = self.img_width * self.img_height
        relative_area = area / total_area
        
        if relative_area < 0.02:  # Very small
            return 'Closet' if aspect_ratio < 2.0 else 'Hallway'
        elif relative_area < 0.05:  # Small
            return 'Bathroom' if aspect_ratio < 1.8 else 'Bedroom'
        elif relative_area < 0.15:  # Medium
            if aspect_ratio > 3.0:
                return 'Hallway'
            else:
                return 'Bedroom'
        elif relative_area < 0.25:  # Large
            return 'Living Room' if aspect_ratio < 2.0 else 'Kitchen'
        else:  # Very large
            return 'Large Room'
    
    def _calculate_room_confidence(self, objects, room_type):
        """Calculate confidence score based on object detection"""
        base_confidence = 0.6
        
        if not objects:
            return base_confidence
        
        # Boost confidence based on relevant objects
        confidence_boost = 0
        room_type_lower = room_type.lower()
        
        for obj in objects:
            obj_confidence = obj['confidence']
            obj_name = obj['class_name'].lower()
            
            # Room-specific object relevance
            if room_type_lower == 'bathroom' and obj_name in ['toilet', 'sink', 'bathtub']:
                confidence_boost += obj_confidence * 0.3
            elif room_type_lower == 'kitchen' and obj_name in ['refrigerator', 'oven', 'microwave']:
                confidence_boost += obj_confidence * 0.3
            elif room_type_lower == 'bedroom' and obj_name in ['bed']:
                confidence_boost += obj_confidence * 0.4
            elif room_type_lower == 'living room' and obj_name in ['couch', 'tv']:
                confidence_boost += obj_confidence * 0.3
            else:
                confidence_boost += obj_confidence * 0.1
        
        return min(0.95, base_confidence + confidence_boost)
    
    def _generate_room_description(self, room_type, room_data, objects):
        """Generate detailed room description"""
        x, y, w, h = room_data['bbox']
        
        # Determine location on floor plan
        h_pos = "left" if x < self.img_width/3 else "right" if x > 2*self.img_width/3 else "center"
        v_pos = "top" if y < self.img_height/3 else "bottom" if y > 2*self.img_height/3 else "middle"
        
        location = f"{v_pos}-{h_pos} of the floor plan"
        
        # Base description
        description = f"Located in the {location}. "
        
        # Add object-based context
        if objects:
            object_names = [obj['class_name'] for obj in objects]
            unique_objects = list(set(object_names))
            
            if len(unique_objects) == 1:
                description += f"Contains a {unique_objects[0]}. "
            elif len(unique_objects) == 2:
                description += f"Contains a {unique_objects[0]} and a {unique_objects[1]}. "
            else:
                description += f"Contains multiple items including {', '.join(unique_objects[:3])}. "
        
        # Add room-specific safety considerations
        room_type_lower = room_type.lower()
        if 'bathroom' in room_type_lower:
            description += "Check for proper ventilation and slip-resistant surfaces."
        elif 'kitchen' in room_type_lower:
            description += "Evaluate fire safety equipment and gas line connections."
        elif 'bedroom' in room_type_lower:
            description += "Ensure adequate emergency exit access and window safety."
        elif 'living' in room_type_lower:
            description += "Check furniture placement for clear evacuation paths."
        
        return description
    
    def _estimate_room_dimensions(self, width_px, height_px, area_px):
        """Estimate real-world room dimensions"""
        # Rough conversion factor (this would need calibration based on floor plan scale)
        # Assuming 1 pixel ≈ 2cm (this is very rough and should be calibrated)
        px_to_cm = 2.0
        
        width_cm = int(width_px * px_to_cm)
        height_cm = int(height_px * px_to_cm)
        area_sqm = round((area_px * px_to_cm * px_to_cm) / 10000, 2)
        
        return {
            'width_cm': width_cm,
            'length_cm': height_cm,
            'area_sqm': max(0.1, area_sqm),  # Minimum 0.1 sqm
            'estimated_ceiling_height_cm': 250
        }
    
    def detect_doors_and_windows(self):
        """Detect doors and windows using edge detection"""
        print("Detecting doors and windows...")
        
        # Use edge detection to find openings
        edges = cv2.Canny(self.binary, 50, 150)
        
        # Find lines using HoughLinesP with more conservative parameters
        lines = cv2.HoughLinesP(edges, 1, np.pi/180, threshold=80,  # Higher threshold
                               minLineLength=30, maxLineGap=10)     # Longer minimum length
        
        doors_windows = []
        
        if lines is not None:
            print(f"   Found {len(lines)} potential lines")
            
            # Calculate reasonable size thresholds
            min_length = min(self.img_width, self.img_height) * 0.03  # 3% of smaller dimension
            max_length = min(self.img_width, self.img_height) * 0.12  # 12% of smaller dimension
            
            print(f"   Door/window length range: {min_length:.0f} - {max_length:.0f} pixels")
            
            valid_lines = 0
            for line in lines:
                x1, y1, x2, y2 = line[0]
                length = np.sqrt((x2-x1)**2 + (y2-y1)**2)
                
                # More strict length filtering
                if min_length < length < max_length:
                    center = ((x1+x2)//2, (y1+y2)//2)
                    
                    # Check if line is reasonably horizontal or vertical (doors/windows are usually aligned)
                    dx = abs(x2 - x1)
                    dy = abs(y2 - y1)
                    
                    # Calculate angle - doors/windows are usually horizontal or vertical
                    if dx > 0:
                        angle = np.arctan(dy / dx) * 180 / np.pi
                    else:
                        angle = 90
                    
                    # Accept lines that are roughly horizontal (0-15°) or vertical (75-90°)
                    is_aligned = (angle <= 15) or (angle >= 75)
                    
                    if is_aligned:
                        # Simple classification based on length and orientation
                        if dx > dy:  # More horizontal
                            element_type = 'door' if length > (min_length + max_length) / 2 else 'window'
                        else:  # More vertical
                            element_type = 'door' if length > (min_length + max_length) / 1.5 else 'window'
                        
                        doors_windows.append({
                            'type': element_type,
                            'position': {'x': center[0], 'y': center[1]},
                            'line': (x1, y1, x2, y2),
                            'width': int(length),
                            'height': 5,  # Approximate thickness
                            'confidence': 0.7,
                            'angle': angle,
                            'orientation': 'horizontal' if dx > dy else 'vertical'
                        })
                        valid_lines += 1
            
            print(f"   Filtered to {valid_lines} valid door/window candidates")
        
        # Remove duplicates (lines that are very close to each other)
        filtered_doors_windows = self._remove_duplicate_lines(doors_windows)
        
        print(f"✅ Detected {len(filtered_doors_windows)} doors and windows after deduplication")
        return filtered_doors_windows
    
    def _remove_duplicate_lines(self, doors_windows):
        """Remove duplicate door/window detections that are too close to each other"""
        if len(doors_windows) <= 1:
            return doors_windows
        
        filtered = []
        min_distance = min(self.img_width, self.img_height) * 0.05  # 5% of image size
        
        for dw in doors_windows:
            pos = dw['position']
            is_duplicate = False
            
            for existing in filtered:
                existing_pos = existing['position']
                distance = np.sqrt((pos['x'] - existing_pos['x'])**2 + 
                                 (pos['y'] - existing_pos['y'])**2)
                
                if distance < min_distance:
                    is_duplicate = True
                    break
            
            if not is_duplicate:
                filtered.append(dw)
        
        return filtered
    
    async def analyze_floor_plan(self, image_bytes: bytes) -> Dict[str, Any]:
        """Main method to analyze the entire floor plan using YOLO + CV"""
        try:
            print("🚀 Starting YOLO-enhanced floor plan analysis...")
            
            # Step 1: Preprocess image
            self.load_and_preprocess(image_bytes)
            
            # Step 1.5: Analyze image characteristics
            image_analysis = self.analyze_image_characteristics()
            
            # Step 2: YOLO object detection
            yolo_objects = self.yolo_object_detection()
            
            # Step 3: Detect structure using computer vision
            self.detect_walls_and_structure()
            
            # Step 4: Detect rooms using computer vision
            cv_rooms = self.detect_rooms_with_cv()
            
            # Step 5: Classify rooms using YOLO context
            classified_rooms = self.classify_rooms_with_yolo_context(cv_rooms, yolo_objects)
            
            # Step 6: Detect doors and windows
            doors_windows = self.detect_doors_and_windows()
            
            # Step 7: Associate doors/windows with rooms
            self._associate_elements_with_rooms(classified_rooms, doors_windows)
            
            # Optional: Save debug images if in debug mode
            if self.debug:
                self.save_debug_images()
            
            # Compile results
            results = {
                'detected_rooms': classified_rooms,
                'image_dimensions': {'width': self.img_width, 'height': self.img_height},
                'image_analysis': image_analysis,
                'processing_method': 'yolo_cv_hybrid',
                'total_doors': len([dw for dw in doors_windows if dw['type'] == 'door']),
                'total_windows': len([dw for dw in doors_windows if dw['type'] == 'window']),
                'total_measurements': 0,  # Not implemented in this version
                'yolo_objects_detected': len(yolo_objects),
                'analysis_summary': f"Detected {len(classified_rooms)} rooms, {len(doors_windows)} doors/windows, and {len(yolo_objects)} objects"
            }
            
            # Add recommendations based on analysis
            recommendations = self._generate_recommendations(image_analysis, yolo_objects, classified_rooms, doors_windows)
            results['recommendations'] = recommendations
            
            print(f"✅ Analysis complete: {results['analysis_summary']}")
            return results
            
        except Exception as e:
            print(f"❌ Error during YOLO analysis: {str(e)}")
            # Return empty result structure
            return {
                'detected_rooms': [],
                'image_dimensions': {'width': 0, 'height': 0},
                'processing_method': 'yolo_cv_hybrid_failed',
                'error': str(e)
            }
    
    def _associate_elements_with_rooms(self, rooms, doors_windows):
        """Associate doors and windows with their respective rooms"""
        for element in doors_windows:
            element_pos = element['position']
            closest_room_idx = self._find_closest_room(element_pos, rooms)
            
            if closest_room_idx >= 0:
                if element['type'] == 'door':
                    if 'doors' not in rooms[closest_room_idx]:
                        rooms[closest_room_idx]['doors'] = []
                    rooms[closest_room_idx]['doors'].append(element)
                else:  # window
                    if 'windows' not in rooms[closest_room_idx]:
                        rooms[closest_room_idx]['windows'] = []
                    rooms[closest_room_idx]['windows'].append(element)
        
        # Ensure all rooms have doors and windows lists
        for room in rooms:
            if 'doors' not in room:
                room['doors'] = []
            if 'windows' not in room:
                room['windows'] = []
            if 'measurements' not in room:
                room['measurements'] = []
    
    def _find_closest_room(self, position, rooms):
        """Find the index of the closest room to a given position"""
        if not rooms:
            return -1
            
        closest_idx = -1
        min_distance = float('inf')
        
        for i, room in enumerate(rooms):
            room_center = room['center']
            
            # Calculate distance to room center
            dx = position['x'] - room_center[0]
            dy = position['y'] - room_center[1]
            distance = (dx * dx + dy * dy) ** 0.5
            
            if distance < min_distance:
                min_distance = distance
                closest_idx = i
                
        return closest_idx
    
    def save_debug_images(self, output_dir="debug_output"):
        """Save debug images showing the detection process"""
        if not hasattr(self, 'original') or not hasattr(self, 'binary'):
            print("⚠️ No processed images available for debug output")
            return
            
        os.makedirs(output_dir, exist_ok=True)
        
        try:
            # Save original image
            cv2.imwrite(f"{output_dir}/01_original.jpg", self.original)
            
            # Save binary/thresholded image
            cv2.imwrite(f"{output_dir}/02_binary.jpg", self.binary)
            
            # Save wall detection
            if hasattr(self, 'walls'):
                cv2.imwrite(f"{output_dir}/03_walls.jpg", self.walls)
            
            # Create room mask visualization
            if hasattr(self, 'walls'):
                room_mask = cv2.bitwise_not(self.walls)
                cv2.imwrite(f"{output_dir}/04_room_mask.jpg", room_mask)
            
            # Create visualization with detected elements
            debug_img = self.original.copy()
            
            # Draw walls in red
            if hasattr(self, 'walls'):
                wall_overlay = cv2.cvtColor(self.walls, cv2.COLOR_GRAY2BGR)
                wall_overlay[:,:,2] = self.walls  # Red channel
                debug_img = cv2.addWeighted(debug_img, 0.7, wall_overlay, 0.3, 0)
            
            cv2.imwrite(f"{output_dir}/05_debug_overlay.jpg", debug_img)
            
            print(f"✅ Debug images saved to {output_dir}/")
            
        except Exception as e:
            print(f"❌ Failed to save debug images: {e}")
    
    def analyze_image_characteristics(self):
        """Analyze image characteristics to help understand detection issues"""
        if not hasattr(self, 'original'):
            return
            
        print(f"\n🔍 Image Analysis:")
        print(f"   Dimensions: {self.img_width}x{self.img_height}")
        print(f"   Total pixels: {self.img_width * self.img_height}")
        
        # Analyze color distribution
        gray = cv2.cvtColor(self.original, cv2.COLOR_BGR2GRAY)
        
        # Calculate histogram
        hist = cv2.calcHist([gray], [0], None, [256], [0, 256])
        
        # Find peaks (most common pixel values)
        peak_indices = np.argsort(hist.flatten())[-5:]  # Top 5 most common values
        print(f"   Most common pixel values: {peak_indices}")
        
        # Calculate contrast
        contrast = np.std(gray)
        print(f"   Contrast (std dev): {contrast:.2f}")
        
        if contrast < 30:
            print("   ⚠️ Low contrast detected - may affect wall detection")
        elif contrast > 80:
            print("   ✅ Good contrast for edge detection")
        else:
            print("   ⚠️ Moderate contrast - results may vary")
        
        # Analyze edge density
        edges = cv2.Canny(gray, 50, 150)
        edge_pixels = np.sum(edges > 0)
        edge_density = edge_pixels / (self.img_width * self.img_height)
        
        print(f"   Edge density: {edge_density:.3f} ({edge_pixels} edge pixels)")
        
        if edge_density < 0.05:
            print("   ⚠️ Low edge density - may indicate blurry or low-detail image")
        elif edge_density > 0.3:
            print("   ⚠️ Very high edge density - may cause false positives")
        else:
            print("   ✅ Good edge density for feature detection")
        
        return {
            'contrast': contrast,
            'edge_density': edge_density,
            'dimensions': (self.img_width, self.img_height)
        }
    
    def _generate_recommendations(self, image_analysis, yolo_objects, rooms, doors_windows):
        """Generate recommendations based on analysis results"""
        recommendations = []
        
        # Check if no rooms were detected
        if len(rooms) == 0:
            recommendations.append({
                'type': 'no_rooms_detected',
                'message': 'No rooms were detected. This could be due to:',
                'suggestions': [
                    'The image may be an architectural line drawing without clear room boundaries',
                    'Try using Google Vision API instead for text-based floor plan analysis',
                    'Ensure the image has good contrast between walls and open spaces',
                    'Check if the floor plan has clearly defined wall lines'
                ]
            })
        
        # Check image quality issues
        if image_analysis:
            contrast = image_analysis.get('contrast', 0)
            edge_density = image_analysis.get('edge_density', 0)
            
            if contrast < 30:
                recommendations.append({
                    'type': 'low_contrast',
                    'message': 'Low image contrast detected',
                    'suggestions': [
                        'Try enhancing the image contrast before analysis',
                        'Ensure the floor plan has clear distinction between walls and spaces',
                        'Consider using a higher resolution image'
                    ]
                })
            
            if edge_density > 0.3:
                recommendations.append({
                    'type': 'high_edge_density',
                    'message': 'Very high edge density detected - may cause false positives',
                    'suggestions': [
                        'The image may have too much detail or noise',
                        'Try simplifying the floor plan or using a cleaner version',
                        'Consider preprocessing to reduce noise'
                    ]
                })
        
        # Check for YOLO detection issues
        if len(yolo_objects) == 0:
            recommendations.append({
                'type': 'no_objects_detected',
                'message': 'No furniture or fixtures detected by YOLO',
                'suggestions': [
                    'This appears to be an unfurnished architectural drawing',
                    'YOLO works best with furnished floor plans showing furniture',
                    'Consider using Google Vision API for better text and label detection',
                    'If furniture should be visible, check image quality and resolution'
                ]
            })
        
        # Check for excessive door/window detections
        if len(doors_windows) > 50:
            recommendations.append({
                'type': 'excessive_doors_windows',
                'message': f'Detected {len(doors_windows)} doors/windows - likely false positives',
                'suggestions': [
                    'The edge detection may be picking up noise or decorative elements',
                    'Try using a cleaner, simplified version of the floor plan',
                    'This suggests the image may not be suitable for computer vision analysis'
                ]
            })
        
        return recommendations

# Global instance for the YOLO vision service
yolo_vision_service = YOLOFloorPlanAnalyzer(debug=False) 