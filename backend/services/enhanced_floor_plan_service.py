import io
import json
import os
from typing import List, Dict, Any, Optional, Tuple
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import base64
import uuid
from datetime import datetime
import math

# Import the specialized floor plan detector
try:
    from .floor_plan_detector import FloorPlanDetector
    FLOOR_PLAN_DETECTOR_AVAILABLE = True
except ImportError:
    FLOOR_PLAN_DETECTOR_AVAILABLE = False
    print("⚠️ Floor plan detector not available")

# Import helper functions and settings from the GitHub repository integration
try:
    from .floor_plan_helper import (
        create_detection_summary, export_results_to_csv, 
        generate_layout_insights, validate_floor_plan_image,
        convert_image_to_base64, optimize_detection_confidence,
        FLOOR_PLAN_LABELS
    )
    from .floor_plan_settings import (
        DEFAULT_CONFIDENCE_THRESHOLD, FLOOR_PLAN_CLASSES,
        get_model_path, get_detection_color
    )
    FLOOR_PLAN_HELPERS_AVAILABLE = True
except ImportError as e:
    print(f"⚠️ Floor plan helpers not available: {e}")
    FLOOR_PLAN_HELPERS_AVAILABLE = False

# Import SAM room segmentation service
try:
    from .sam_room_segmentation_service import sam_service, SAM_AVAILABLE
    SAM_INTEGRATION_AVAILABLE = True
    print("✅ SAM room segmentation integration available")
except ImportError as e:
    print(f"⚠️ SAM integration not available: {e}")
    SAM_INTEGRATION_AVAILABLE = False

