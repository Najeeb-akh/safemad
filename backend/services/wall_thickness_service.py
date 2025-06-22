import cv2
import torch
import numpy as np
import base64
import io
from PIL import Image
from typing import Dict, List, Any, Tuple, Optional
from fastapi import HTTPException
import logging

# Optional scipy import for better filtering
try:
    from scipy.ndimage import gaussian_filter1d
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False

logger = logging.getLogger(__name__)

class WallThicknessAnalyzer:
    """
    Wall thickness analyzer using Depth Anything V2 for monocular depth estimation
    Based on: https://github.com/DepthAnything/Depth-Anything-V2
    """
    
    def __init__(self):
        self.device = 'cuda' if torch.cuda.is_available() else 'mps' if torch.backends.mps.is_available() else 'cpu'
        self.model = None
        self._load_depth_model()
    
    def _load_depth_model(self):
        """Load Depth Anything V2 model"""
        try:
            # Import from local Depth-Anything-V2 directory
            import sys
            import os
            depth_anything_v2_path = os.path.join(os.path.dirname(__file__), '..', 'Depth-Anything-V2')
            if depth_anything_v2_path not in sys.path:
                sys.path.insert(0, depth_anything_v2_path)
            
            from depth_anything_v2.dpt import DepthAnythingV2
            
            # Model configurations from the repository
            model_configs = {
                'vits': {'encoder': 'vits', 'features': 64, 'out_channels': [48, 96, 192, 384]},
                'vitb': {'encoder': 'vitb', 'features': 128, 'out_channels': [96, 192, 384, 768]},
                'vitl': {'encoder': 'vitl', 'features': 256, 'out_channels': [256, 512, 1024, 1024]},
                'vitg': {'encoder': 'vitg', 'features': 384, 'out_channels': [1536, 1536, 1536, 1536]}
            }
            
            # Use small model for efficiency (24.8M parameters)
            encoder = 'vits'
            
            # Initialize model
            self.model = DepthAnythingV2(**model_configs[encoder])
            
            # Load pretrained weights
            model_path = os.path.join(os.path.dirname(__file__), '..', 'models', f'depth_anything_v2_{encoder}.pth')
            try:
                self.model.load_state_dict(torch.load(model_path, map_location='cpu'))
                logger.info(f"Loaded Depth Anything V2 model from {model_path}")
            except FileNotFoundError:
                logger.warning(f"Model file not found at {model_path}. Please download the model first.")
                raise HTTPException(status_code=500, detail="Depth analysis model not available")
            
            self.model = self.model.to(self.device).eval()
            logger.info(f"Depth Anything V2 model loaded successfully on {self.device}")
            
        except ImportError:
            logger.error("Depth Anything V2 not installed. Please install the required dependencies.")
            raise HTTPException(status_code=500, detail="Depth analysis dependencies not available")
        except Exception as e:
            logger.error(f"Failed to load depth model: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to initialize depth analysis: {str(e)}")
    
    async def analyze_wall_thickness(self, image_bytes: bytes, room_id: str = None) -> Dict[str, Any]:
        """
        Main method to analyze wall thickness from door/window frame image
        
        Args:
            image_bytes: Raw image bytes
            room_id: Optional room identifier for context
            
        Returns:
            Dictionary containing wall thickness analysis results
        """
        try:
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Starting wall thickness analysis for room {room_id}")
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Image bytes length: {len(image_bytes)}")
            
            # 1. Load and preprocess image
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Step 1: Loading and preprocessing image...")
            image = self._load_image(image_bytes)
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Image loaded successfully - Shape: {image.shape}, Type: {image.dtype}")
            
            # 2. Generate depth map using Depth Anything V2
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Step 2: Generating depth map using Depth Anything V2...")
            depth_map = self._generate_depth_map(image)
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Depth map generated - Shape: {depth_map.shape}, Min: {depth_map.min():.3f}, Max: {depth_map.max():.3f}")
            
            # 3. Detect frame boundaries
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Step 3: Detecting frame boundaries...")
            frame_analysis = self._detect_frame_boundaries(image, depth_map)
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Frame boundaries detected - Orientation: {frame_analysis.get('frame_orientation', 'unknown')}, Lines: {frame_analysis.get('total_lines', 0)}")
            
            # 4. Extract wall thickness profile
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Step 4: Extracting wall thickness profile...")
            thickness_profile = self._extract_wall_thickness_profile(depth_map, frame_analysis)
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Thickness profile extracted - Sampling lines: {len(thickness_profile.get('measurements', []))}")
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Average thickness pixels: {thickness_profile.get('average_thickness_pixels', 0):.2f}")
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Average depth difference: {thickness_profile.get('average_depth_difference', 0):.6f}")
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Measurement consistency: {thickness_profile.get('measurement_consistency', 0):.2f}")
            
            # 5. Calculate real-world measurements
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Step 5: Calculating real-world measurements...")
            measurements = self._calculate_real_world_thickness(thickness_profile, frame_analysis)
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Measurements calculated - Thickness: {measurements['thickness_cm']:.2f} cm, Confidence: {measurements['confidence']:.3f}")
            
            # 6. Create visualization
            logger.info(f"🔍 [WALL THICKNESS DEBUG] Step 6: Creating visualization...")
            visualization = self._create_thickness_visualization(image, depth_map, frame_analysis, measurements)
            
            logger.info(f"Wall thickness analysis completed: {measurements['thickness_cm']} cm")
            
            # Convert numpy arrays to lists for JSON serialization
            def make_json_serializable(obj):
                if isinstance(obj, np.ndarray):
                    return obj.tolist()
                elif isinstance(obj, dict):
                    return {k: make_json_serializable(v) for k, v in obj.items()}
                elif isinstance(obj, list):
                    return [make_json_serializable(item) for item in obj]
                elif isinstance(obj, (np.int32, np.int64)):
                    return int(obj)
                elif isinstance(obj, (np.float32, np.float64)):
                    return float(obj)
                else:
                    return obj
            
            return {
                "success": True,
                "wall_thickness_cm": measurements["thickness_cm"],
                "confidence": measurements["confidence"],
                "measurement_points": measurements["points"],
                "depth_visualization": visualization,
                "frame_info": make_json_serializable(frame_analysis),
                "quality_metrics": make_json_serializable(measurements["quality"]),
                "calibration_method": measurements.get("calibration_method", "frame_reference")
            }
            
        except Exception as e:
            logger.error(f"Wall thickness analysis failed: {e}")
            raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")
    
    def _load_image(self, image_bytes: bytes) -> np.ndarray:
        """Load image from bytes and convert to OpenCV format"""
        try:
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] Converting {len(image_bytes)} bytes to PIL Image...")
            # Convert bytes to PIL Image
            image = Image.open(io.BytesIO(image_bytes))
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] PIL Image loaded - Size: {image.size}, Mode: {image.mode}")
            
            # Convert to RGB if necessary
            if image.mode != 'RGB':
                logger.debug(f"🔍 [WALL THICKNESS DEBUG] Converting from {image.mode} to RGB...")
                image = image.convert('RGB')
            
            # Convert to OpenCV format (BGR)
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] Converting to OpenCV format (BGR)...")
            cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] OpenCV image ready - Shape: {cv_image.shape}")
            
            return cv_image
        except Exception as e:
            logger.error(f"🔍 [WALL THICKNESS DEBUG] Failed to load image: {str(e)}")
            raise Exception(f"Failed to load image: {str(e)}")
    
    def _generate_depth_map(self, image: np.ndarray) -> np.ndarray:
        """Generate depth map using Depth Anything V2"""
        try:
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] Calling model.infer_image() with image shape: {image.shape}")
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] Model device: {self.device}")
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] Model loaded: {self.model is not None}")
            
            # Use the model's infer_image method as shown in the repository
            depth_map = self.model.infer_image(image)
            
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] Depth map inference completed - Output shape: {depth_map.shape}")
            logger.debug(f"🔍 [WALL THICKNESS DEBUG] Depth map stats - Min: {depth_map.min():.6f}, Max: {depth_map.max():.6f}, Mean: {depth_map.mean():.6f}")
            
            return depth_map
        except Exception as e:
            logger.error(f"🔍 [WALL THICKNESS DEBUG] Depth map generation failed: {str(e)}")
            import traceback
            logger.error(f"🔍 [WALL THICKNESS DEBUG] Traceback: {traceback.format_exc()}")
            raise Exception(f"Depth map generation failed: {str(e)}")
    
    def _detect_frame_boundaries(self, image: np.ndarray, depth_map: np.ndarray) -> Dict:
        """Detect door/window frame boundaries using both visual and depth information"""
        try:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            
            # Method 1: Edge detection on original image
            edges = cv2.Canny(gray, 50, 150)
            
            # Method 2: Depth gradient analysis
            depth_normalized = cv2.normalize(depth_map, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
            depth_edges = cv2.Canny(depth_normalized, 30, 100)
            
            # Combine edge information
            combined_edges = cv2.bitwise_or(edges, depth_edges)
            
            # Detect frame lines using HoughLinesP
            lines = cv2.HoughLinesP(
                combined_edges, 
                rho=1, 
                theta=np.pi/180, 
                threshold=100,
                minLineLength=50, 
                maxLineGap=10
            )
            
            if lines is None:
                raise Exception("Could not detect frame boundaries")
            
            # Classify lines as inner/outer frame edges
            frame_boundaries = self._classify_frame_lines(lines, depth_map)
            
            return {
                "inner_frame": frame_boundaries["inner"],
                "outer_frame": frame_boundaries["outer"],
                "frame_orientation": frame_boundaries["orientation"],
                "frame_region": frame_boundaries["region"],
                "total_lines": len(lines)
            }
        except Exception as e:
            raise Exception(f"Frame boundary detection failed: {str(e)}")
    
    def _classify_frame_lines(self, lines: np.ndarray, depth_map: np.ndarray) -> Dict:
        """Classify detected lines as inner/outer frame boundaries"""
        try:
            vertical_lines = []
            horizontal_lines = []
            
            for line in lines:
                x1, y1, x2, y2 = line[0]
                
                # Calculate line angle
                dx = abs(x2 - x1)
                dy = abs(y2 - y1)
                
                if dx > dy:  # More horizontal
                    horizontal_lines.append(line[0])
                else:  # More vertical
                    vertical_lines.append(line[0])
            
            # Determine frame orientation
            if len(vertical_lines) >= len(horizontal_lines):
                orientation = "vertical_frame"
                primary_lines = vertical_lines
            else:
                orientation = "horizontal_frame"
                primary_lines = horizontal_lines
            
            # Sort lines by position to identify inner/outer boundaries
            if orientation == "vertical_frame":
                # Sort by x-coordinate
                primary_lines.sort(key=lambda line: (line[0] + line[2]) / 2)
            else:
                # Sort by y-coordinate
                primary_lines.sort(key=lambda line: (line[1] + line[3]) / 2)
            
            # Identify inner and outer frame lines
            if len(primary_lines) >= 2:
                inner_frame = primary_lines[0]
                outer_frame = primary_lines[-1]
            else:
                # Fallback: use depth analysis to estimate frame boundaries
                inner_frame, outer_frame = self._estimate_frame_from_depth(depth_map)
            
            return {
                "inner": inner_frame,
                "outer": outer_frame,
                "orientation": orientation,
                "region": self._get_frame_region(inner_frame, outer_frame)
            }
        except Exception as e:
            raise Exception(f"Frame line classification failed: {str(e)}")
    
    def _estimate_frame_from_depth(self, depth_map: np.ndarray) -> Tuple[List[int], List[int]]:
        """Estimate frame boundaries from depth map when line detection fails"""
        height, width = depth_map.shape
        
        # Create simple vertical frame boundaries based on depth transitions
        center_x = width // 2
        
        # Find depth transitions along the center line
        center_column = depth_map[:, center_x]
        
        # Simple approach: assume frame is in the center third of the image
        inner_x = center_x - width // 6
        outer_x = center_x + width // 6
        
        inner_frame = [inner_x, 0, inner_x, height - 1]
        outer_frame = [outer_x, 0, outer_x, height - 1]
        
        return inner_frame, outer_frame
    
    def _get_frame_region(self, inner_frame: List[int], outer_frame: List[int]) -> Dict:
        """Get frame region information"""
        x1_inner, y1_inner, x2_inner, y2_inner = inner_frame
        x1_outer, y1_outer, x2_outer, y2_outer = outer_frame
        
        return {
            "inner_bounds": inner_frame,
            "outer_bounds": outer_frame,
            "width_pixels": abs(x1_outer - x1_inner),
            "height_pixels": abs(y1_outer - y1_inner)
        }
    
    def _extract_wall_thickness_profile(self, depth_map: np.ndarray, frame_analysis: Dict) -> Dict:
        """Extract depth profile across the wall thickness"""
        try:
            inner_frame = frame_analysis["inner_frame"]
            outer_frame = frame_analysis["outer_frame"]
            orientation = frame_analysis["frame_orientation"]
            
            # Create sampling lines perpendicular to frame
            if orientation == "vertical_frame":
                sampling_lines = self._create_horizontal_sampling_lines(inner_frame, outer_frame, depth_map.shape)
            else:
                sampling_lines = self._create_vertical_sampling_lines(inner_frame, outer_frame, depth_map.shape)
            
            thickness_measurements = []
            
            for line in sampling_lines:
                # Extract depth values along this line
                depth_profile = self._sample_depth_along_line(depth_map, line)
                
                # Find transitions (edges of wall)
                transitions = self._find_depth_transitions(depth_profile)
                
                if len(transitions) >= 2:
                    # Calculate thickness from first major transition to last
                    inner_depth = depth_profile[transitions[0]]
                    outer_depth = depth_profile[transitions[-1]]
                    
                    # Thickness in pixels
                    thickness_pixels = abs(transitions[-1] - transitions[0])
                    depth_difference = abs(outer_depth - inner_depth)
                    
                    thickness_measurements.append({
                        "line_position": line,
                        "thickness_pixels": thickness_pixels,
                        "depth_difference": depth_difference,
                        "inner_depth": inner_depth,
                        "outer_depth": outer_depth,
                        "transitions": transitions
                    })
            
            if not thickness_measurements:
                raise Exception("No valid thickness measurements found")
            
            return {
                "measurements": thickness_measurements,
                "average_thickness_pixels": np.mean([m["thickness_pixels"] for m in thickness_measurements]),
                "average_depth_difference": np.mean([m["depth_difference"] for m in thickness_measurements]),
                "measurement_consistency": np.std([m["thickness_pixels"] for m in thickness_measurements])
            }
        except Exception as e:
            raise Exception(f"Thickness profile extraction failed: {str(e)}")
    
    def _create_horizontal_sampling_lines(self, inner_frame: List[int], outer_frame: List[int], shape: Tuple) -> List[Dict]:
        """Create horizontal sampling lines for vertical frames"""
        height, width = shape
        lines = []
        
        x1_inner, y1_inner, x2_inner, y2_inner = inner_frame
        x1_outer, y1_outer, x2_outer, y2_outer = outer_frame
        
        logger.debug(f"🔍 [SAMPLING DEBUG] Creating horizontal lines - Inner frame: {inner_frame}, Outer frame: {outer_frame}")
        
        # Create multiple sampling lines across the frame height
        num_samples = min(10, height // 20)  # 10 samples or one every 20 pixels
        
        for i in range(num_samples):
            y = int(y1_inner + (y2_inner - y1_inner) * i / (num_samples - 1)) if num_samples > 1 else height // 2
            
            # Extend sampling lines beyond detected frame boundaries to capture full wall thickness
            frame_center_x = (x1_inner + x1_outer) // 2
            frame_width = abs(x1_outer - x1_inner)
            
            # Extend sampling by 50% on each side to ensure we capture the full wall
            extension = max(20, int(frame_width * 0.5))
            
            x_start = max(0, min(x1_inner, x1_outer) - extension)
            x_end = min(width - 1, max(x1_inner, x1_outer) + extension)
            
            logger.debug(f"🔍 [SAMPLING DEBUG] Line {i}: y={y}, x_start={x_start}, x_end={x_end} (extended by {extension})")
            
            lines.append({
                "start": (x_start, y),
                "end": (x_end, y),
                "direction": "horizontal",
                "frame_bounds": (min(x1_inner, x1_outer), max(x1_inner, x1_outer))
            })
        
        return lines
    
    def _create_vertical_sampling_lines(self, inner_frame: List[int], outer_frame: List[int], shape: Tuple) -> List[Dict]:
        """Create vertical sampling lines for horizontal frames"""
        height, width = shape
        lines = []
        
        x1_inner, y1_inner, x2_inner, y2_inner = inner_frame
        x1_outer, y1_outer, x2_outer, y2_outer = outer_frame
        
        logger.debug(f"🔍 [SAMPLING DEBUG] Creating vertical lines - Inner frame: {inner_frame}, Outer frame: {outer_frame}")
        
        # Create multiple sampling lines across the frame width
        num_samples = min(10, width // 20)
        
        for i in range(num_samples):
            x = int(x1_inner + (x2_inner - x1_inner) * i / (num_samples - 1)) if num_samples > 1 else width // 2
            
            # Extend sampling lines beyond detected frame boundaries to capture full wall thickness
            frame_center_y = (y1_inner + y1_outer) // 2
            frame_height = abs(y1_outer - y1_inner)
            
            # Extend sampling by 50% on each side to ensure we capture the full wall
            extension = max(20, int(frame_height * 0.5))
            
            y_start = max(0, min(y1_inner, y1_outer) - extension)
            y_end = min(height - 1, max(y1_inner, y1_outer) + extension)
            
            logger.debug(f"🔍 [SAMPLING DEBUG] Line {i}: x={x}, y_start={y_start}, y_end={y_end} (extended by {extension})")
            
            lines.append({
                "start": (x, y_start),
                "end": (x, y_end),
                "direction": "vertical",
                "frame_bounds": (min(y1_inner, y1_outer), max(y1_inner, y1_outer))
            })
        
        return lines
    
    def _sample_depth_along_line(self, depth_map: np.ndarray, line: Dict) -> np.ndarray:
        """Sample depth values along a line"""
        start_x, start_y = line["start"]
        end_x, end_y = line["end"]
        
        # Create line coordinates
        if line["direction"] == "horizontal":
            x_coords = np.linspace(start_x, end_x, abs(end_x - start_x) + 1, dtype=int)
            y_coords = np.full_like(x_coords, start_y)
        else:
            y_coords = np.linspace(start_y, end_y, abs(end_y - start_y) + 1, dtype=int)
            x_coords = np.full_like(y_coords, start_x)
        
        # Ensure coordinates are within bounds
        height, width = depth_map.shape
        x_coords = np.clip(x_coords, 0, width - 1)
        y_coords = np.clip(y_coords, 0, height - 1)
        
        # Sample depth values
        depth_profile = depth_map[y_coords, x_coords]
        
        return depth_profile
    
    def _find_depth_transitions(self, depth_profile: np.ndarray, threshold: float = 0.1) -> List[int]:
        """Find significant depth transitions that indicate wall edges"""
        if len(depth_profile) < 3:
            return []
        
        # Smooth the depth profile to reduce noise
        if SCIPY_AVAILABLE:
            smoothed_profile = gaussian_filter1d(depth_profile, sigma=1.0)
        else:
            # Fallback to simple moving average if scipy not available
            kernel_size = min(3, len(depth_profile))
            smoothed_profile = np.convolve(depth_profile, np.ones(kernel_size)/kernel_size, mode='same')
        
        # Calculate first and second derivatives
        first_derivative = np.gradient(smoothed_profile)
        second_derivative = np.gradient(first_derivative)
        
        # Find significant changes using multiple criteria
        transitions = []
        
        # Method 1: Find peaks/valleys in first derivative (edges)
        gradient_threshold = np.std(first_derivative) * 0.8  # More sensitive threshold
        
        for i in range(1, len(first_derivative) - 1):
            # Look for local extrema in the gradient
            if abs(first_derivative[i]) > gradient_threshold:
                # Check if it's a local maximum or minimum
                if ((first_derivative[i-1] < first_derivative[i] > first_derivative[i+1]) or 
                    (first_derivative[i-1] > first_derivative[i] < first_derivative[i+1])):
                    transitions.append(i)
        
        # Method 2: Find zero crossings in second derivative (inflection points)
        zero_crossings = []
        for i in range(1, len(second_derivative)):
            if (second_derivative[i-1] * second_derivative[i] < 0):  # Sign change
                zero_crossings.append(i)
        
        # Combine transitions from both methods
        all_transitions = list(set(transitions + zero_crossings))
        all_transitions.sort()
        
        # Filter transitions that are too close together
        if len(all_transitions) > 2:
            filtered_transitions = [all_transitions[0]]
            min_distance = max(3, len(depth_profile) * 0.1)  # Minimum distance between transitions
            
            for transition in all_transitions[1:]:
                if abs(transition - filtered_transitions[-1]) > min_distance:
                    filtered_transitions.append(transition)
            
            all_transitions = filtered_transitions
        
        # Ensure we have at least 2 transitions for wall thickness measurement
        if len(all_transitions) < 2 and len(depth_profile) > 10:
            # Fallback: find the most significant depth changes
            depth_changes = np.abs(np.diff(smoothed_profile))
            
            # Find the two largest changes
            largest_changes = np.argsort(depth_changes)[-2:]
            largest_changes.sort()
            
            # Add buffer to ensure we're measuring the full thickness
            start_idx = max(0, largest_changes[0] - 2)
            end_idx = min(len(depth_profile) - 1, largest_changes[-1] + 2)
            
            all_transitions = [start_idx, end_idx]
        
        return all_transitions
    
    def _calculate_real_world_thickness(self, thickness_profile: Dict, frame_analysis: Dict) -> Dict:
        """Convert pixel measurements to real-world centimeters using depth-based calibration"""
        avg_thickness_pixels = thickness_profile["average_thickness_pixels"]
        avg_depth_difference = thickness_profile["average_depth_difference"]
        consistency = thickness_profile["measurement_consistency"]
        
        logger.info(f"🔍 [CALIBRATION DEBUG] Starting calibration - Avg pixels: {avg_thickness_pixels:.2f}, Avg depth diff: {avg_depth_difference:.6f}")
        
        # NEW APPROACH: Use depth information for calibration instead of assumed frame widths
        calibration_method = "depth_based_calibration"
        
        try:
            # Method 1: Depth-ratio based calibration
            # The idea is that we can estimate real-world thickness by analyzing the depth gradient
            # across the wall thickness region
            
            # Get the depth measurements from the thickness profile
            depth_measurements = [m["depth_difference"] for m in thickness_profile["measurements"]]
            pixel_measurements = [m["thickness_pixels"] for m in thickness_profile["measurements"]]
            
            logger.info(f"🔍 [CALIBRATION DEBUG] Individual measurements - Depth: {depth_measurements}, Pixels: {pixel_measurements}")
            
            if len(depth_measurements) > 0 and len(pixel_measurements) > 0:
                # Calculate the depth-to-pixel ratio
                valid_ratios = [d/p if p > 0 else 0 for d, p in zip(depth_measurements, pixel_measurements) if p > 0]
                avg_depth_per_pixel = np.mean(valid_ratios) if valid_ratios else 0
                
                logger.info(f"🔍 [CALIBRATION DEBUG] Valid depth/pixel ratios: {valid_ratios}, Avg: {avg_depth_per_pixel:.6f}")
                
                # Use depth information to estimate scale
                # Depth Anything V2 outputs relative depth, so we need to calibrate it
                # Based on typical indoor scenes, we can estimate that:
                # - Wall thickness typically ranges from 10-30cm
                # - The depth difference across a wall should be proportional to its thickness
                
                # Estimate pixels per cm using depth analysis
                if avg_depth_per_pixel > 0:
                    # Use the depth gradient to estimate real-world scale
                    # This is based on the assumption that deeper depth changes indicate thicker walls
                    depth_scale_factor = self._estimate_depth_scale_factor(avg_depth_difference, avg_thickness_pixels)
                    pixels_per_cm = avg_thickness_pixels / depth_scale_factor
                    
                    logger.info(f"🔍 [CALIBRATION DEBUG] Depth-based calibration - Scale factor: {depth_scale_factor:.2f}cm, Pixels/cm: {pixels_per_cm:.2f}")
                else:
                    # Fallback to frame-based estimation
                    pixels_per_cm = self._fallback_frame_calibration(frame_analysis)
                    calibration_method = "frame_fallback"
                    logger.info(f"🔍 [CALIBRATION DEBUG] Using frame fallback - Pixels/cm: {pixels_per_cm:.2f}")
            else:
                # Fallback to frame-based estimation
                pixels_per_cm = self._fallback_frame_calibration(frame_analysis)
                calibration_method = "frame_fallback"
                logger.info(f"🔍 [CALIBRATION DEBUG] No valid measurements, using frame fallback - Pixels/cm: {pixels_per_cm:.2f}")
            
            # Ensure reasonable pixels_per_cm value
            if pixels_per_cm <= 0 or pixels_per_cm > 100:  # Sanity check
                logger.warning(f"🔍 [CALIBRATION DEBUG] Unrealistic pixels_per_cm: {pixels_per_cm}, using frame fallback")
                pixels_per_cm = self._fallback_frame_calibration(frame_analysis)
                calibration_method = "frame_fallback"
            
            # Calculate wall thickness
            wall_thickness_cm = avg_thickness_pixels / pixels_per_cm
            
            logger.info(f"🔍 [CALIBRATION DEBUG] Raw calculation: {avg_thickness_pixels:.2f} pixels / {pixels_per_cm:.2f} px/cm = {wall_thickness_cm:.2f} cm")
            
            # Apply reasonable bounds based on typical wall thickness ranges
            wall_thickness_cm = max(8.0, min(35.0, wall_thickness_cm))  # 8-35cm range
            
            logger.info(f"🔍 [CALIBRATION DEBUG] Final thickness after bounds: {wall_thickness_cm:.2f} cm")
            
        except Exception as e:
            logger.warning(f"Depth-based calibration failed: {e}, falling back to frame calibration")
            # Fallback to original frame-based method
            pixels_per_cm = self._fallback_frame_calibration(frame_analysis)
            wall_thickness_cm = avg_thickness_pixels / pixels_per_cm
            wall_thickness_cm = max(8.0, min(35.0, wall_thickness_cm))
            calibration_method = "frame_fallback"
        
        # Quality assessment
        confidence = self._calculate_measurement_confidence(
            consistency, 
            len(thickness_profile["measurements"]),
            calibration_method
        )
        
        logger.info(f"🔍 [CALIBRATION DEBUG] Final result: {wall_thickness_cm:.1f} cm, confidence: {confidence:.3f}, method: {calibration_method}")
        
        return {
            "thickness_cm": round(wall_thickness_cm, 1),
            "confidence": confidence,
            "calibration_method": calibration_method,
            "pixels_per_cm": pixels_per_cm,
            "points": len(thickness_profile["measurements"]),
            "quality": {
                "consistency": consistency,
                "measurement_points": len(thickness_profile["measurements"]),
                "frame_detection_quality": frame_analysis.get("total_lines", 0),
                "avg_depth_difference": avg_depth_difference,
                "depth_measurements": depth_measurements
            }
        }
    
    def _estimate_depth_scale_factor(self, avg_depth_difference: float, avg_thickness_pixels: float) -> float:
        """Estimate real-world thickness in cm based on depth analysis"""
        try:
            # Depth Anything V2 produces relative depth values
            # We need to map these to real-world measurements
            
            # Empirical approach: analyze the depth gradient strength
            # Stronger depth gradients typically indicate larger real-world depth changes
            
            # Base assumption: typical interior wall thickness is 15-25cm
            base_wall_thickness_cm = 20.0
            
            # Scale based on depth difference magnitude
            # This is a heuristic that may need adjustment based on testing
            if avg_depth_difference > 0.5:  # Strong depth gradient
                estimated_thickness = base_wall_thickness_cm * 1.2  # Thicker wall
            elif avg_depth_difference > 0.2:  # Medium depth gradient
                estimated_thickness = base_wall_thickness_cm  # Standard thickness
            else:  # Weak depth gradient
                estimated_thickness = base_wall_thickness_cm * 0.8  # Thinner wall
            
            # Additional scaling based on pixel thickness
            # More pixels generally indicate thicker walls in the image
            if avg_thickness_pixels > 50:
                estimated_thickness *= 1.1
            elif avg_thickness_pixels < 20:
                estimated_thickness *= 0.9
            
            return max(10.0, min(30.0, estimated_thickness))  # Clamp to reasonable range
            
        except Exception as e:
            logger.warning(f"Failed to estimate depth scale factor: {e}")
            return 20.0  # Default to 20cm
    
    def _fallback_frame_calibration(self, frame_analysis: Dict) -> float:
        """Fallback calibration method using frame reference"""
        try:
            # Use standard door/window frame dimensions for calibration
            if frame_analysis["frame_orientation"] == "vertical_frame":
                # Standard door frame width is typically 10-15cm
                reference_width_cm = 12.5
            else:
                # Window frames are typically 5-10cm
                reference_width_cm = 7.5
            
            # Estimate frame width in pixels
            frame_width_pixels = self._estimate_frame_width_pixels(frame_analysis)
            
            # Calculate pixels per cm
            if frame_width_pixels > 0:
                pixels_per_cm = frame_width_pixels / reference_width_cm
            else:
                pixels_per_cm = 8  # Conservative fallback estimate
            
            return max(5.0, min(50.0, pixels_per_cm))  # Sanity check bounds
            
        except Exception as e:
            logger.warning(f"Frame calibration failed: {e}")
            return 8.0  # Conservative fallback
    
    def _estimate_frame_width_pixels(self, frame_analysis: Dict) -> int:
        """Estimate frame width in pixels"""
        try:
            frame_region = frame_analysis["frame_region"]
            if frame_analysis["frame_orientation"] == "vertical_frame":
                return frame_region.get("width_pixels", 50)  # Default estimate
            else:
                return frame_region.get("height_pixels", 50)
        except:
            return 50  # Fallback estimate
    
    def _calculate_measurement_confidence(self, consistency: float, num_points: int, method: str) -> float:
        """Calculate confidence score for the measurement"""
        # Base confidence from consistency (lower is better)
        consistency_score = max(0, 1 - (consistency / 10))  # Normalize consistency
        
        # Points score (more points = higher confidence)
        points_score = min(1.0, num_points / 10)
        
        # Method score
        method_score = 0.8 if method == "frame_reference" else 0.6
        
        # Combined confidence
        confidence = (consistency_score * 0.4 + points_score * 0.3 + method_score * 0.3)
        
        return max(0.1, min(1.0, confidence))
    
    def _create_thickness_visualization(self, image: np.ndarray, depth_map: np.ndarray, 
                                      frame_analysis: Dict, measurements: Dict) -> str:
        """Create visualization showing depth map and measurements"""
        try:
            # Create depth visualization
            depth_normalized = cv2.normalize(depth_map, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
            depth_colored = cv2.applyColorMap(depth_normalized, cv2.COLORMAP_JET)
            
            # Resize to match original image
            height, width = image.shape[:2]
            depth_colored = cv2.resize(depth_colored, (width, height))
            
            # Create side-by-side visualization
            combined = np.hstack([image, depth_colored])
            
            # Add measurement annotations
            font = cv2.FONT_HERSHEY_SIMPLEX
            font_scale = 0.7
            color = (255, 255, 255)
            thickness = 2
            
            # Add text with measurement
            text = f"Wall Thickness: {measurements['thickness_cm']} cm"
            cv2.putText(combined, text, (10, 30), font, font_scale, color, thickness)
            
            text = f"Confidence: {int(measurements['confidence'] * 100)}%"
            cv2.putText(combined, text, (10, 60), font, font_scale, color, thickness)
            
            text = f"Points: {measurements['points']}"
            cv2.putText(combined, text, (10, 90), font, font_scale, color, thickness)
            
            # Convert to base64
            _, buffer = cv2.imencode('.jpg', combined, [cv2.IMWRITE_JPEG_QUALITY, 85])
            img_base64 = base64.b64encode(buffer).decode('utf-8')
            
            return f"data:image/jpeg;base64,{img_base64}"
        except Exception as e:
            logger.warning(f"Failed to create visualization: {e}")
            return None 