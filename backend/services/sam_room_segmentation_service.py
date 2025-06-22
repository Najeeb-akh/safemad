"""
SAM Room Segmentation Service

Integrates Meta's Segment Anything Model (SAM) for intelligent room segmentation
in floor plans, working in conjunction with YOLO architectural element detection.
"""

import io
import os
import cv2
import numpy as np
from PIL import Image
import torch
from typing import List, Dict, Any, Optional, Tuple
import logging

# SAM imports
try:
    from segment_anything import sam_model_registry, SamPredictor, SamAutomaticMaskGenerator
    from segment_anything.utils.onnx import SamOnnxModel
    SAM_AVAILABLE = True
except ImportError:
    print("⚠️ SAM not available. Install with: pip install segment-anything")
    SAM_AVAILABLE = False

# Additional utilities
try:
    import supervision as sv
    SUPERVISION_AVAILABLE = True
except ImportError:
    print("⚠️ Supervision not available for enhanced visualization")
    SUPERVISION_AVAILABLE = False

class SAMRoomSegmentationService:
    """
    Service for segmenting rooms in floor plans using SAM,
    guided by architectural elements detected by YOLO
    """
    
    def __init__(self, sam_checkpoint_path: Optional[str] = None, model_type: str = "vit_h"):
        """
        Initialize SAM room segmentation service
        
        Args:
            sam_checkpoint_path: Path to SAM model checkpoint
            model_type: SAM model type ('vit_h', 'vit_l', 'vit_b')
        """
        self.sam_predictor = None
        self.mask_generator = None
        self.model_type = model_type
        self.sam_checkpoint_path = sam_checkpoint_path
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        
        if SAM_AVAILABLE:
            self._initialize_sam()
        else:
            print("❌ SAM not available - room segmentation will be disabled")
    
    def _initialize_sam(self):
        """Initialize SAM model and predictor"""
        try:
            # Try to find SAM checkpoint
            if not self.sam_checkpoint_path:
                self.sam_checkpoint_path = self._find_sam_checkpoint()
            
            if not self.sam_checkpoint_path or not os.path.exists(self.sam_checkpoint_path):
                print("⚠️ SAM checkpoint not found. Please download SAM model checkpoint.")
                print("Download from: https://github.com/facebookresearch/segment-anything#model-checkpoints")
                return
            
            # Load SAM model
            sam = sam_model_registry[self.model_type](checkpoint=self.sam_checkpoint_path)
            sam.to(device=self.device)
            
            # Initialize predictor and mask generator
            self.sam_predictor = SamPredictor(sam)
            self.mask_generator = SamAutomaticMaskGenerator(
                model=sam,
                points_per_side=16,  # Reduced for floor plans
                pred_iou_thresh=0.7,  # Higher threshold for cleaner segments
                stability_score_thresh=0.8,
                crop_n_layers=1,
                crop_n_points_downscale_factor=2,
                min_mask_region_area=1000,  # Minimum area for room segments
            )
            
            print(f"✅ SAM model ({self.model_type}) initialized successfully")
            
        except Exception as e:
            print(f"❌ Failed to initialize SAM: {e}")
            self.sam_predictor = None
            self.mask_generator = None
    
    def _find_sam_checkpoint(self) -> Optional[str]:
        """Try to find SAM checkpoint in common locations"""
        possible_paths = [
            "backend/models/sam_vit_h_4b8939.pth",
            "backend/models/sam_vit_l_0b3195.pth", 
            "backend/models/sam_vit_b_01ec64.pth",
            "sam_vit_h_4b8939.pth",
            "sam_vit_l_0b3195.pth",
            "sam_vit_b_01ec64.pth"
        ]
        
        for path in possible_paths:
            if os.path.exists(path):
                print(f"🔍 Found SAM checkpoint: {path}")
                return path
        
        return None
    
    async def segment_rooms_with_architectural_guidance(
        self, 
        image_bytes: bytes, 
        architectural_elements: List[Dict[str, Any]],
        confidence_threshold: float = 0.7
    ) -> Dict[str, Any]:
        """
        Segment rooms using SAM with guidance from YOLO-detected architectural elements
        
        Args:
            image_bytes: Floor plan image as bytes
            architectural_elements: List of detected doors, windows, walls, etc. from YOLO
            confidence_threshold: Threshold for segment quality
            
        Returns:
            Dictionary containing room segments and metadata
        """
        if not self.sam_predictor or not self.mask_generator:
            return {
                'room_segments': [],
                'error': 'SAM not available or not properly initialized',
                'segmentation_method': 'sam_unavailable'
            }
        
        try:
            # Convert bytes to image
            image = Image.open(io.BytesIO(image_bytes))
            image_np = np.array(image)
            
            # Convert to RGB if needed
            if len(image_np.shape) == 3 and image_np.shape[2] == 4:
                image_np = cv2.cvtColor(image_np, cv2.COLOR_RGBA2RGB)
            elif len(image_np.shape) == 3 and image_np.shape[2] == 3:
                image_np = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
            
            print(f"🖼️ Processing image: {image_np.shape}")
            
            # Set image for SAM predictor
            self.sam_predictor.set_image(image_np)
            
            # Generate automatic masks
            masks = self.mask_generator.generate(image_np)
            print(f"🎭 Generated {len(masks)} initial segments")
            
            # Filter and refine masks based on architectural elements
            room_segments = self._refine_segments_with_architecture(
                masks, architectural_elements, image_np.shape[:2]
            )
            
            # Post-process segments
            final_segments = self._post_process_room_segments(room_segments, image_np.shape[:2])
            
            # Create visualizations
            visualization = self._create_segmentation_visualization(image_np, final_segments)
            individual_visualizations = self._create_individual_visualizations(image_np, final_segments)
            
            print(f"✅ Successfully segmented {len(final_segments)} rooms")
            
            return {
                'room_segments': final_segments,
                'total_rooms': len(final_segments),
                'segmentation_method': 'sam_with_architectural_guidance',
                'image_dimensions': {'width': image_np.shape[1], 'height': image_np.shape[0]},
                'architectural_elements_used': len(architectural_elements),
                'visualization': visualization,
                'individual_visualizations': individual_visualizations,
                'metadata': {
                    'sam_model': self.model_type,
                    'device': str(self.device),
                    'total_initial_masks': len(masks),
                    'confidence_threshold': confidence_threshold
                }
            }
            
        except Exception as e:
            print(f"❌ Error during room segmentation: {e}")
            return {
                'room_segments': [],
                'error': str(e),
                'segmentation_method': 'sam_failed'
            }
    
    def _refine_segments_with_architecture(
        self, 
        masks: List[Dict], 
        architectural_elements: List[Dict[str, Any]], 
        image_shape: Tuple[int, int]
    ) -> List[Dict[str, Any]]:
        """
        Refine SAM segments using architectural element information
        """
        print(f"🔧 Refining {len(masks)} segments with {len(architectural_elements)} architectural elements")
        
        refined_segments = []
        
        # Extract doors and walls for room boundary analysis
        doors = [elem for elem in architectural_elements if elem.get('type') in ['Door', 'Sliding Door']]
        walls = [elem for elem in architectural_elements if elem.get('type') == 'Wall']
        
        for i, mask in enumerate(masks):
            segment_mask = mask['segmentation']
            
            # Calculate segment properties
            area = np.sum(segment_mask)
            bbox = mask['bbox']  # [x, y, width, height]
            stability_score = mask.get('stability_score', 0)
            
            # Filter out small segments (likely not rooms)
            if area < 5000:  # Minimum room area in pixels
                continue
            
            # Filter based on stability score
            if stability_score < 0.7:
                continue
            
            # Analyze relationship with architectural elements
            room_info = self._analyze_room_segment(segment_mask, doors, walls, image_shape)
            
            # Create room segment data
            room_segment = {
                'segment_id': i,
                'mask': segment_mask,
                'area': int(area),
                'bbox': {
                    'x': int(bbox[0]),
                    'y': int(bbox[1]), 
                    'width': int(bbox[2]),
                    'height': int(bbox[3])
                },
                'stability_score': float(stability_score),
                'room_info': room_info,
                'centroid': self._calculate_centroid(segment_mask),
                'perimeter': self._calculate_perimeter(segment_mask)
            }
            
            refined_segments.append(room_segment)
        
        # Sort by area (largest rooms first)
        refined_segments.sort(key=lambda x: x['area'], reverse=True)
        
        return refined_segments
    
    def _analyze_room_segment(
        self, 
        segment_mask: np.ndarray, 
        doors: List[Dict], 
        walls: List[Dict], 
        image_shape: Tuple[int, int]
    ) -> Dict[str, Any]:
        """
        Analyze a room segment's relationship with architectural elements
        """
        # Find doors that intersect with this segment
        intersecting_doors = []
        for door in doors:
            if self._element_intersects_segment(door, segment_mask):
                intersecting_doors.append(door)
        
        # Find walls that bound this segment
        bounding_walls = []
        for wall in walls:
            if self._element_near_segment_boundary(wall, segment_mask):
                bounding_walls.append(wall)
        
        # Classify room type based on doors and size
        room_type = self._classify_room_type(segment_mask, intersecting_doors, bounding_walls)
        
        return {
            'room_type': room_type,
            'door_count': len(intersecting_doors),
            'wall_count': len(bounding_walls),
            'access_points': intersecting_doors,
            'boundaries': bounding_walls,
            'is_main_room': len(intersecting_doors) > 1,  # Rooms with multiple doors are often main rooms
            'estimated_function': self._estimate_room_function(segment_mask, intersecting_doors)
        }
    
    def _element_intersects_segment(self, element: Dict, segment_mask: np.ndarray) -> bool:
        """Check if an architectural element intersects with a room segment"""
        bbox = element.get('bbox', {})
        if not bbox:
            return False
        
        x1, y1 = int(bbox.get('x1', 0)), int(bbox.get('y1', 0))
        x2, y2 = int(bbox.get('x2', 0)), int(bbox.get('y2', 0))
        
        # Check if any part of the element bbox overlaps with the segment
        if (0 <= y1 < segment_mask.shape[0] and 0 <= x1 < segment_mask.shape[1] and
            0 <= y2 < segment_mask.shape[0] and 0 <= x2 < segment_mask.shape[1]):
            
            element_region = segment_mask[y1:y2, x1:x2]
            return np.any(element_region)
        
        return False
    
    def _element_near_segment_boundary(self, element: Dict, segment_mask: np.ndarray, threshold: int = 10) -> bool:
        """Check if an element is near the boundary of a segment"""
        # Find segment boundary
        edges = cv2.Canny(segment_mask.astype(np.uint8) * 255, 50, 150)
        
        bbox = element.get('bbox', {})
        if not bbox:
            return False
        
        center_x = int((bbox.get('x1', 0) + bbox.get('x2', 0)) / 2)
        center_y = int((bbox.get('y1', 0) + bbox.get('y2', 0)) / 2)
        
        # Check if element center is near any edge
        if (0 <= center_y < edges.shape[0] and 0 <= center_x < edges.shape[1]):
            # Check surrounding area for edges
            y1, y2 = max(0, center_y - threshold), min(edges.shape[0], center_y + threshold)
            x1, x2 = max(0, center_x - threshold), min(edges.shape[1], center_x + threshold)
            
            return np.any(edges[y1:y2, x1:x2])
        
        return False
    
    def _classify_room_type(self, segment_mask: np.ndarray, doors: List, walls: List) -> str:
        """Classify room type based on segment characteristics"""
        area = np.sum(segment_mask)
        door_count = len(doors)
        
        if door_count == 0:
            return "Enclosed Space"
        elif door_count == 1:
            if area > 20000:
                return "Large Room"
            else:
                return "Small Room" 
        elif door_count == 2:
            return "Connecting Room"
        else:
            return "Main Area"
    
    def _estimate_room_function(self, segment_mask: np.ndarray, doors: List) -> str:
        """Estimate room function based on characteristics"""
        area = np.sum(segment_mask)
        door_count = len(doors)
        
        # Simple heuristic-based classification
        if door_count == 0:
            return "Storage/Utility"
        elif door_count == 1 and area < 15000:
            return "Bedroom/Office"
        elif door_count == 1 and area >= 15000:
            return "Living Room"
        elif door_count >= 2:
            return "Common Area"
        else:
            return "General Room"
    
    def _calculate_centroid(self, mask: np.ndarray) -> Dict[str, int]:
        """Calculate centroid of a mask"""
        y_coords, x_coords = np.where(mask)
        if len(x_coords) == 0:
            return {'x': 0, 'y': 0}
        
        centroid_x = int(np.mean(x_coords))
        centroid_y = int(np.mean(y_coords))
        return {'x': centroid_x, 'y': centroid_y}
    
    def _calculate_perimeter(self, mask: np.ndarray) -> int:
        """Calculate perimeter of a mask"""
        contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if contours:
            return int(cv2.arcLength(contours[0], True))
        return 0
    
    def _post_process_room_segments(self, segments: List[Dict], image_shape: Tuple[int, int]) -> List[Dict[str, Any]]:
        """Post-process room segments for better results"""
        if not segments:
            return []
        
        print(f"🔄 Post-processing {len(segments)} room segments")
        
        # Remove overlapping segments (keep the one with higher stability score)
        cleaned_segments = self._remove_overlapping_segments(segments)
        
        # Add additional metadata
        for i, segment in enumerate(cleaned_segments):
            segment['room_id'] = i
            segment['room_name'] = f"Room {i+1}"
            segment['area_percentage'] = (segment['area'] / (image_shape[0] * image_shape[1])) * 100
            
        return cleaned_segments
    
    def _remove_overlapping_segments(self, segments: List[Dict]) -> List[Dict]:
        """Remove overlapping segments, keeping the better one"""
        if len(segments) <= 1:
            return segments
        
        non_overlapping = []
        
        for segment in segments:
            overlap_found = False
            current_mask = segment['mask']
            
            for existing in non_overlapping:
                existing_mask = existing['mask']
                
                # Calculate overlap
                intersection = np.logical_and(current_mask, existing_mask)
                overlap_ratio = np.sum(intersection) / min(np.sum(current_mask), np.sum(existing_mask))
                
                if overlap_ratio > 0.3:  # 30% overlap threshold
                    overlap_found = True
                    # Keep the segment with higher stability score
                    if segment['stability_score'] > existing['stability_score']:
                        non_overlapping.remove(existing)
                        non_overlapping.append(segment)
                    break
            
            if not overlap_found:
                non_overlapping.append(segment)
        
        return non_overlapping
    
    def _create_segmentation_visualization(self, image: np.ndarray, segments: List[Dict]) -> str:
        """Create visualization of room segmentation similar to official SAM repository"""
        try:
            # Create multiple visualizations similar to official SAM
            visualizations = self._create_sam_style_visualizations(image, segments)
            
            # Create a composite visualization showing all views
            composite = self._create_composite_visualization(visualizations)
            
            # Convert to base64 for web display
            return self._image_to_base64(composite)
            
        except Exception as e:
            print(f"⚠️ Error creating visualization: {e}")
            return ""

    def _create_individual_visualizations(self, image: np.ndarray, segments: List[Dict]) -> Dict[str, str]:
        """Create individual visualization images for Flutter display"""
        try:
            # Create multiple visualizations similar to official SAM
            visualizations = self._create_sam_style_visualizations(image, segments)
            
            # Convert each visualization to base64
            individual_viz = {}
            for key, viz_image in visualizations.items():
                individual_viz[key] = self._image_to_base64(viz_image)
            
            return individual_viz
            
        except Exception as e:
            print(f"⚠️ Error creating individual visualizations: {e}")
            return {}
    
    def _create_sam_style_visualizations(self, image: np.ndarray, segments: List[Dict]) -> Dict[str, np.ndarray]:
        """Create multiple SAM-style visualizations"""
        visualizations = {}
        
        # 1. Original image
        visualizations['original'] = image.copy()
        
        # 2. All masks overlay (like official SAM)
        visualizations['masks_overlay'] = self._create_masks_overlay(image, segments)
        
        # 3. Individual colored segments
        visualizations['colored_segments'] = self._create_colored_segments(image, segments)
        
        # 4. Mask boundaries only
        visualizations['boundaries'] = self._create_boundaries_visualization(image, segments)
        
        # 5. Segmentation with labels
        visualizations['labeled_segments'] = self._create_labeled_segments(image, segments)
        
        return visualizations
    
    def _create_masks_overlay(self, image: np.ndarray, segments: List[Dict]) -> np.ndarray:
        """Create mask overlay similar to official SAM examples"""
        overlay = image.copy()
        
        # Create a combined mask for all segments
        combined_mask = np.zeros(image.shape[:2], dtype=np.uint8)
        
        # Generate distinct colors for each segment
        colors = self._generate_sam_colors(len(segments))
        
        for i, segment in enumerate(segments):
            mask = segment['mask'].astype(np.uint8)
            color = colors[i]
            
            # Apply transparent colored overlay
            colored_mask = np.zeros_like(image)
            colored_mask[mask > 0] = color
            
            # Blend with original image
            alpha = 0.4
            overlay = cv2.addWeighted(overlay, 1 - alpha, colored_mask, alpha, 0)
            
            # Add to combined mask
            combined_mask[mask > 0] = (i + 1) * 50  # Different intensity for each segment
        
        return overlay
    
    def _create_colored_segments(self, image: np.ndarray, segments: List[Dict]) -> np.ndarray:
        """Create colored segments with clear boundaries"""
        result = image.copy()
        colors = self._generate_sam_colors(len(segments))
        
        for i, segment in enumerate(segments):
            mask = segment['mask'].astype(np.uint8)
            color = colors[i]
            
            # Fill segment with color
            result[mask > 0] = color
            
            # Draw boundary
            contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(result, contours, -1, (255, 255, 255), 2)
        
        return result
    
    def _create_boundaries_visualization(self, image: np.ndarray, segments: List[Dict]) -> np.ndarray:
        """Create boundaries-only visualization"""
        result = image.copy()
        colors = self._generate_sam_colors(len(segments))
        
        for i, segment in enumerate(segments):
            mask = segment['mask'].astype(np.uint8)
            color = colors[i]
            
            # Find and draw contours
            contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(result, contours, -1, color, 3)
        
        return result
    
    def _create_labeled_segments(self, image: np.ndarray, segments: List[Dict]) -> np.ndarray:
        """Create labeled segments with room information"""
        result = self._create_masks_overlay(image, segments)
        
        for i, segment in enumerate(segments):
            centroid = segment['centroid']
            room_info = segment.get('room_info', {})
            
            # Room label
            label = f"Room {i+1}"
            room_type = room_info.get('room_type', 'Unknown')
            if room_type != 'Unknown':
                label += f"\n{room_type}"
            
            # Add area information
            area_pct = segment.get('area_percentage', 0)
            label += f"\n{area_pct:.1f}%"
            
            # Draw label background
            font = cv2.FONT_HERSHEY_SIMPLEX
            font_scale = 0.5
            thickness = 2
            
            # Calculate text size
            lines = label.split('\n')
            text_sizes = [cv2.getTextSize(line, font, font_scale, thickness)[0] for line in lines]
            max_width = max(size[0] for size in text_sizes)
            total_height = sum(size[1] for size in text_sizes) + (len(lines) - 1) * 5
            
            # Draw background rectangle
            x, y = centroid['x'] - max_width//2, centroid['y'] - total_height//2
            cv2.rectangle(result, (x-5, y-5), (x + max_width + 10, y + total_height + 10), 
                         (0, 0, 0), -1)
            cv2.rectangle(result, (x-5, y-5), (x + max_width + 10, y + total_height + 10), 
                         (255, 255, 255), 2)
            
            # Draw text lines
            current_y = y + text_sizes[0][1]
            for line in lines:
                cv2.putText(result, line, (x, current_y), font, font_scale, (255, 255, 255), thickness)
                current_y += text_sizes[0][1] + 5
        
        return result
    
    def _create_composite_visualization(self, visualizations: Dict[str, np.ndarray]) -> np.ndarray:
        """Create a composite visualization showing multiple views"""
        # Get dimensions
        h, w = visualizations['original'].shape[:2]
        
        # Create a 2x3 grid layout
        grid_h, grid_w = 2, 3
        cell_h, cell_w = h // grid_h, w // grid_w
        
        # Create composite image
        composite = np.zeros((h, w * 2, 3), dtype=np.uint8)
        
        # Resize all visualizations to fit grid
        viz_keys = ['original', 'masks_overlay', 'colored_segments', 'boundaries', 'labeled_segments']
        
        # Left side: Original image (full height)
        original_resized = cv2.resize(visualizations['original'], (w, h))
        composite[:h, :w] = original_resized
        
        # Right side: 2x2 grid of other visualizations
        grid_size = h // 2
        
        # Top row
        if 'masks_overlay' in visualizations:
            masks_resized = cv2.resize(visualizations['masks_overlay'], (grid_size, grid_size))
            composite[:grid_size, w:w+grid_size] = masks_resized
        
        if 'colored_segments' in visualizations:
            colored_resized = cv2.resize(visualizations['colored_segments'], (grid_size, grid_size))
            composite[:grid_size, w+grid_size:w+2*grid_size] = colored_resized
        
        # Bottom row
        if 'boundaries' in visualizations:
            boundaries_resized = cv2.resize(visualizations['boundaries'], (grid_size, grid_size))
            composite[grid_size:h, w:w+grid_size] = boundaries_resized
        
        if 'labeled_segments' in visualizations:
            labeled_resized = cv2.resize(visualizations['labeled_segments'], (grid_size, grid_size))
            composite[grid_size:h, w+grid_size:w+2*grid_size] = labeled_resized
        
        # Add titles to each section
        self._add_visualization_titles(composite, w, h, grid_size)
        
        return composite
    
    def _add_visualization_titles(self, composite: np.ndarray, w: int, h: int, grid_size: int):
        """Add titles to each visualization section"""
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 0.8
        thickness = 2
        color = (255, 255, 255)
        
        titles = [
            ("Original Image", (10, 30)),
            ("SAM Masks Overlay", (w + 10, 30)),
            ("Colored Segments", (w + grid_size + 10, 30)),
            ("Boundaries Only", (w + 10, grid_size + 30)),
            ("Labeled Segments", (w + grid_size + 10, grid_size + 30))
        ]
        
        for title, (x, y) in titles:
            # Add background
            text_size = cv2.getTextSize(title, font, font_scale, thickness)[0]
            cv2.rectangle(composite, (x-5, y-25), (x + text_size[0] + 10, y + 5), (0, 0, 0), -1)
            cv2.putText(composite, title, (x, y), font, font_scale, color, thickness)
    
    def _generate_sam_colors(self, num_segments: int) -> List[Tuple[int, int, int]]:
        """Generate distinct colors similar to official SAM visualization"""
        colors = []
        
        # Use a predefined set of distinct colors for better visibility
        base_colors = [
            (255, 0, 0),     # Red
            (0, 255, 0),     # Green
            (0, 0, 255),     # Blue
            (255, 255, 0),   # Yellow
            (255, 0, 255),   # Magenta
            (0, 255, 255),   # Cyan
            (255, 128, 0),   # Orange
            (128, 0, 255),   # Purple
            (255, 192, 203), # Pink
            (0, 128, 128),   # Teal
            (128, 128, 0),   # Olive
            (128, 0, 128),   # Maroon
        ]
        
        # If we need more colors, generate them systematically
        for i in range(num_segments):
            if i < len(base_colors):
                colors.append(base_colors[i])
            else:
                # Generate additional colors using HSV
                import colorsys
                hue = (i * 137.5) % 360  # Golden angle for better distribution
                rgb = colorsys.hsv_to_rgb(hue/360.0, 0.8, 0.9)
                colors.append(tuple(int(c * 255) for c in rgb))
        
        return colors
    
    def _image_to_base64(self, image: np.ndarray) -> str:
        """Convert image to base64 string"""
        try:
            image_pil = Image.fromarray(image.astype(np.uint8))
            buffer = io.BytesIO()
            image_pil.save(buffer, format='PNG')
            import base64
            img_base64 = base64.b64encode(buffer.getvalue()).decode()
            return f"data:image/png;base64,{img_base64}"
        except:
            return ""

    async def segment_room_with_point_prompt(
        self,
        image_bytes: bytes,
        point_coords: List[List[int]],
        point_labels: Optional[List[int]] = None,
        multimask_output: bool = True
    ) -> Dict[str, Any]:
        """
        Segment room using point prompts (similar to EfficientViTSAM --mode point)
        
        Args:
            image_bytes: Floor plan image as bytes
            point_coords: List of [x, y] coordinates where user clicked
            point_labels: List of labels (1 for positive, 0 for negative points)
            multimask_output: Whether to output multiple masks
            
        Returns:
            Dictionary containing segmentation results and visualization
        """
        if not self.sam_predictor:
            return {
                'masks': [],
                'error': 'SAM not available or not properly initialized',
                'segmentation_method': 'sam_unavailable'
            }
        
        try:
            # Convert bytes to image
            image = Image.open(io.BytesIO(image_bytes))
            image_np = np.array(image)
            
            # Convert to RGB if needed
            if len(image_np.shape) == 3 and image_np.shape[2] == 4:
                image_np = cv2.cvtColor(image_np, cv2.COLOR_RGBA2RGB)
            elif len(image_np.shape) == 3 and image_np.shape[2] == 3:
                image_np = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
            
            print(f"🖼️ Processing image with point prompts: {image_np.shape}")
            print(f"📍 Point coordinates: {point_coords}")
            
            # Set image for SAM predictor
            self.sam_predictor.set_image(image_np)
            
            # Prepare point inputs
            input_points = np.array(point_coords)
            
            # Default to positive points if labels not provided
            if point_labels is None:
                input_labels = np.ones(len(point_coords), dtype=int)
            else:
                input_labels = np.array(point_labels)
            
            print(f"🎯 Using {len(input_points)} points with labels {input_labels}")
            
            # Generate masks using point prompts
            masks, scores, logits = self.sam_predictor.predict(
                point_coords=input_points,
                point_labels=input_labels,
                multimask_output=multimask_output
            )
            
            print(f"🎭 Generated {len(masks)} masks from point prompts")
            
            # Process and format results
            mask_results = []
            for i, (mask, score) in enumerate(zip(masks, scores)):
                # Calculate mask properties
                area = np.sum(mask)
                bbox = self._calculate_bbox_from_mask(mask)
                centroid = self._calculate_centroid(mask)
                perimeter = self._calculate_perimeter(mask)
                
                mask_result = {
                    'mask_id': i,
                    'mask': mask,
                    'score': float(score),
                    'area': int(area),
                    'bbox': bbox,
                    'centroid': centroid,
                    'perimeter': perimeter,
                    'area_percentage': (area / (image_np.shape[0] * image_np.shape[1])) * 100,
                    'input_points': point_coords,
                    'input_labels': input_labels.tolist()
                }
                
                mask_results.append(mask_result)
            
            # Sort by score (best mask first)
            mask_results.sort(key=lambda x: x['score'], reverse=True)
            
            # Create visualization
            visualization = self._create_point_segmentation_visualization(
                image_np, mask_results, input_points, input_labels
            )
            
            print(f"✅ Successfully generated {len(mask_results)} masks from point prompts")
            
            return {
                'masks': mask_results,
                'total_masks': len(mask_results),
                'segmentation_method': 'sam_point_prompt',
                'image_dimensions': {'width': image_np.shape[1], 'height': image_np.shape[0]},
                'visualization': visualization,
                'best_mask': mask_results[0] if mask_results else None,
                'metadata': {
                    'sam_model': self.model_type,
                    'device': str(self.device),
                    'multimask_output': multimask_output,
                    'point_count': len(point_coords)
                }
            }
            
        except Exception as e:
            print(f"❌ Error during point-based segmentation: {e}")
            return {
                'masks': [],
                'error': str(e),
                'segmentation_method': 'sam_point_failed'
            }

    def _calculate_bbox_from_mask(self, mask: np.ndarray) -> Dict[str, int]:
        """Calculate bounding box from mask"""
        try:
            # Find coordinates where mask is True
            coords = np.argwhere(mask)
            if len(coords) == 0:
                return {'x': 0, 'y': 0, 'width': 0, 'height': 0}
            
            # Get min/max coordinates
            y_min, x_min = coords.min(axis=0)
            y_max, x_max = coords.max(axis=0)
            
            return {
                'x': int(x_min),
                'y': int(y_min),
                'width': int(x_max - x_min),
                'height': int(y_max - y_min)
            }
        except:
            return {'x': 0, 'y': 0, 'width': 0, 'height': 0}

    def _create_point_segmentation_visualization(self, 
                                               image: np.ndarray, 
                                               mask_results: List[Dict], 
                                               input_points: np.ndarray,
                                               input_labels: np.ndarray) -> str:
        """Create visualization for point-based segmentation (EfficientViTSAM style)"""
        try:
            # Create figure with subplots (original + masks)
            fig_height = 8
            fig_width = 4 * len(mask_results) + 4  # Original + each mask
            
            import matplotlib.pyplot as plt
            fig, axes = plt.subplots(1, len(mask_results) + 1, figsize=(fig_width, fig_height))
            
            # Ensure axes is always a list
            if len(mask_results) == 0:
                axes = [axes] if not hasattr(axes, '__len__') else axes
            elif not hasattr(axes, '__len__'):
                axes = [axes]
            
            # Show original image with points
            ax_orig = axes[0]
            ax_orig.imshow(image)
            self._show_points(input_points, input_labels, ax_orig)
            ax_orig.set_title('Original with Points', fontsize=12, fontweight='bold')
            ax_orig.axis('off')
            
            # Show each mask
            colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]  # Red, Green, Blue
            for i, mask_result in enumerate(mask_results):
                if i + 1 < len(axes):
                    ax = axes[i + 1]
                    ax.imshow(image)
                    
                    # Show mask overlay
                    mask = mask_result['mask']
                    self._show_mask(mask, ax, color=colors[i % len(colors)])
                    
                    # Show points
                    self._show_points(input_points, input_labels, ax)
                    
                    # Add title with score
                    score = mask_result['score']
                    area_pct = mask_result['area_percentage']
                    ax.set_title(f'Mask {i+1}\nScore: {score:.3f}\nArea: {area_pct:.1f}%', 
                               fontsize=10, fontweight='bold')
                    ax.axis('off')
            
            # Save to bytes and convert to base64
            buffer = io.BytesIO()
            plt.tight_layout()
            plt.savefig(buffer, format='png', dpi=150, bbox_inches='tight')
            plt.close()
            
            buffer.seek(0)
            import base64
            img_base64 = base64.b64encode(buffer.getvalue()).decode()
            return f"data:image/png;base64,{img_base64}"
            
        except Exception as e:
            print(f"⚠️ Error creating point segmentation visualization: {e}")
            return ""

    def _show_points(self, coords: np.ndarray, labels: np.ndarray, ax, marker_size: int = 200):
        """Show points on plot (similar to official SAM visualization)"""
        try:
            pos_points = coords[labels == 1]
            neg_points = coords[labels == 0]
            
            # Show positive points (green stars)
            if len(pos_points) > 0:
                ax.scatter(pos_points[:, 0], pos_points[:, 1], 
                          color='green', marker='*', s=marker_size, 
                          edgecolor='white', linewidth=2, label='Positive')
            
            # Show negative points (red stars)  
            if len(neg_points) > 0:
                ax.scatter(neg_points[:, 0], neg_points[:, 1],
                          color='red', marker='*', s=marker_size,
                          edgecolor='white', linewidth=2, label='Negative')
        except Exception as e:
            print(f"⚠️ Error showing points: {e}")

    def _show_mask(self, mask: np.ndarray, ax, color: Tuple[int, int, int] = (30, 144, 255), alpha: float = 0.6):
        """Show mask overlay on plot (similar to official SAM visualization)"""
        try:
            # Normalize color to 0-1 range
            color_norm = tuple(c / 255.0 for c in color)
            color_with_alpha = color_norm + (alpha,)
            
            h, w = mask.shape[-2:]
            mask_image = mask.reshape(h, w, 1) * np.array(color_with_alpha).reshape(1, 1, -1)
            ax.imshow(mask_image)
        except Exception as e:
            print(f"⚠️ Error showing mask: {e}")

# Global service instance
sam_service = SAMRoomSegmentationService() if SAM_AVAILABLE else None 