class RoomAnnotationManager:
    """Manages room annotations with drawing capabilities similar to Flutter interface"""
    
    def __init__(self):
        self.room_colors = [
            (255, 0, 0, 76),      # Red with opacity
            (0, 0, 255, 76),      # Blue with opacity
            (0, 255, 0, 76),      # Green with opacity
            (255, 165, 0, 76),    # Orange with opacity
            (128, 0, 128, 76),    # Purple with opacity
            (0, 128, 128, 76),    # Teal with opacity
            (255, 192, 203, 76),  # Pink with opacity
            (165, 42, 42, 76),    # Brown with opacity
            (0, 255, 255, 76),    # Cyan with opacity
            (50, 205, 50, 76),    # Lime with opacity
            (255, 191, 0, 76),    # Amber with opacity
        ]
        
        self.room_types = [
            'Living Room', 'Bedroom', 'Kitchen', 'Bathroom', 'Dining Room',
            'Office', 'Laundry', 'Storage', 'Garage', 'Hallway', 'Mamad', 
            'Staircases', 'Balcony', 'Other'
        ]
    
    def create_room_from_rectangle(self, top_left: Tuple[int, int], bottom_right: Tuple[int, int], 
                                  room_type: str, room_name: str, image_dimensions: Tuple[int, int]) -> Dict[str, Any]:
        """Create a room annotation from rectangle coordinates"""
        x1, y1 = top_left
        x2, y2 = bottom_right
        
        # Ensure coordinates are in correct order
        min_x, max_x = min(x1, x2), max(x1, x2)
        min_y, max_y = min(y1, y2), max(y1, y2)
        
        width = max_x - min_x
        height = max_y - min_y
        center_x = min_x + width // 2
        center_y = min_y + height // 2
        
        room_id = str(uuid.uuid4())
        
        return {
            'id': room_id,
            'name': room_name,
            'type': room_type,
            'drawing_tool': 'rectangle',
            'coordinates': {
                'top_left': {'x': min_x, 'y': min_y},
                'bottom_right': {'x': max_x, 'y': max_y},
                'center': {'x': center_x, 'y': center_y},
                'width': width,
                'height': height
            },
            'boundary': {
                'type': 'rectangle',
                'points': [
                    {'x': min_x, 'y': min_y},
                    {'x': max_x, 'y': min_y},
                    {'x': max_x, 'y': max_y},
                    {'x': min_x, 'y': max_y}
                ]
            },
            'area_pixels': width * height,
            'placement': self._calculate_placement(center_x, center_y, image_dimensions),
            'size_description': self._get_size_description(width * height),
            'created_at': datetime.now().isoformat(),
            'detection_method': 'user_drawn_rectangle'
        }
    
    def create_room_from_polygon(self, points: List[Tuple[int, int]], room_type: str, 
                                room_name: str, image_dimensions: Tuple[int, int]) -> Dict[str, Any]:
        """Create a room annotation from polygon points"""
        if len(points) < 3:
            raise ValueError("Polygon must have at least 3 points")
        
        # Calculate polygon properties
        polygon_points = [{'x': x, 'y': y} for x, y in points]
        area = self._calculate_polygon_area(points)
        centroid = self._calculate_polygon_centroid(points)
        bbox = self._calculate_polygon_bbox(points)
        
        room_id = str(uuid.uuid4())
        
        return {
            'id': room_id,
            'name': room_name,
            'type': room_type,
            'drawing_tool': 'polygon',
            'coordinates': {
                'centroid': {'x': centroid[0], 'y': centroid[1]},
                'bbox': bbox,
                'points_count': len(points)
            },
            'boundary': {
                'type': 'polygon',
                'points': polygon_points
            },
            'area_pixels': area,
            'placement': self._calculate_placement(centroid[0], centroid[1], image_dimensions),
            'size_description': self._get_size_description(area),
            'created_at': datetime.now().isoformat(),
            'detection_method': 'user_drawn_polygon'
        }
    
    def _calculate_polygon_area(self, points: List[Tuple[int, int]]) -> float:
        """Calculate area of polygon using shoelace formula"""
        if len(points) < 3:
            return 0.0
        
        area = 0.0
        n = len(points)
        
        for i in range(n):
            j = (i + 1) % n
            area += points[i][0] * points[j][1]
            area -= points[j][0] * points[i][1]
        
        return abs(area) / 2.0
    
    def _calculate_polygon_centroid(self, points: List[Tuple[int, int]]) -> Tuple[int, int]:
        """Calculate centroid of polygon"""
        if not points:
            return (0, 0)
        
        x = sum(p[0] for p in points) / len(points)
        y = sum(p[1] for p in points) / len(points)
        return (int(x), int(y))
    
    def _calculate_polygon_bbox(self, points: List[Tuple[int, int]]) -> Dict[str, int]:
        """Calculate bounding box of polygon"""
        if not points:
            return {'x': 0, 'y': 0, 'width': 0, 'height': 0}
        
        min_x = min(p[0] for p in points)
        max_x = max(p[0] for p in points)
        min_y = min(p[1] for p in points)
        max_y = max(p[1] for p in points)
        
        return {
            'x': min_x,
            'y': min_y,
            'width': max_x - min_x,
            'height': max_y - min_y
        }
    
    def _calculate_placement(self, center_x: int, center_y: int, image_dims: Tuple[int, int]) -> Dict[str, Any]:
        """Calculate room placement similar to Flutter implementation"""
        img_width, img_height = image_dims
        
        relative_x = center_x / img_width
        relative_y = center_y / img_height
        
        # Determine position description
        h_pos = "left" if relative_x < 0.33 else "right" if relative_x > 0.66 else "center"
        v_pos = "top" if relative_y < 0.33 else "bottom" if relative_y > 0.66 else "middle"
        
        if h_pos == "center" and v_pos == "middle":
            position_description = "Center of plan"
        else:
            position_description = f"{v_pos.title()} {h_pos}"
        
        return {
            'center_x': center_x,
            'center_y': center_y,
            'relative_x': relative_x,
            'relative_y': relative_y,
            'position_description': position_description
        }
    
    def _get_size_description(self, area_pixels: float) -> str:
        """Get size description based on area"""
        if area_pixels < 5000:
            return 'Small'
        elif area_pixels < 15000:
            return 'Medium'
        elif area_pixels < 30000:
            return 'Large'
        else:
            return 'Very Large'
    
    def draw_rooms_on_image(self, image_bytes: bytes, rooms: List[Dict[str, Any]], 
                           show_labels: bool = True) -> bytes:
        """Draw room annotations on floor plan image"""
        # Load image
        image = Image.open(io.BytesIO(image_bytes))
        img_array = np.array(image)
        
        # Convert to RGBA if needed
        if len(img_array.shape) == 3 and img_array.shape[2] == 3:
            img_array = cv2.cvtColor(img_array, cv2.COLOR_RGB2RGBA)
        elif len(img_array.shape) == 2:
            img_array = cv2.cvtColor(img_array, cv2.COLOR_GRAY2RGBA)
        
        # Create overlay for transparent drawing
        overlay = img_array.copy()
        
        for i, room in enumerate(rooms):
            color = self.room_colors[i % len(self.room_colors)]
            boundary = room.get('boundary', {})
            
            if boundary.get('type') == 'rectangle':
                self._draw_rectangle(overlay, boundary, color, room, show_labels)
            elif boundary.get('type') == 'polygon':
                self._draw_polygon(overlay, boundary, color, room, show_labels)
        
        # Convert back to PIL Image
        result_image = Image.fromarray(overlay)
        
        # Save to bytes
        output_buffer = io.BytesIO()
        result_image.save(output_buffer, format='PNG')
        return output_buffer.getvalue()
    
    def _draw_rectangle(self, img_array: np.ndarray, boundary: Dict, color: Tuple, 
                       room: Dict, show_labels: bool):
        """Draw rectangle room on image"""
        points = boundary.get('points', [])
        if len(points) < 4:
            return
        
        # Extract rectangle coordinates
        x1, y1 = points[0]['x'], points[0]['y']
        x2, y2 = points[2]['x'], points[2]['y']
        
        # Draw filled rectangle with transparency
        cv2.rectangle(img_array, (x1, y1), (x2, y2), color, -1)
        
        # Draw border
        border_color = (color[0], color[1], color[2], 255)
        cv2.rectangle(img_array, (x1, y1), (x2, y2), border_color, 2)
        
        if show_labels:
            self._draw_room_label(img_array, room, (x1 + (x2-x1)//2, y1 + (y2-y1)//2))
    
    def _draw_polygon(self, img_array: np.ndarray, boundary: Dict, color: Tuple, 
                     room: Dict, show_labels: bool):
        """Draw polygon room on image"""
        points = boundary.get('points', [])
        if len(points) < 3:
            return
        
        # Convert points to numpy array
        polygon_points = np.array([[p['x'], p['y']] for p in points], np.int32)
        
        # Draw filled polygon with transparency
        cv2.fillPoly(img_array, [polygon_points], color)
        
        # Draw border
        border_color = (color[0], color[1], color[2], 255)
        cv2.polylines(img_array, [polygon_points], True, border_color, 2)
        
        if show_labels:
            # Calculate centroid for label placement
            centroid = self._calculate_polygon_centroid([(p['x'], p['y']) for p in points])
            self._draw_room_label(img_array, room, centroid)
    
    def _draw_room_label(self, img_array: np.ndarray, room: Dict, center: Tuple[int, int]):
        """Draw room label at center position"""
        text = f"{room.get('name', 'Room')}"
        font_scale = 0.6
        font_thickness = 1
        font = cv2.FONT_HERSHEY_SIMPLEX
        
        # Get text size
        (text_width, text_height), baseline = cv2.getTextSize(text, font, font_scale, font_thickness)
        
        # Calculate text position (centered)
        text_x = center[0] - text_width // 2
        text_y = center[1] + text_height // 2
        
        # Draw text background rectangle
        padding = 4
        cv2.rectangle(img_array, 
                     (text_x - padding, text_y - text_height - padding),
                     (text_x + text_width + padding, text_y + baseline + padding),
                     (255, 255, 255, 200), -1)
        
        # Draw text
        cv2.putText(img_array, text, (text_x, text_y), font, font_scale, (0, 0, 0, 255), font_thickness)

class EnhancedFloorPlanService:
    def __init__(self, model_path: Optional[str] = None):
        """
        Initialize the enhanced floor plan service
        
        Args:
            model_path: Path to the trained floor plan detection model (.pt file)
        """
        self.floor_plan_detector = None
        self.model_path = model_path
        self.room_annotation_manager = RoomAnnotationManager()
        
        # Try to get model path from settings if not provided
        if not model_path and FLOOR_PLAN_HELPERS_AVAILABLE:
            try:
                model_path = get_model_path()
                self.model_path = model_path
                print(f"🔍 Using model path from settings: {model_path}")
            except Exception as e:
                print(f"⚠️ Could not get model path from settings: {e}")
        
        # Try to initialize the floor plan detector
        if model_path and os.path.exists(model_path) and FLOOR_PLAN_DETECTOR_AVAILABLE:
            try:
                self.floor_plan_detector = FloorPlanDetector(model_path)
                print(f"✅ Enhanced floor plan service initialized with model: {model_path}")
                
                # Verify the model can detect the expected classes
                available_labels = self.floor_plan_detector.get_available_labels()
                print(f"📋 Model can detect {len(available_labels)} classes: {', '.join(available_labels[:5])}...")
                
            except Exception as e:
                print(f"⚠️ Failed to load floor plan model: {e}")
                self.floor_plan_detector = None
        else:
            if not model_path:
                print("⚠️ No model path provided")
            elif not os.path.exists(model_path):
                print(f"⚠️ Model file not found: {model_path}")
            elif not FLOOR_PLAN_DETECTOR_AVAILABLE:
                print("⚠️ Floor plan detector not available")
            print("⚠️ Enhanced floor plan service initialized without specialized model")
    
    async def analyze_floor_plan_with_room_segmentation(self, image_bytes: bytes, confidence: float = 0.4, enable_sam: bool = True) -> Dict[str, Any]:
        """
        Complete floor plan analysis: YOLO architectural detection + SAM room segmentation
        
        This is the main method for the "AI Detect" button functionality that:
        1. Detects doors, windows, walls, etc. using enhanced YOLO
        2. Segments rooms using SAM guided by architectural elements
        
        Args:
            image_bytes: Floor plan image as bytes
            confidence: Detection confidence threshold for YOLO
            enable_sam: Whether to perform SAM room segmentation
            
        Returns:
            Combined results with both architectural elements and room segments
        """
        print(f"🚀 Starting complete floor plan analysis (YOLO + SAM)")
        print(f"   📊 YOLO confidence: {confidence}")
        print(f"   🎭 SAM segmentation: {'enabled' if enable_sam else 'disabled'}")
        
        # Step 1: Perform YOLO architectural element detection
        print("🏗️ Step 1: Detecting architectural elements with enhanced YOLO...")
        yolo_results = await self.analyze_floor_plan(image_bytes, confidence)
        
        if yolo_results.get('processing_method') == 'enhanced_floor_plan_unavailable':
            print("❌ YOLO detection failed - cannot proceed with SAM")
            return yolo_results
        
        # Step 2: Perform SAM room segmentation if enabled and available
        sam_results = {}
        if enable_sam and SAM_INTEGRATION_AVAILABLE and sam_service:
            print("🎭 Step 2: Segmenting rooms with SAM...")
            try:
                architectural_elements = yolo_results.get('architectural_elements', [])
                sam_results = await sam_service.segment_rooms_with_architectural_guidance(
                    image_bytes, 
                    architectural_elements,
                    confidence_threshold=0.7
                )
                print(f"✅ SAM segmentation complete: {sam_results.get('total_rooms', 0)} rooms found")
                
            except Exception as e:
                print(f"⚠️ SAM segmentation failed: {e}")
                sam_results = {
                    'room_segments': [],
                    'error': str(e),
                    'segmentation_method': 'sam_failed'
                }
        else:
            print("⚠️ SAM segmentation skipped (disabled or unavailable)")
            sam_results = {
                'room_segments': [],
                'segmentation_method': 'sam_disabled',
                'message': 'SAM room segmentation not available or disabled'
            }
        
        # Step 3: Combine results
        print("🔗 Step 3: Combining YOLO and SAM results...")
        combined_results = self._combine_yolo_and_sam_results(yolo_results, sam_results)
        
        print(f"🎉 Complete analysis finished!")
        print(f"   🏗️ Architectural elements: {len(combined_results.get('architectural_elements', []))}")
        print(f"   🏠 Room segments: {len(combined_results.get('room_segments', []))}")
        
        return combined_results
    
    def _combine_yolo_and_sam_results(self, yolo_results: Dict[str, Any], sam_results: Dict[str, Any]) -> Dict[str, Any]:
        """
        Combine YOLO architectural detection and SAM room segmentation results
        """
        combined = yolo_results.copy()  # Start with YOLO results
        
        # Add SAM room segmentation data
        combined.update({
            'room_segments': sam_results.get('room_segments', []),
            'total_sam_rooms': sam_results.get('total_rooms', 0),
            'sam_segmentation_method': sam_results.get('segmentation_method', 'not_performed'),
            'sam_visualization': sam_results.get('visualization', ''),
            'individual_visualizations': sam_results.get('individual_visualizations', {}),
            'sam_metadata': sam_results.get('metadata', {}),
            'processing_method': 'enhanced_yolo_plus_sam_integration',
            'combined_analysis': True
        })
        
        # Enhanced room analysis combining both YOLO and SAM data
        if sam_results.get('room_segments'):
            combined['enhanced_rooms'] = self._create_enhanced_room_analysis(
                yolo_results.get('architectural_elements', []),
                sam_results.get('room_segments', []),
                yolo_results.get('image_dimensions', {})
            )
        
        # Update summary to include SAM information
        original_summary = combined.get('analysis_summary', '')
        sam_room_count = len(sam_results.get('room_segments', []))
        
        if sam_room_count > 0:
            sam_summary = f" | SAM detected {sam_room_count} distinct room segments"
            combined['analysis_summary'] = original_summary + sam_summary
        
        return combined
    
    def _create_enhanced_room_analysis(self, architectural_elements: List[Dict], room_segments: List[Dict], image_dims: Dict) -> List[Dict[str, Any]]:
        """
        Create enhanced room analysis combining YOLO elements with SAM segments
        """
        enhanced_rooms = []
        
        for segment in room_segments:
            # Get basic room info from SAM
            room_info = segment.get('room_info', {})
            
            # Add YOLO-detected elements that belong to this room
            room_doors = room_info.get('access_points', [])
            room_walls = room_info.get('boundaries', [])
            
            # Create enhanced room data
            enhanced_room = {
                'room_id': segment.get('room_id', 0),
                'room_name': segment.get('room_name', 'Unknown Room'),
                'sam_segment_id': segment.get('segment_id'),
                
                # Geometry from SAM
                'area_pixels': segment.get('area', 0),
                'area_percentage': segment.get('area_percentage', 0),
                'centroid': segment.get('centroid', {'x': 0, 'y': 0}),
                'bbox': segment.get('bbox', {}),
                'perimeter': segment.get('perimeter', 0),
                
                # Classification from SAM + YOLO
                'room_type': room_info.get('room_type', 'Unknown'),
                'estimated_function': room_info.get('estimated_function', 'General Room'),
                'is_main_room': room_info.get('is_main_room', False),
                
                # Architectural elements from YOLO
                'doors': room_doors,
                'walls': room_walls,
                'door_count': len(room_doors),
                'wall_count': len(room_walls),
                
                # Combined analysis
                'accessibility_score': self._calculate_accessibility_score(room_doors, segment.get('area', 0)),
                'safety_features': self._analyze_safety_features(room_doors, room_walls),
                'room_connectivity': self._analyze_room_connectivity(room_doors),
                
                # SAM-specific data
                'stability_score': segment.get('stability_score', 0),
                'segmentation_quality': 'high' if segment.get('stability_score', 0) > 0.8 else 'medium'
            }
            
            enhanced_rooms.append(enhanced_room)
        
        return enhanced_rooms
    
    def _calculate_accessibility_score(self, doors: List[Dict], room_area: int) -> float:
        """Calculate room accessibility score for safety analysis"""
        if not doors:
            return 0.0  # No access
        
        door_count = len(doors)
        
        # Base score from door count
        if door_count == 1:
            base_score = 0.6
        elif door_count == 2:
            base_score = 0.8
        else:
            base_score = 1.0  # Multiple exits
        
        # Adjust for room size (larger rooms should have more exits)
        size_factor = min(1.0, room_area / 20000)  # Normalize to reasonable room size
        
        return min(1.0, base_score + (size_factor * 0.2))
    
    def _analyze_safety_features(self, doors: List[Dict], walls: List[Dict]) -> Dict[str, Any]:
        """Analyze safety features of a room"""
        return {
            'exit_count': len(doors),
            'has_multiple_exits': len(doors) > 1,
            'wall_protection': len(walls) > 0,
            'emergency_egress': 'good' if len(doors) > 1 else 'limited' if len(doors) == 1 else 'poor'
        }
    
    def _analyze_room_connectivity(self, doors: List[Dict]) -> Dict[str, Any]:
        """Analyze how well connected a room is"""
        door_count = len(doors)
        
        return {
            'connection_level': 'isolated' if door_count == 0 else 'connected' if door_count == 1 else 'hub' if door_count > 2 else 'standard',
            'door_count': door_count,
            'connectivity_score': min(1.0, door_count / 3.0)  # Normalize to max 3 doors
        }
    
    async def analyze_floor_plan(self, image_bytes: bytes, confidence: float = 0.4) -> Dict[str, Any]:
        """
        Analyze a floor plan using the specialized detector
        
        Args:
            image_bytes: Image data as bytes
            confidence: Detection confidence threshold (0.0 to 1.0)
        """
        print(f"🏗️ Starting enhanced floor plan analysis (confidence: {confidence})")
        
        # Validate input image if helpers are available
        if FLOOR_PLAN_HELPERS_AVAILABLE:
            is_valid, validation_message = validate_floor_plan_image(image_bytes)
            if not is_valid:
                return {
                    'detected_rooms': [],
                    'image_dimensions': {'width': 0, 'height': 0},
                    'processing_method': 'enhanced_floor_plan_validation_failed',
                    'error': f'Image validation failed: {validation_message}'
                }
            print(f"✅ Image validation passed: {validation_message}")
        
        if not self.floor_plan_detector:
            return {
                'detected_rooms': [],
                'image_dimensions': {'width': 0, 'height': 0},
                'processing_method': 'enhanced_floor_plan_unavailable',
                'error': 'Floor plan detector not available. Please provide a trained model.'
            }
        
        try:
            # Convert bytes to PIL Image
            image = Image.open(io.BytesIO(image_bytes))
            img_width, img_height = image.size
            
            print(f"📐 Image dimensions: {img_width}x{img_height}")
            
            # Convert original image to base64 for frontend display
            original_image_b64 = ""
            if FLOOR_PLAN_HELPERS_AVAILABLE:
                # Convert PIL Image to numpy array for the helper function
                import numpy as np
                image_array = np.array(image)
                original_image_b64 = convert_image_to_base64(image_array)
            else:
                # Fallback: create base64 directly from PIL Image
                import base64
                buffer = io.BytesIO()
                image.save(buffer, format='PNG')
                img_bytes = buffer.getvalue()
                original_image_b64 = base64.b64encode(img_bytes).decode()
                original_image_b64 = f"data:image/png;base64,{original_image_b64}"
            
            # Run specialized floor plan detection
            detection_results = self.floor_plan_detector.detect_objects(
                image, 
                confidence=confidence
            )
            
            # Extract detection information
            object_counts = detection_results['object_counts']
            filtered_boxes = detection_results['filtered_boxes']
            
            print(f"🎯 Detected architectural elements:")
            for element, count in object_counts.items():
                print(f"   • {element}: {count}")
            
            # Process detections into our standard format
            processed_results = self._process_detections(
                filtered_boxes, 
                object_counts, 
                img_width, 
                img_height,
                self.floor_plan_detector.model.names
            )
            
            # Generate rooms based on detected elements
            rooms = self._generate_rooms_from_detections(processed_results, img_width, img_height)
            
            # Generate layout insights using helper functions
            layout_insights = {}
            detection_summary = ""
            csv_export = ""
            annotated_image_b64 = ""
            
            if FLOOR_PLAN_HELPERS_AVAILABLE:
                # Create detection summary
                detection_summary = create_detection_summary(object_counts)
                
                # Generate layout insights
                layout_insights = generate_layout_insights(processed_results, img_width, img_height)
                
                # Create CSV export
                csv_export = export_results_to_csv(object_counts)
                
                # Convert annotated image to base64 for web display
                if 'annotated_image' in detection_results:
                    annotated_image_b64 = convert_image_to_base64(detection_results['annotated_image'])
                
                # Optimize confidence suggestion for future use
                suggested_confidence = optimize_detection_confidence(processed_results)
                print(f"💡 Suggested confidence for optimal results: {suggested_confidence:.2f}")
            
            # Compile final results with enhanced data from GitHub repository
            results = {
                'detected_rooms': rooms,
                'architectural_elements': processed_results,
                'image_dimensions': {'width': img_width, 'height': img_height},
                'processing_method': 'enhanced_floor_plan_yolo_github_integration',
                'detection_confidence': confidence,
                'total_doors': object_counts.get('Door', 0) + object_counts.get('Sliding Door', 0),
                'total_windows': object_counts.get('Window', 0),
                'total_walls': object_counts.get('Wall', 0),
                'total_stairs': object_counts.get('Stair Case', 0),
                'element_counts': object_counts,
                'analysis_summary': detection_summary if detection_summary else self._generate_summary(object_counts, len(rooms)),
                'layout_insights': layout_insights,
                'csv_export': csv_export,
                'annotated_image_base64': annotated_image_b64,
                'original_image_base64': original_image_b64,
                'sam_visualization': None,  # SAM not available in standard YOLO endpoint
                'model_classes': list(FLOOR_PLAN_CLASSES.values()) if FLOOR_PLAN_HELPERS_AVAILABLE else [],
                'suggested_confidence': suggested_confidence if FLOOR_PLAN_HELPERS_AVAILABLE else confidence
            }
            
            summary_text = results['analysis_summary']
            print(f"✅ Enhanced analysis complete: {summary_text}")
            return results
            
        except Exception as e:
            print(f"❌ Error during enhanced floor plan analysis: {str(e)}")
            return {
                'detected_rooms': [],
                'image_dimensions': {'width': 0, 'height': 0},
                'processing_method': 'enhanced_floor_plan_failed',
                'error': str(e)
            }
    
    def _process_detections(self, boxes, object_counts, img_width, img_height, class_names) -> List[Dict[str, Any]]:
        """Process raw detections into structured format"""
        elements = []
        
        for box in boxes:
            # Get box coordinates (xyxy format)
            x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
            confidence = box.conf[0].cpu().numpy()
            class_id = int(box.cls[0].cpu().numpy())
            class_name = class_names[class_id]
            
            # Calculate center and dimensions
            center_x = int((x1 + x2) / 2)
            center_y = int((y1 + y2) / 2)
            width = int(x2 - x1)
            height = int(y2 - y1)
            area = width * height
            
            element = {
                'type': class_name,
                'confidence': float(confidence),
                'bbox': {'x1': int(x1), 'y1': int(y1), 'x2': int(x2), 'y2': int(y2)},
                'center': {'x': center_x, 'y': center_y},
                'dimensions': {'width': width, 'height': height},
                'area': area,
                'relative_position': self._get_relative_position(center_x, center_y, img_width, img_height)
            }
            
            elements.append(element)
        
        return elements
    
    def _get_relative_position(self, x, y, img_width, img_height) -> str:
        """Get relative position description"""
        h_pos = "left" if x < img_width/3 else "right" if x > 2*img_width/3 else "center"
        v_pos = "top" if y < img_height/3 else "bottom" if y > 2*img_height/3 else "middle"
        return f"{v_pos}-{h_pos}"
    
    def _generate_rooms_from_detections(self, elements, img_width, img_height) -> List[Dict[str, Any]]:
        """Generate room information based on detected architectural elements"""
        rooms = []
        
        # Group elements by spatial proximity to infer rooms
        room_clusters = self._cluster_elements_into_rooms(elements, img_width, img_height)
        
        for i, cluster in enumerate(room_clusters):
            # Analyze elements in this cluster to determine room type
            room_type, confidence = self._classify_room_from_elements(cluster)
            
            # Calculate room boundaries (include image dimensions for location analysis)
            boundaries = self._calculate_room_boundaries(cluster, img_width, img_height)
            boundaries['img_width'] = img_width  # Add for location descriptions
            boundaries['img_height'] = img_height  # Add for location descriptions
            
            # Generate room description
            description = self._generate_room_description(room_type, cluster, boundaries)
            
            room = {
                'room_id': i,
                'default_name': room_type,
                'boundaries': boundaries,
                'confidence': confidence,
                'architectural_elements': cluster,
                'description': description,
                'detection_method': 'enhanced_floor_plan_clustering',
                'doors': [e for e in cluster if e['type'] in ['Door', 'Sliding Door']],
                'windows': [e for e in cluster if e['type'] == 'Window'],
                'walls': [e for e in cluster if e['type'] == 'Wall'],
                'estimated_dimensions': self._estimate_room_dimensions(boundaries)
            }
            
            rooms.append(room)
        
        # If no clusters found, create a general room based on overall layout
        if not rooms and elements:
            general_room = self._create_general_room_from_elements(elements, img_width, img_height)
            rooms.append(general_room)
        
        return rooms
    
    def _cluster_elements_into_rooms(self, elements, img_width, img_height) -> List[List[Dict]]:
        """Cluster architectural elements into potential rooms using spatial proximity"""
        if not elements:
            return []
        
        # Simple clustering based on spatial proximity
        clusters = []
        used_elements = set()
        
        # Define clustering distance (10% of image diagonal)
        cluster_distance = np.sqrt(img_width**2 + img_height**2) * 0.1
        
        for i, element in enumerate(elements):
            if i in used_elements:
                continue
            
            # Start new cluster
            cluster = [element]
            used_elements.add(i)
            
            # Find nearby elements
            for j, other_element in enumerate(elements):
                if j in used_elements or i == j:
                    continue
                
                # Calculate distance between elements
                dist = np.sqrt(
                    (element['center']['x'] - other_element['center']['x'])**2 +
                    (element['center']['y'] - other_element['center']['y'])**2
                )
                
                if dist < cluster_distance:
                    cluster.append(other_element)
                    used_elements.add(j)
            
            if len(cluster) >= 2:  # Only keep clusters with multiple elements
                clusters.append(cluster)
        
        return clusters
    
    def _classify_room_from_elements(self, elements) -> tuple:
        """Classify room type based on architectural elements with enhanced logic"""
        element_types = [e['type'] for e in elements]
        element_counts = {}
        for elem_type in element_types:
            element_counts[elem_type] = element_counts.get(elem_type, 0) + 1
        
        doors = element_counts.get('Door', 0) + element_counts.get('Sliding Door', 0)
        windows = element_counts.get('Window', 0)
        walls = element_counts.get('Wall', 0)
        stairs = element_counts.get('Stair Case', 0)
        
        # Enhanced classification logic
        if stairs > 0:
            if doors >= 2:
                return 'Main Stairway', 0.95
            else:
                return 'Stairway', 0.9
        elif doors >= 3:
            return 'Central Hallway', 0.85
        elif doors == 2 and windows == 0:
            return 'Corridor', 0.8
        elif doors >= 2 and windows >= 1:
            return 'Living Area', 0.85
        elif doors == 1 and windows >= 2:
            return 'Bedroom', 0.8
        elif doors == 1 and windows == 1:
            return 'Private Room', 0.75
        elif doors == 1 and windows == 0:
            if walls >= 3:
                return 'Utility Room', 0.7
            else:
                return 'Storage Room', 0.65
        elif doors == 0 and windows >= 1:
            return 'Enclosed Space', 0.6
        elif windows >= doors and windows > 0:
            return 'Sunroom', 0.7
        elif doors == 1:
            return 'Room', 0.6
        else:
            return 'Undefined Space', 0.4
    
    def _calculate_room_boundaries(self, elements, img_width, img_height) -> Dict[str, int]:
        """Calculate room boundaries based on element positions"""
        if not elements:
            return {'x': 0, 'y': 0, 'width': 0, 'height': 0}
        
        # Find bounding box of all elements
        min_x = min(e['bbox']['x1'] for e in elements)
        min_y = min(e['bbox']['y1'] for e in elements)
        max_x = max(e['bbox']['x2'] for e in elements)
        max_y = max(e['bbox']['y2'] for e in elements)
        
        # Add some padding
        padding = min(img_width, img_height) * 0.05
        min_x = max(0, int(min_x - padding))
        min_y = max(0, int(min_y - padding))
        max_x = min(img_width, int(max_x + padding))
        max_y = min(img_height, int(max_y + padding))
        
        return {
            'x': min_x,
            'y': min_y,
            'width': max_x - min_x,
            'height': max_y - min_y
        }
    
    def _generate_room_description(self, room_type, elements, boundaries) -> str:
        """Generate detailed descriptive text for the room including location and context"""
        element_counts = {}
        for element in elements:
            element_type = element['type']
            element_counts[element_type] = element_counts.get(element_type, 0) + 1
        
        # Start with room type and size description
        room_area_sqm = self._estimate_room_dimensions(boundaries)['area_sqm']
        size_description = self._get_room_size_description(room_area_sqm)
        
        description = f"A {size_description} {room_type.lower()}"
        
        # Add architectural elements description
        element_descriptions = []
        for element_type, count in element_counts.items():
            if count == 1:
                element_descriptions.append(f"1 {element_type.lower()}")
            else:
                element_descriptions.append(f"{count} {element_type.lower()}s")
        
        if element_descriptions:
            description += f" containing {', '.join(element_descriptions)}"
        
        # Add detailed location information
        avg_x = boundaries['x'] + boundaries['width'] // 2
        avg_y = boundaries['y'] + boundaries['height'] // 2
        img_width = boundaries.get('img_width', 1000)  # Default fallback
        img_height = boundaries.get('img_height', 1000)  # Default fallback
        
        location_desc = self._get_detailed_location_description(avg_x, avg_y, img_width, img_height)
        description += f". {location_desc}"
        
        # Add room function and accessibility analysis
        function_desc = self._analyze_room_function(room_type, element_counts)
        if function_desc:
            description += f" {function_desc}"
        
        accessibility_desc = self._analyze_room_accessibility(element_counts)
        if accessibility_desc:
            description += f" {accessibility_desc}"
        
        # Add contextual information based on elements
        context_desc = self._generate_room_context(element_counts, boundaries)
        if context_desc:
            description += f" {context_desc}"
        
        return description
    
    def _get_room_size_description(self, area_sqm: float) -> str:
        """Get descriptive text for room size"""
        if area_sqm < 5:
            return "small"
        elif area_sqm < 15:
            return "medium-sized"
        elif area_sqm < 30:
            return "large"
        else:
            return "very large"
    
    def _get_detailed_location_description(self, x: int, y: int, img_width: int, img_height: int) -> str:
        """Generate detailed location description within the floor plan"""
        # Determine horizontal position
        h_third = img_width / 3
        if x < h_third:
            h_pos = "left"
            h_detail = "western"
        elif x > 2 * h_third:
            h_pos = "right"
            h_detail = "eastern"
        else:
            h_pos = "center"
            h_detail = "central"
        
        # Determine vertical position
        v_third = img_height / 3
        if y < v_third:
            v_pos = "top"
            v_detail = "northern"
        elif y > 2 * v_third:
            v_pos = "bottom"
            v_detail = "southern"
        else:
            v_pos = "middle"
            v_detail = "central"
        
        # Create detailed location description
        if v_pos == "middle" and h_pos == "center":
            return "Centrally positioned within the floor plan, serving as a core area"
        elif v_pos == "middle":
            return f"Located along the {h_detail} edge of the floor plan, positioned in the {h_pos} section"
        elif h_pos == "center":
            return f"Positioned in the {v_detail} section of the floor plan, centrally aligned horizontally"
        else:
            return f"Situated in the {v_detail}-{h_detail} quadrant of the floor plan ({v_pos}-{h_pos} area)"
    
    def _analyze_room_function(self, room_type: str, element_counts: Dict[str, int]) -> str:
        """Analyze and describe the likely function of the room"""
        doors = element_counts.get('Door', 0) + element_counts.get('Sliding Door', 0)
        windows = element_counts.get('Window', 0)
        walls = element_counts.get('Wall', 0)
        
        if room_type.lower() == 'stairway':
            if doors >= 2:
                return "This stairway serves as a primary vertical circulation hub with multiple access points."
            else:
                return "This stairway provides vertical access between floors."
        
        elif room_type.lower() == 'hallway':
            return f"This corridor facilitates movement between different areas, with {doors} connection points to adjacent spaces."
        
        elif room_type.lower() == 'room':
            if windows >= 2 and doors == 1:
                return "This appears to be a main living space with excellent natural lighting from multiple windows."
            elif windows >= 1 and doors == 1:
                return "This room offers natural light and privacy, suitable for bedroom or office use."
            elif doors >= 2:
                return "This room serves as a connecting space with multiple access points, possibly a dining or living area."
            else:
                return "This enclosed space provides privacy and functionality for various uses."
        
        return ""
    
    def _analyze_room_accessibility(self, element_counts: Dict[str, int]) -> str:
        """Analyze room accessibility and safety features"""
        doors = element_counts.get('Door', 0) + element_counts.get('Sliding Door', 0)
        windows = element_counts.get('Window', 0)
        
        accessibility_notes = []
        
        if doors == 0:
            accessibility_notes.append("No direct access detected - may be an enclosed utility space")
        elif doors == 1:
            accessibility_notes.append("Single-point access provides privacy but limited emergency egress")
        elif doors == 2:
            accessibility_notes.append("Dual access points offer good circulation and emergency exit options")
        else:
            accessibility_notes.append(f"Multiple access points ({doors} doors) provide excellent connectivity and safety")
        
        if windows >= 2:
            accessibility_notes.append("abundant natural lighting")
        elif windows == 1:
            accessibility_notes.append("natural lighting available")
        
        if accessibility_notes:
            return f"Features {' and '.join(accessibility_notes)}."
        
        return ""
    
    def _generate_room_context(self, element_counts: Dict[str, int], boundaries: Dict[str, int]) -> str:
        """Generate contextual information about the room based on its characteristics"""
        context_notes = []
        
        # Analyze room proportions
        width = boundaries.get('width', 0)
        height = boundaries.get('height', 0)
        
        if width > 0 and height > 0:
            aspect_ratio = max(width, height) / min(width, height)
            if aspect_ratio > 2.5:
                context_notes.append("The elongated shape suggests a corridor or narrow room design")
            elif aspect_ratio < 1.3:
                context_notes.append("The square proportions indicate a balanced, functional layout")
        
        # Analyze element density
        total_elements = sum(element_counts.values())
        room_area = width * height if width > 0 and height > 0 else 1
        element_density = total_elements / (room_area / 10000)  # elements per 100x100 pixel area
        
        if element_density > 0.5:
            context_notes.append("high architectural detail density suggests an important functional space")
        elif element_density < 0.1:
            context_notes.append("minimal architectural elements indicate an open, flexible space")
        
        # Special combinations analysis
        doors = element_counts.get('Door', 0) + element_counts.get('Sliding Door', 0)
        windows = element_counts.get('Window', 0)
        walls = element_counts.get('Wall', 0)
        
        if windows >= doors and windows > 0:
            context_notes.append("window-to-door ratio suggests a space designed for natural light and views")
        
        if walls >= 3 and doors <= 1:
            context_notes.append("well-enclosed design provides privacy and sound isolation")
        
        if context_notes:
            return f"{' and '.join(context_notes)}."
        
        return ""
    
    def _estimate_room_dimensions(self, boundaries) -> Dict[str, float]:
        """Estimate real-world room dimensions"""
        # Very rough estimation - would need calibration
        px_to_meter = 0.05  # Assume 1 pixel = 5cm (very rough)
        
        width_m = boundaries['width'] * px_to_meter
        height_m = boundaries['height'] * px_to_meter
        area_sqm = width_m * height_m
        
        return {
            'width_m': round(width_m, 2),
            'length_m': round(height_m, 2),
            'area_sqm': round(area_sqm, 2),
            'estimated_ceiling_height_m': 2.5
        }
    
    def _create_general_room_from_elements(self, elements, img_width, img_height) -> Dict[str, Any]:
        """Create a general room when clustering fails"""
        # Count all elements
        element_counts = {}
        for element in elements:
            element_type = element['type']
            element_counts[element_type] = element_counts.get(element_type, 0) + 1
        
        # Determine room type based on most common elements
        doors = element_counts.get('Door', 0) + element_counts.get('Sliding Door', 0)
        windows = element_counts.get('Window', 0)
        stairs = element_counts.get('Stair Case', 0)
        
        if stairs > 0:
            room_type = 'Multi-level Floor Plan'
        elif doors > 3:
            room_type = 'Open Floor Plan'
        elif doors > 2:
            room_type = 'Multi-room Layout'
        else:
            room_type = 'General Floor Plan'
        
        # Create enhanced description for general room
        boundaries = {'x': 0, 'y': 0, 'width': img_width, 'height': img_height, 'img_width': img_width, 'img_height': img_height}
        detailed_description = self._generate_general_floor_plan_description(element_counts, room_type, img_width, img_height)
        
        return {
            'room_id': 0,
            'default_name': room_type,
            'boundaries': boundaries,
            'confidence': 0.6,
            'architectural_elements': elements,
            'description': detailed_description,
            'detection_method': 'enhanced_floor_plan_general',
            'doors': [e for e in elements if e['type'] in ['Door', 'Sliding Door']],
            'windows': [e for e in elements if e['type'] == 'Window'],
            'walls': [e for e in elements if e['type'] == 'Wall'],
            'estimated_dimensions': {
                'width_m': img_width * 0.05,
                'length_m': img_height * 0.05,
                'area_sqm': (img_width * img_height) * 0.0025,
                'estimated_ceiling_height_m': 2.5
            }
        }
    
    def _generate_general_floor_plan_description(self, element_counts: Dict[str, int], room_type: str, img_width: int, img_height: int) -> str:
        """Generate detailed description for general floor plan analysis"""
        total_elements = sum(element_counts.values())
        doors = element_counts.get('Door', 0) + element_counts.get('Sliding Door', 0)
        windows = element_counts.get('Window', 0)
        walls = element_counts.get('Wall', 0)
        stairs = element_counts.get('Stair Case', 0)
        
        # Calculate floor plan area and proportions
        area_sqm = (img_width * img_height) * 0.0025  # Rough conversion
        aspect_ratio = max(img_width, img_height) / min(img_width, img_height)
        
        description = f"This {room_type.lower()} encompasses the entire architectural layout"
        
        # Add area description
        if area_sqm < 50:
            description += f" covering a compact {area_sqm:.0f} square meter area"
        elif area_sqm < 150:
            description += f" spanning a moderate {area_sqm:.0f} square meter footprint"
        else:
            description += f" extending across a spacious {area_sqm:.0f} square meter area"
        
        # Add proportion description
        if aspect_ratio > 2.0:
            description += f" with an elongated rectangular layout (aspect ratio {aspect_ratio:.1f}:1)"
        elif aspect_ratio < 1.3:
            description += f" featuring a balanced, nearly square configuration"
        else:
            description += f" arranged in a rectangular format"
        
        # Detailed element analysis
        description += f". The floor plan contains {total_elements} architectural elements: "
        
        element_details = []
        if doors > 0:
            if doors >= 4:
                element_details.append(f"{doors} doors providing extensive connectivity between spaces")
            elif doors >= 2:
                element_details.append(f"{doors} doors facilitating good circulation flow")
            else:
                element_details.append(f"{doors} door offering basic access")
        
        if windows > 0:
            if windows >= 6:
                element_details.append(f"{windows} windows ensuring abundant natural lighting throughout")
            elif windows >= 3:
                element_details.append(f"{windows} windows providing good natural illumination")
            else:
                element_details.append(f"{windows} window{'s' if windows > 1 else ''} for natural light")
        
        if walls > 0:
            element_details.append(f"{walls} structural wall{'s' if walls > 1 else ''}")
        
        if stairs > 0:
            element_details.append(f"{stairs} staircase{'s' if stairs > 1 else ''} for vertical circulation")
        
        # Add other elements
        other_elements = {k: v for k, v in element_counts.items() if k not in ['Door', 'Sliding Door', 'Window', 'Wall', 'Stair Case'] and v > 0}
        for elem_type, count in other_elements.items():
            element_details.append(f"{count} {elem_type.lower()}{'s' if count > 1 else ''}")
        
        if element_details:
            description += ', '.join(element_details)
        
        # Functional analysis
        if stairs > 0 and doors >= 2:
            description += ". This multi-level design suggests a complex residential or commercial space with vertical circulation and multiple functional zones"
        elif doors >= 4:
            description += ". The high number of access points indicates an open, highly connected layout suitable for public or commercial use"
        elif windows >= doors and windows > 2:
            description += ". The emphasis on natural lighting suggests a design prioritizing comfort and energy efficiency"
        elif doors <= 2 and walls >= 3:
            description += ". The limited access points and substantial wall structure indicate a more private, enclosed design"
        
        return description
    
    def _generate_summary(self, object_counts, room_count) -> str:
        """Generate analysis summary"""
        total_elements = sum(object_counts.values())
        
        summary_parts = []
        if room_count > 0:
            summary_parts.append(f"{room_count} rooms")
        
        for element_type, count in object_counts.items():
            if count > 0:
                summary_parts.append(f"{count} {element_type.lower()}{'s' if count > 1 else ''}")
        
        if summary_parts:
            return f"Detected {', '.join(summary_parts)}"
        else:
            return "No architectural elements detected"
    
    # ===== ROOM ANNOTATION METHODS (Similar to Flutter Interactive Drawing) =====
    
    async def create_room_annotation(self, image_bytes: bytes, room_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a room annotation with drawing capabilities similar to Flutter interface
        
        Args:
            image_bytes: Floor plan image as bytes
            room_data: Room annotation data with coordinates and properties
        
        Returns:
            Created room annotation with updated visualization
        """
        print(f"🎨 Creating room annotation: {room_data.get('drawing_tool', 'unknown')} tool")
        
        try:
            # Load image to get dimensions
            image = Image.open(io.BytesIO(image_bytes))
            image_dimensions = (image.width, image.height)
            
            drawing_tool = room_data.get('drawing_tool', 'rectangle')
            room_type = room_data.get('room_type', 'Room')
            room_name = room_data.get('room_name', f'{room_type} {len(room_data.get("existing_rooms", [])) + 1}')
            
            if drawing_tool == 'rectangle':
                # Extract rectangle coordinates
                top_left = room_data.get('top_left', (0, 0))
                bottom_right = room_data.get('bottom_right', (100, 100))
                
                if isinstance(top_left, dict):
                    top_left = (top_left['x'], top_left['y'])
                if isinstance(bottom_right, dict):
                    bottom_right = (bottom_right['x'], bottom_right['y'])
                
                room_annotation = self.room_annotation_manager.create_room_from_rectangle(
                    top_left, bottom_right, room_type, room_name, image_dimensions
                )
                
            elif drawing_tool == 'polygon':
                # Extract polygon points
                points = room_data.get('points', [])
                if not points:
                    raise ValueError("No points provided for polygon")
                
                # Convert points to tuples if they're dictionaries
                polygon_points = []
                for point in points:
                    if isinstance(point, dict):
                        polygon_points.append((point['x'], point['y']))
                    else:
                        polygon_points.append(tuple(point))
                
                room_annotation = self.room_annotation_manager.create_room_from_polygon(
                    polygon_points, room_type, room_name, image_dimensions
                )
            else:
                raise ValueError(f"Unsupported drawing tool: {drawing_tool}")
            
            print(f"✅ Room annotation created: {room_annotation['name']} ({room_annotation['area_pixels']} px²)")
            
            return {
                'success': True,
                'room_annotation': room_annotation,
                'drawing_tool': drawing_tool,
                'image_dimensions': {'width': image_dimensions[0], 'height': image_dimensions[1]}
            }
            
        except Exception as e:
            print(f"❌ Error creating room annotation: {str(e)}")
            return {
                'success': False,
                'error': str(e),
                'drawing_tool': room_data.get('drawing_tool', 'unknown')
            }
    
    async def update_room_annotation(self, room_id: str, room_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Update an existing room annotation
        
        Args:
            room_id: ID of room to update
            room_data: Updated room data
        
        Returns:
            Updated room annotation data
        """
        print(f"📝 Updating room annotation: {room_id}")
        
        try:
            # Basic validation
            if not room_id:
                raise ValueError("Room ID is required")
            
            # Create updated room data (in real implementation, this would update stored data)
            updated_room = {
                'id': room_id,
                'name': room_data.get('name', 'Updated Room'),
                'type': room_data.get('type', 'Room'),
                'updated_at': datetime.now().isoformat(),
                **room_data
            }
            
            print(f"✅ Room annotation updated: {updated_room['name']}")
            return {
                'success': True,
                'room_annotation': updated_room
            }
            
        except Exception as e:
            print(f"❌ Error updating room annotation: {str(e)}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def delete_room_annotation(self, room_id: str) -> Dict[str, Any]:
        """
        Delete a room annotation
        
        Args:
            room_id: ID of room to delete
        
        Returns:
            Deletion confirmation
        """
        print(f"🗑️ Deleting room annotation: {room_id}")
        
        try:
            if not room_id:
                raise ValueError("Room ID is required")
            
            # In real implementation, this would delete from storage
            print(f"✅ Room annotation deleted: {room_id}")
            return {
                'success': True,
                'deleted_room_id': room_id
            }
            
        except Exception as e:
            print(f"❌ Error deleting room annotation: {str(e)}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def get_annotated_floor_plan(self, image_bytes: bytes, rooms: List[Dict[str, Any]], 
                                     show_labels: bool = True) -> Dict[str, Any]:
        """
        Get floor plan with room annotations drawn on it (similar to Flutter custom painter)
        
        Args:
            image_bytes: Original floor plan image
            rooms: List of room annotations
            show_labels: Whether to show room labels
        
        Returns:
            Annotated image data
        """
        print(f"🖼️ Generating annotated floor plan with {len(rooms)} rooms")
        
        try:
            # Draw rooms on image
            annotated_image_bytes = self.room_annotation_manager.draw_rooms_on_image(
                image_bytes, rooms, show_labels
            )
            
            # Convert to base64 for web display
            annotated_image_b64 = base64.b64encode(annotated_image_bytes).decode()
            annotated_image_b64 = f"data:image/png;base64,{annotated_image_b64}"
            
            print(f"✅ Annotated floor plan generated")
            return {
                'success': True,
                'annotated_image_base64': annotated_image_b64,
                'room_count': len(rooms),
                'show_labels': show_labels
            }
            
        except Exception as e:
            print(f"❌ Error generating annotated floor plan: {str(e)}")
            return {
                'success': False,
                'error': str(e)
            }
    
    async def save_floor_plan_with_annotations(self, image_bytes: bytes, rooms: List[Dict[str, Any]], 
                                             metadata: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Save complete floor plan with room annotations (similar to Flutter _proceedToSafetyAssessment)
        
        Args:
            image_bytes: Original floor plan image
            rooms: List of room annotations
            metadata: Additional metadata
        
        Returns:
            Save confirmation with annotation ID
        """
        print(f"💾 Saving floor plan with {len(rooms)} room annotations")
        
        try:
            # Load image for dimensions
            image = Image.open(io.BytesIO(image_bytes))
            
            # Generate annotation ID similar to Flutter
            annotation_id = f"enhanced_{int(datetime.now().timestamp() * 1000)}"
            
            # Prepare save data similar to Flutter format
            save_data = {
                'annotation_id': annotation_id,
                'rooms': rooms,
                'image_dimensions': {
                    'width': image.width,
                    'height': image.height
                },
                'total_rooms': len(rooms),
                'room_types': list(set(room.get('type', 'Unknown') for room in rooms)),
                'total_area_pixels': sum(room.get('area_pixels', 0) for room in rooms),
                'created_at': datetime.now().isoformat(),
                'drawing_tools_used': list(set(room.get('drawing_tool', 'unknown') for room in rooms)),
                'metadata': metadata or {}
            }
            
            # Generate room summary similar to Flutter _showRoomDataSummary
            room_summary = []
            for i, room in enumerate(rooms):
                summary = {
                    'index': i,
                    'id': room.get('id', f'room_{i}'),
                    'name': room.get('name', f'Room {i+1}'),
                    'type': room.get('type', 'Unknown'),
                    'area_pixels': room.get('area_pixels', 0),
                    'size_description': room.get('size_description', 'Unknown'),
                    'position': room.get('placement', {}).get('position_description', 'Unknown'),
                    'drawing_tool': room.get('drawing_tool', 'unknown')
                }
                room_summary.append(summary)
            
            save_data['room_summary'] = room_summary
            
            print(f"✅ Floor plan saved with annotation ID: {annotation_id}")
            return {
                'success': True,
                'annotation_id': annotation_id,
                'save_data': save_data,
                'room_summary': room_summary
            }
            
        except Exception as e:
            print(f"❌ Error saving floor plan: {str(e)}")
            return {
                'success': False,
                'error': str(e)
            }
    
    def get_available_room_types(self) -> List[str]:
        """Get list of available room types for annotation (similar to Flutter _roomTypes)"""
        return self.room_annotation_manager.room_types
    
    def validate_room_coordinates(self, room_data: Dict[str, Any], image_dimensions: Tuple[int, int]) -> Dict[str, Any]:
        """
        Validate room coordinates are within image bounds
        
        Args:
            room_data: Room data with coordinates
            image_dimensions: (width, height) of image
        
        Returns:
            Validation result
        """
        img_width, img_height = image_dimensions
        errors = []
        
        drawing_tool = room_data.get('drawing_tool', 'rectangle')
        
        if drawing_tool == 'rectangle':
            top_left = room_data.get('top_left', (0, 0))
            bottom_right = room_data.get('bottom_right', (100, 100))
            
            if isinstance(top_left, dict):
                top_left = (top_left['x'], top_left['y'])
            if isinstance(bottom_right, dict):
                bottom_right = (bottom_right['x'], bottom_right['y'])
            
            # Check bounds
            if not (0 <= top_left[0] < img_width and 0 <= top_left[1] < img_height):
                errors.append(f"Top left coordinate {top_left} is outside image bounds")
            if not (0 <= bottom_right[0] < img_width and 0 <= bottom_right[1] < img_height):
                errors.append(f"Bottom right coordinate {bottom_right} is outside image bounds")
            
            # Check rectangle size
            width = abs(bottom_right[0] - top_left[0])
            height = abs(bottom_right[1] - top_left[1])
            if width < 10 or height < 10:
                errors.append(f"Rectangle too small: {width}x{height} pixels")
        
        elif drawing_tool == 'polygon':
            points = room_data.get('points', [])
            if len(points) < 3:
                errors.append("Polygon must have at least 3 points")
            
            for i, point in enumerate(points):
                if isinstance(point, dict):
                    x, y = point['x'], point['y']
                else:
                    x, y = point
                
                if not (0 <= x < img_width and 0 <= y < img_height):
                    errors.append(f"Point {i} at ({x}, {y}) is outside image bounds")
        
        return {
            'valid': len(errors) == 0,
            'errors': errors,
            'image_dimensions': {'width': img_width, 'height': img_height}
        }

# Global instance - will be initialized when model path is provided
enhanced_floor_plan_service = None

def initialize_enhanced_service(model_path: str):
    """Initialize the global enhanced service with a model path"""
    global enhanced_floor_plan_service
    enhanced_floor_plan_service = EnhancedFloorPlanService(model_path)
    return enhanced_floor_plan_service

# Auto-load model if path file exists (persistent across reloads)
import os
MODEL_PATH_FILE = os.path.join(os.path.dirname(__file__), "../models/ENHANCED_MODEL_PATH.txt")
if os.path.exists(MODEL_PATH_FILE):
    with open(MODEL_PATH_FILE) as f:
        path = f.read().strip()
        if os.path.exists(path):
            enhanced_floor_plan_service = EnhancedFloorPlanService(path) 