import io
import json
import os
from typing import List, Dict, Any
from google.cloud import vision
from google.oauth2 import service_account
import cv2
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter
import base64

# Import the YOLO vision service
try:
    from .yolo_vision_service import yolo_vision_service
    YOLO_AVAILABLE = True
except ImportError:
    YOLO_AVAILABLE = False
    print("⚠️ YOLO vision service not available - install ultralytics, scikit-learn, matplotlib")

# Import the enhanced floor plan service
try:
    from backend.services.enhanced_floor_plan_service import enhanced_floor_plan_service, initialize_enhanced_service
    ENHANCED_FLOOR_PLAN_AVAILABLE = True
except ImportError:
    ENHANCED_FLOOR_PLAN_AVAILABLE = False
    print("⚠️ Enhanced floor plan service not available")

class VisionService:
    def __init__(self):
        # Initialize the Vision API client
        self.client = None
        
        # Check if credentials are available and set use_dummy accordingly
        credentials_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "google-credentials.json")
        env_credentials = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
        
        # Use real API if credentials are available, otherwise use dummy implementation
        self.use_dummy = not (os.path.exists(credentials_path) or env_credentials)
        
        if not self.use_dummy:
            print("Google Cloud Vision credentials found. Using real Vision API.")
            # Set the credentials path for the Google Cloud client
            if os.path.exists(credentials_path):
                os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = credentials_path
                print(f"Set GOOGLE_APPLICATION_CREDENTIALS to: {credentials_path}")
        else:
            print("No Google Cloud credentials found. Using dummy implementation.")
    
    def set_floor_plan_model(self, model_path: str):
        """Set the path to the specialized floor plan detection model"""
        if ENHANCED_FLOOR_PLAN_AVAILABLE:
            initialize_enhanced_service(model_path)
            print(f"✅ Enhanced floor plan model set: {model_path}")
        else:
            print("⚠️ Enhanced floor plan service not available")
    
    def _preprocess_image(self, image_bytes: bytes) -> bytes:
        """
        Preprocess the image to improve Vision API accuracy
        """
        try:
            # Convert bytes to PIL Image
            image = Image.open(io.BytesIO(image_bytes))
            
            # Convert to RGB if necessary
            if image.mode != 'RGB':
                image = image.convert('RGB')
            
            # Step 1: Resize if image is too large (Vision API works better with reasonable sizes)
            max_dimension = 2048
            if max(image.size) > max_dimension:
                ratio = max_dimension / max(image.size)
                new_size = (int(image.size[0] * ratio), int(image.size[1] * ratio))
                image = image.resize(new_size, Image.Resampling.LANCZOS)
                print(f"Resized image to {new_size} for better processing")
            
            # Step 2: Enhance contrast and brightness
            enhancer = ImageEnhance.Contrast(image)
            image = enhancer.enhance(1.2)  # Increase contrast by 20%
            
            enhancer = ImageEnhance.Brightness(image)
            image = enhancer.enhance(1.1)  # Increase brightness by 10%
            
            # Step 3: Sharpen the image to make text and lines clearer
            enhancer = ImageEnhance.Sharpness(image)
            image = enhancer.enhance(1.3)  # Increase sharpness by 30%
            
            # Step 4: Apply noise reduction using PIL filters
            image = image.filter(ImageFilter.MedianFilter(size=3))
            
            # Step 5: Convert to OpenCV format for advanced processing
            cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
            
            # Step 6: Apply adaptive histogram equalization to improve contrast
            lab = cv2.cvtColor(cv_image, cv2.COLOR_BGR2LAB)
            lab[:,:,0] = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8)).apply(lab[:,:,0])
            cv_image = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)
            
            # Step 7: Apply bilateral filter to reduce noise while keeping edges sharp
            cv_image = cv2.bilateralFilter(cv_image, 9, 75, 75)
            
            # Step 8: Enhance edges for better line detection
            gray = cv2.cvtColor(cv_image, cv2.COLOR_BGR2GRAY)
            edges = cv2.Canny(gray, 50, 150, apertureSize=3)
            
            # Dilate edges slightly to make them more prominent
            kernel = np.ones((2,2), np.uint8)
            edges = cv2.dilate(edges, kernel, iterations=1)
            
            # Combine original image with enhanced edges
            edges_colored = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)
            cv_image = cv2.addWeighted(cv_image, 0.8, edges_colored, 0.2, 0)
            
            # Convert back to PIL and then to bytes
            final_image = Image.fromarray(cv2.cvtColor(cv_image, cv2.COLOR_BGR2RGB))
            
            # Save as high-quality JPEG
            output_buffer = io.BytesIO()
            final_image.save(output_buffer, format='JPEG', quality=95, optimize=True)
            
            print("Image preprocessing completed successfully")
            return output_buffer.getvalue()
            
        except Exception as e:
            print(f"Image preprocessing failed: {e}, using original image")
            return image_bytes
    
    def _create_high_contrast_version(self, image_bytes: bytes) -> bytes:
        """
        Create a high-contrast black and white version for better text detection
        """
        try:
            image = Image.open(io.BytesIO(image_bytes))
            
            # Convert to grayscale
            gray_image = image.convert('L')
            
            # Apply threshold to create high contrast
            threshold = 128
            bw_image = gray_image.point(lambda x: 255 if x > threshold else 0, mode='1')
            
            # Convert back to RGB for Vision API
            bw_image = bw_image.convert('RGB')
            
            # Save as bytes
            output_buffer = io.BytesIO()
            bw_image.save(output_buffer, format='JPEG', quality=95)
            
            return output_buffer.getvalue()
            
        except Exception as e:
            print(f"High contrast processing failed: {e}")
            return image_bytes
    
    def _merge_duplicate_objects(self, objects: List) -> List:
        """
        Merge duplicate objects detected across multiple passes
        """
        if not objects:
            return []
        
        merged = []
        processed = set()
        
        for i, obj in enumerate(objects):
            if i in processed:
                continue
                
            # Find similar objects (same name, similar position)
            similar_objects = [obj]
            for j, other_obj in enumerate(objects[i+1:], i+1):
                if j in processed:
                    continue
                    
                if (obj.name.lower() == other_obj.name.lower() and 
                    self._objects_are_similar(obj, other_obj)):
                    similar_objects.append(other_obj)
                    processed.add(j)
            
            # Merge similar objects by taking the one with highest confidence
            best_obj = max(similar_objects, key=lambda x: x.score)
            merged.append(best_obj)
            processed.add(i)
        
        return merged
    
    def _merge_duplicate_texts(self, texts: List) -> List:
        """
        Merge duplicate texts detected across multiple passes
        """
        if not texts:
            return []
        
        merged = []
        processed = set()
        
        for i, text in enumerate(texts):
            if i in processed:
                continue
                
            # Find similar texts (same content, similar position)
            similar_texts = [text]
            for j, other_text in enumerate(texts[i+1:], i+1):
                if j in processed:
                    continue
                    
                if (text.description.lower().strip() == other_text.description.lower().strip() and 
                    self._texts_are_similar(text, other_text)):
                    similar_texts.append(other_text)
                    processed.add(j)
            
            # Take the text with the most complete bounding box info
            best_text = max(similar_texts, key=lambda x: len(x.bounding_poly.vertices) if x.bounding_poly else 0)
            merged.append(best_text)
            processed.add(i)
        
        return merged
    
    def _select_best_document_text(self, doc_texts: List) -> Any:
        """
        Select the best document text analysis from multiple passes
        """
        if not doc_texts:
            return None
        
        # Return the one with the most detected text
        return max(doc_texts, key=lambda x: len(x.text) if x and hasattr(x, 'text') else 0)
    
    def _objects_are_similar(self, obj1, obj2, threshold=0.1) -> bool:
        """
        Check if two objects are similar based on position and size
        """
        try:
            # Get bounding boxes
            v1 = obj1.bounding_poly.normalized_vertices
            v2 = obj2.bounding_poly.normalized_vertices
            
            if not v1 or not v2:
                return False
            
            # Calculate centers
            center1_x = (v1[0].x + v1[2].x) / 2
            center1_y = (v1[0].y + v1[2].y) / 2
            center2_x = (v2[0].x + v2[2].x) / 2
            center2_y = (v2[0].y + v2[2].y) / 2
            
            # Calculate distance between centers
            distance = ((center1_x - center2_x) ** 2 + (center1_y - center2_y) ** 2) ** 0.5
            
            return distance < threshold
        except:
            return False
    
    def _texts_are_similar(self, text1, text2, threshold=0.05) -> bool:
        """
        Check if two texts are similar based on position
        """
        try:
            # Get bounding boxes
            v1 = text1.bounding_poly.vertices
            v2 = text2.bounding_poly.vertices
            
            if not v1 or not v2:
                return False
            
            # Calculate centers (using pixel coordinates)
            center1_x = sum(v.x for v in v1) / len(v1)
            center1_y = sum(v.y for v in v1) / len(v1)
            center2_x = sum(v.x for v in v2) / len(v2)
            center2_y = sum(v.y for v in v2) / len(v2)
            
            # Calculate distance (normalize by image size assumption)
            distance = ((center1_x - center2_x) ** 2 + (center1_y - center2_y) ** 2) ** 0.5
            
            return distance < 50  # 50 pixels threshold
        except:
            return False
 
    async def analyze_floor_plan(self, image_bytes: bytes, method: str = "auto", confidence: float = 0.4) -> Dict[str, Any]:
        """
        Analyze a floor plan image using the specified method
        
        Args:
            image_bytes: Image data as bytes
            method: Analysis method ('auto', 'google_vision', 'yolo', 'enhanced')
            confidence: Detection confidence threshold for enhanced method
        """
        print(f"🏗️ Starting floor plan analysis with method: {method}")
        
        # Method selection logic
        if method == "auto":
            # Auto-select the best available method
            if ENHANCED_FLOOR_PLAN_AVAILABLE and enhanced_floor_plan_service and enhanced_floor_plan_service.floor_plan_detector:
                method = "enhanced"
                print("✅ Auto-selected enhanced floor plan method")
            elif YOLO_AVAILABLE:
                method = "yolo"
                print("✅ Auto-selected YOLO method")
            elif not self.use_dummy:
                method = "google_vision"
                print("✅ Auto-selected Google Vision method")
            else:
                method = "dummy"
                print("⚠️ Auto-selected dummy method (no real services available)")
        
        # Process with selected method
        if method == "enhanced":
            print(f"🔍 Enhanced method selected. Checking service state...")
            print(f"   ENHANCED_FLOOR_PLAN_AVAILABLE: {ENHANCED_FLOOR_PLAN_AVAILABLE}")
            print(f"   enhanced_floor_plan_service: {enhanced_floor_plan_service}")
            
            if not ENHANCED_FLOOR_PLAN_AVAILABLE:
                print("❌ Enhanced floor plan service not available")
                return {
                    'detected_rooms': [],
                    'image_dimensions': {'width': 0, 'height': 0},
                    'processing_method': 'enhanced_unavailable',
                    'error': 'Enhanced floor plan service not available'
                }
            
            if not enhanced_floor_plan_service:
                print("❌ Enhanced floor plan service not initialized")
                return {
                    'detected_rooms': [],
                    'image_dimensions': {'width': 0, 'height': 0},
                    'processing_method': 'enhanced_not_initialized',
                    'error': 'Enhanced floor plan service not initialized. Please set a model first.'
                }
            
            if not enhanced_floor_plan_service.floor_plan_detector:
                print("❌ Enhanced floor plan detector not loaded")
                return {
                    'detected_rooms': [],
                    'image_dimensions': {'width': 0, 'height': 0},
                    'processing_method': 'enhanced_no_model',
                    'error': 'Enhanced floor plan model not loaded. Please set a model first.'
                }
            
            print(f"✅ Enhanced service ready. Proceeding with analysis...")
            print(f"🎯 Using enhanced floor plan detection (confidence: {confidence})")
            return await enhanced_floor_plan_service.analyze_floor_plan(image_bytes, confidence)
            
        elif method == "yolo":
            if not YOLO_AVAILABLE:
                return {
                    'detected_rooms': [],
                    'image_dimensions': {'width': 0, 'height': 0},
                    'processing_method': 'yolo_unavailable',
                    'error': 'YOLO service not available'
                }
            
            print("🎯 Using YOLO + Computer Vision hybrid method")
            return await yolo_vision_service.analyze_floor_plan(image_bytes)
            
        elif method == "google_vision":
            if self.use_dummy:
                return {
                    'detected_rooms': [],
                    'image_dimensions': {'width': 0, 'height': 0},
                    'processing_method': 'google_vision_unavailable',
                    'error': 'Google Vision API not available (no credentials)'
                }
            
            print("🎯 Using Google Vision API method")
            return await self._vision_floor_plan_analysis(image_bytes)
            
        else:  # dummy method
            print("🎯 Using dummy method")
            return self._dummy_floor_plan_analysis(image_bytes)
    
    def _dummy_floor_plan_analysis(self, image_bytes: bytes) -> Dict[str, Any]:
        """
        Dummy implementation that simulates floor plan analysis
        """
        # Convert bytes to image for basic analysis
        image = Image.open(io.BytesIO(image_bytes))
        width, height = image.size
        
        # Simulate detecting 3-5 rooms based on image size
        num_rooms = min(5, max(2, width * height // 50000))
        
        rooms = []
        colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FECA57"]
        room_types = ["Living Room", "Kitchen", "Master Bedroom", "Bedroom", "Bathroom", "Dining Room"]
        
        for i in range(num_rooms):
            # Generate random room boundaries
            room_width = width // 3
            room_height = height // 3
            x = (i % 2) * room_width + np.random.randint(0, room_width // 2)
            y = (i // 2) * room_height + np.random.randint(0, room_height // 2)
            
            # Random number of doors and windows per room
            num_doors = np.random.randint(1, 3)
            num_windows = np.random.randint(0, 3)
            
            doors = []
            for d in range(num_doors):
                door_x = x + np.random.randint(0, room_width)
                door_y = y + np.random.randint(0, room_height)
                doors.append({
                    "position": {"x": door_x, "y": door_y},
                    "width": 30,
                    "height": 5,
                    "confidence": 0.8 + np.random.random() * 0.15
                })
                
            windows = []
            for w in range(num_windows):
                window_x = x + np.random.randint(0, room_width)
                window_y = y + np.random.randint(0, room_height)
                windows.append({
                    "position": {"x": window_x, "y": window_y},
                    "width": 40,
                    "height": 5,
                    "confidence": 0.75 + np.random.random() * 0.2
                })
                
            # Random wall measurements
            measurements = [
                {"type": "wall", "value": f"{np.random.randint(200, 500)} cm", "position": {"x": x, "y": y}},
                {"type": "wall", "value": f"{np.random.randint(200, 500)} cm", "position": {"x": x + room_width, "y": y}}
            ]
            
            # Assign a room type
            room_type = room_types[i % len(room_types)]
            
            # Generate detailed room description
            position_x = "left side" if x < width/3 else "right side" if x > 2*width/3 else "central area"
            position_y = "upper" if y < height/3 else "lower" if y > 2*height/3 else "middle"
            
            room_description = f"Located in the {position_y} {position_x} of the floor plan. "
            
            if "bedroom" in room_type.lower():
                room_description += "Typically a private space with sleeping accommodations. "
                room_description += "Check for emergency exits and ensure windows can be used for evacuation."
            elif "kitchen" in room_type.lower():
                room_description += "Contains cooking facilities and potential fire hazards. "
                room_description += "Evaluate fire extinguisher access and gas line safety."
            elif "bathroom" in room_type.lower():
                room_description += "Contains plumbing fixtures and water sources. "
                room_description += "Check for water damage risks and slip hazards."
            elif "living" in room_type.lower():
                room_description += "Main gathering area with typically larger open space. "
                room_description += "Evaluate furniture placement for clear evacuation paths."
            elif "dining" in room_type.lower():
                room_description += "Designated eating area, often connected to kitchen. "
                room_description += "Check proximity to exits and kitchen safety features."
            
            # Generate estimated dimensions
            estimated_dimensions = {
                "width_cm": np.random.randint(300, 500),
                "length_cm": np.random.randint(300, 500),
                "area_sqm": round(np.random.randint(10, 25) + np.random.random(), 2),
                "estimated_ceiling_height_cm": np.random.randint(240, 300)
            }
            
            rooms.append({
                "room_id": i + 1,
                "default_name": room_type,
                "boundaries": {
                    "x": max(0, x),
                    "y": max(0, y),
                    "width": min(room_width, width - x),
                    "height": min(room_height, height - y)
                },
                "color": colors[i % len(colors)],
                "confidence": 0.85 + np.random.random() * 0.1,
                "doors": doors,
                "windows": windows,
                "measurements": measurements,
                "description": room_description,
                "estimated_dimensions": estimated_dimensions
            })
        
        return {
            "detected_rooms": rooms,
            "image_dimensions": {"width": width, "height": height},
            "processing_method": "dummy"
        }
    
    async def _vision_floor_plan_analysis(self, image_bytes: bytes) -> Dict[str, Any]:
        """
        Real Google Cloud Vision API implementation for floor plan analysis with multi-pass processing
        """
        try:
            # Initialize client if not already done
            if not self.client:
                # Get the credentials path
                credentials_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "google-credentials.json")
                
                if os.path.exists(credentials_path):
                    # Load credentials from file
                    credentials = service_account.Credentials.from_service_account_file(credentials_path)
                    self.client = vision.ImageAnnotatorClient(credentials=credentials)
                    print("Initialized Vision API client with service account credentials")
                else:
                    # Fallback to default credentials
                    self.client = vision.ImageAnnotatorClient()
                    print("Initialized Vision API client with default credentials")
            
            # Multi-pass analysis for better accuracy
            print("Starting multi-pass Vision API analysis...")
            
            # Pass 1: Analyze original image
            print("Pass 1: Analyzing original image...")
            original_image = vision.Image(content=image_bytes)
            
            # Pass 2: Analyze preprocessed image
            print("Pass 2: Analyzing preprocessed image...")
            preprocessed_bytes = self._preprocess_image(image_bytes)
            preprocessed_image = vision.Image(content=preprocessed_bytes)
            
            # Pass 3: Analyze high-contrast version for better text detection
            print("Pass 3: Analyzing high-contrast image for text...")
            contrast_bytes = self._create_high_contrast_version(image_bytes)
            contrast_image = vision.Image(content=contrast_bytes)
            
            # Perform analyses on all versions
            all_objects = []
            all_texts = []
            all_doc_texts = []
            
            # Analyze original image
            try:
                object_response = self.client.object_localization(image=original_image)
                all_objects.extend(object_response.localized_object_annotations)
                
                text_response = self.client.text_detection(image=original_image)
                all_texts.extend(text_response.text_annotations)
                
                doc_response = self.client.document_text_detection(image=original_image)
                if doc_response.full_text_annotation:
                    all_doc_texts.append(doc_response.full_text_annotation)
            except Exception as e:
                print(f"Original image analysis failed: {e}")
            
            # Analyze preprocessed image
            try:
                object_response = self.client.object_localization(image=preprocessed_image)
                all_objects.extend(object_response.localized_object_annotations)
                
                text_response = self.client.text_detection(image=preprocessed_image)
                all_texts.extend(text_response.text_annotations)
                
                doc_response = self.client.document_text_detection(image=preprocessed_image)
                if doc_response.full_text_annotation:
                    all_doc_texts.append(doc_response.full_text_annotation)
            except Exception as e:
                print(f"Preprocessed image analysis failed: {e}")
            
            # Analyze high-contrast image (primarily for text)
            try:
                text_response = self.client.text_detection(image=contrast_image)
                all_texts.extend(text_response.text_annotations)
                
                doc_response = self.client.document_text_detection(image=contrast_image)
                if doc_response.full_text_annotation:
                    all_doc_texts.append(doc_response.full_text_annotation)
            except Exception as e:
                print(f"High-contrast image analysis failed: {e}")
            
            # Merge and deduplicate results
            merged_objects = self._merge_duplicate_objects(all_objects)
            merged_texts = self._merge_duplicate_texts(all_texts)
            best_doc_text = self._select_best_document_text(all_doc_texts)
            
            print(f"Multi-pass analysis complete: {len(merged_objects)} objects, {len(merged_texts)} texts")
            
            # Process results to extract floor plan elements
            result = self._process_vision_floor_plan_results(image_bytes, merged_objects, merged_texts, best_doc_text)
            
            # Add metadata about API usage
            result["processing_method"] = "google_vision_multipass"
            result["objects_found"] = len(merged_objects)
            result["texts_found"] = len(merged_texts)
            result["analysis_passes"] = 3
            
            return result
            
        except Exception as e:
            # Fallback to dummy if Vision API fails
            print(f"Vision API error: {e}")
            return self._dummy_floor_plan_analysis(image_bytes)
    
    def _process_vision_floor_plan_results(self, image_bytes, objects, texts, doc_text) -> Dict[str, Any]:
        """
        Process Google Vision API results to identify rooms, doors, windows, and measurements
        """
        # Convert bytes to image for processing
        image = Image.open(io.BytesIO(image_bytes))
        width, height = image.size
        
        # Extract rooms using a combination of approaches
        rooms = self._extract_rooms(image_bytes, objects, texts, width, height)
        
        # Identify doors and windows
        doors_windows = self._identify_doors_and_windows(objects, width, height)
        
        # Extract measurements
        measurements = self._extract_measurements(texts, doc_text, width, height)
        
        # Associate doors, windows and measurements with rooms
        self._associate_elements_with_rooms(rooms, doors_windows["doors"], doors_windows["windows"], measurements)
        
        return {
            "detected_rooms": rooms,
            "image_dimensions": {"width": width, "height": height},
            "total_doors": len(doors_windows["doors"]),
            "total_windows": len(doors_windows["windows"]),
            "total_measurements": len(measurements)
        }
    
    def _extract_rooms(self, image_bytes, objects, texts, width, height) -> List[Dict]:
        """Extract rooms from the floor plan using multiple detection strategies"""
        rooms = []
        colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FECA57"]
        
        # Strategy 1: Look for text labels indicating rooms
        room_keywords = ["room", "bedroom", "kitchen", "bathroom", "living", "dining", "office", "hall", "closet", "pantry", "garage", "basement", "attic"]
        
        room_texts = []
        for text in texts[1:] if texts else []:  # Skip the first text which is usually the entire document
            text_lower = text.description.lower()
            if any(keyword in text_lower for keyword in room_keywords):
                room_texts.append(text)
        
        print(f"Found {len(room_texts)} room text labels")
        
        # Create rooms from detected text labels
        for i, text in enumerate(room_texts):
            vertices = text.bounding_poly.vertices if text.bounding_poly else []
            if not vertices:
                continue
                
            x = min(v.x for v in vertices)
            y = min(v.y for v in vertices)
            
            # Intelligently expand the area around the text to approximate the room
            # Base expansion on image size and text position
            base_expansion_x = width * 0.12  # 12% of image width
            base_expansion_y = height * 0.12  # 12% of image height
            
            # Adjust expansion based on room type
            room_type_lower = text.description.lower()
            if "living" in room_type_lower or "family" in room_type_lower:
                expansion_multiplier = 1.5  # Living rooms are typically larger
            elif "bathroom" in room_type_lower or "closet" in room_type_lower:
                expansion_multiplier = 0.7  # Bathrooms and closets are smaller
            elif "kitchen" in room_type_lower:
                expansion_multiplier = 1.2  # Kitchens are medium-large
            else:
                expansion_multiplier = 1.0
            
            expansion_x = base_expansion_x * expansion_multiplier
            expansion_y = base_expansion_y * expansion_multiplier
            
            # Generate detailed room description
            room_description = self._generate_room_description(text.description, x, y, width, height)
            
            # Generate more accurate estimated dimensions
            estimated_width_cm = int(expansion_x * 0.3)  # Improved real-world conversion
            estimated_length_cm = int(expansion_y * 0.3)
            estimated_area_sqm = round((estimated_width_cm * estimated_length_cm) / 10000, 2)
            
            estimated_dimensions = {
                "width_cm": estimated_width_cm,
                "length_cm": estimated_length_cm,
                "area_sqm": estimated_area_sqm,
                "estimated_ceiling_height_cm": 250  # Standard ceiling height
            }
            
            room = {
                "room_id": i + 1,
                "default_name": text.description.title(),
                "boundaries": {
                    "x": max(0, int(x - expansion_x/2)),
                    "y": max(0, int(y - expansion_y/2)),
                    "width": min(int(expansion_x), width - int(x - expansion_x/2)),
                    "height": min(int(expansion_y), height - int(y - expansion_y/2))
                },
                "color": colors[i % len(colors)],
                "confidence": 0.85,  # Higher confidence for text-based detection
                "doors": [],
                "windows": [],
                "measurements": [],
                "description": room_description,
                "estimated_dimensions": estimated_dimensions,
                "detection_method": "text_label"
            }
            rooms.append(room)
        
        # Strategy 2: Enhanced contour-based room detection
        if len(rooms) < 3:  # Only use if we don't have enough rooms from text
            print("Attempting enhanced contour-based room detection...")
            contour_rooms = self._enhanced_room_boundary_detection(image_bytes, width, height)
            
            # Merge contour rooms with text-based rooms, avoiding duplicates
            for contour_room in contour_rooms:
                # Check if this room overlaps significantly with existing text-based rooms
                is_duplicate = False
                for existing_room in rooms:
                    if self._rooms_overlap(contour_room["boundaries"], existing_room["boundaries"]):
                        is_duplicate = True
                        break
                
                if not is_duplicate:
                    contour_room["room_id"] = len(rooms) + 1
                    contour_room["color"] = colors[len(rooms) % len(colors)]
                    contour_room["detection_method"] = "contour_analysis"
                    rooms.append(contour_room)
        
        # Strategy 3: Fallback to object detection if still no rooms found
        if not rooms:
            print("Falling back to object detection for rooms...")
            room_objects = [obj for obj in objects if obj.name.lower() in ["room", "area", "space", "interior"]]
            
            for i, obj in enumerate(room_objects[:5]):  # Limit to 5 rooms
                vertices = obj.bounding_poly.normalized_vertices if obj.bounding_poly else []
                if not vertices:
                    continue
                    
                x = int(vertices[0].x * width)
                y = int(vertices[0].y * height)
                w = int((vertices[2].x - vertices[0].x) * width)
                h = int((vertices[2].y - vertices[0].y) * height)
                
                room = {
                    "room_id": i + 1,
                    "default_name": f"Room {i + 1}",
                    "boundaries": {"x": x, "y": y, "width": w, "height": h},
                    "color": colors[i % len(colors)],
                    "confidence": obj.score,
                    "doors": [],
                    "windows": [],
                    "measurements": [],
                    "detection_method": "object_detection"
                }
                rooms.append(room)
        
        # Strategy 4: Final fallback to dummy rooms
        if not rooms:
            print("Using dummy room generation as final fallback...")
            default_result = self._dummy_floor_plan_analysis(image_bytes)
            rooms = default_result["detected_rooms"]
            for room in rooms:
                room["detection_method"] = "dummy"
        
        print(f"Final room count: {len(rooms)}")
        return rooms
    
    def _rooms_overlap(self, bounds1: Dict, bounds2: Dict, threshold: float = 0.3) -> bool:
        """
        Check if two room boundaries overlap significantly
        """
        try:
            # Calculate overlap area
            x1_left, y1_top = bounds1["x"], bounds1["y"]
            x1_right, y1_bottom = x1_left + bounds1["width"], y1_top + bounds1["height"]
            
            x2_left, y2_top = bounds2["x"], bounds2["y"]
            x2_right, y2_bottom = x2_left + bounds2["width"], y2_top + bounds2["height"]
            
            # Calculate intersection
            left = max(x1_left, x2_left)
            top = max(y1_top, y2_top)
            right = min(x1_right, x2_right)
            bottom = min(y1_bottom, y2_bottom)
            
            if left < right and top < bottom:
                intersection_area = (right - left) * (bottom - top)
                area1 = bounds1["width"] * bounds1["height"]
                area2 = bounds2["width"] * bounds2["height"]
                min_area = min(area1, area2)
                
                overlap_ratio = intersection_area / min_area
                return overlap_ratio > threshold
            
            return False
        except:
            return False
    
    def _generate_room_description(self, room_name, x, y, total_width, total_height) -> str:
        """Generate detailed description for a room based on its position and name"""
        room_type = room_name.lower()
        
        # Determine room position in the floor plan
        position_x = "left side" if x < total_width/3 else "right side" if x > 2*total_width/3 else "central area"
        position_y = "upper" if y < total_height/3 else "lower" if y > 2*total_height/3 else "middle"
        
        # Generate description based on room type
        descriptions = {
            "kitchen": f"Located in the {position_y} {position_x} of the floor plan. "
                      f"Likely contains hard surfaces and potential gas connections. "
                      f"Consider fire hazards and water sources when evaluating safety.",
            
            "bedroom": f"Located in the {position_y} {position_x} of the floor plan. "
                      f"Check for multiple exits and window escape routes. "
                      f"Evaluate window measurements for emergency access.",
            
            "bathroom": f"Located in the {position_y} {position_x} of the floor plan. "
                       f"Consider water sources and slip hazards. "
                       f"Check if ventilation is adequate.",
            
            "living": f"Located in the {position_y} {position_x} of the floor plan. "
                    f"Typically a larger open space. "
                    f"Evaluate accessibility to exits and visibility lines.",
            
            "dining": f"Located in the {position_y} {position_x} of the floor plan. "
                     f"Often adjacent to kitchen areas. "
                     f"Check for clear exit pathways.",
                     
            "hall": f"Located in the {position_y} {position_x} of the floor plan. "
                   f"Important connection point between rooms. "
                   f"Evaluate as potential evacuation route.",
            
            "office": f"Located in the {position_y} {position_x} of the floor plan. "
                     f"Assess electrical safety and equipment placement. "
                     f"Check for adequate emergency exits.",
        }
        
        # Get description by room type, fallback to generic description
        for key, description in descriptions.items():
            if key in room_type:
                return description
        
        return f"Located in the {position_y} {position_x} of the floor plan. Check walls, windows, and doors for safety evaluation."
    
    def _identify_doors_and_windows(self, objects, width, height) -> Dict[str, List]:
        """Identify doors and windows from object detection"""
        doors = []
        windows = []
        
        # Keywords to identify doors and windows
        door_keywords = ["door", "entrance", "exit", "doorway"]
        window_keywords = ["window", "glass", "pane"]
        
        for obj in objects:
            obj_name = obj.name.lower()
            vertices = obj.bounding_poly.normalized_vertices
            x = int(vertices[0].x * width)
            y = int(vertices[0].y * height)
            w = int((vertices[2].x - vertices[0].x) * width)
            h = int((vertices[2].y - vertices[0].y) * height)
            
            element = {
                "position": {"x": x, "y": y},
                "width": w,
                "height": h,
                "confidence": obj.score
            }
            
            if any(keyword in obj_name for keyword in door_keywords):
                doors.append(element)
            elif any(keyword in obj_name for keyword in window_keywords):
                windows.append(element)
        
        return {
            "doors": doors,
            "windows": windows
        }
    
    def _extract_measurements(self, texts, doc_text, width, height) -> List[Dict]:
        """Extract measurements from text detection with enhanced pattern matching"""
        measurements = []
        
        # Enhanced measurement patterns
        import re
        patterns = [
            r'(\d+\.?\d*)\s*(cm|centimeter|centimeters)',
            r'(\d+\.?\d*)\s*(m|meter|meters)',
            r'(\d+\.?\d*)\s*(mm|millimeter|millimeters)',
            r'(\d+\.?\d*)\s*(ft|foot|feet)',
            r'(\d+\.?\d*)\s*(in|inch|inches|\")',
            r'(\d+\.?\d*)\s*(\'\s*\d*\.?\d*\"?)',  # feet and inches
            r'(\d+\.?\d*)\s*x\s*(\d+\.?\d*)\s*(cm|m|ft|in)',  # dimensions
            r'(\d+\.?\d*)\s*[×x]\s*(\d+\.?\d*)\s*(cm|m|ft|in)',  # dimensions with × symbol
        ]
        
        for text in texts[1:] if texts else []:  # Skip the first text which is usually the entire document
            text_content = text.description.lower()
            
            # Check each pattern
            for pattern in patterns:
                matches = re.findall(pattern, text_content, re.IGNORECASE)
                if matches:
                    vertices = text.bounding_poly.vertices if text.bounding_poly else []
                    if vertices:
                        x = min(v.x for v in vertices)
                        y = min(v.y for v in vertices)
                        
                        for match in matches:
                            if len(match) == 2:  # Simple measurement
                                value, unit = match
                                measurements.append({
                                    "type": "measurement",
                                    "value": f"{value} {unit}",
                                    "position": {"x": x, "y": y},
                                    "confidence": 0.8
                                })
                            elif len(match) == 3:  # Dimension measurement
                                val1, val2, unit = match
                                measurements.append({
                                    "type": "dimension",
                                    "value": f"{val1} x {val2} {unit}",
                                    "position": {"x": x, "y": y},
                                    "confidence": 0.9
                                })
        
        return measurements
    
    def _associate_elements_with_rooms(self, rooms, doors, windows, measurements):
        """Associate doors, windows and measurements with their respective rooms"""
        for door in doors:
            # Find the closest room for this door
            closest_room = self._find_closest_room(door["position"], rooms)
            if closest_room >= 0:
                rooms[closest_room]["doors"].append(door)
        
        for window in windows:
            # Find the closest room for this window
            closest_room = self._find_closest_room(window["position"], rooms)
            if closest_room >= 0:
                rooms[closest_room]["windows"].append(window)
                
        for measurement in measurements:
            # Find the closest room for this measurement
            closest_room = self._find_closest_room(measurement["position"], rooms)
            if closest_room >= 0:
                rooms[closest_room]["measurements"].append(measurement)
    
    def _find_closest_room(self, position, rooms):
        """Find the index of the closest room to a given position"""
        if not rooms:
            return -1
            
        closest_idx = -1
        min_distance = float('inf')
        
        for i, room in enumerate(rooms):
            bounds = room["boundaries"]
            room_center_x = bounds["x"] + bounds["width"] / 2
            room_center_y = bounds["y"] + bounds["height"] / 2
            
            # Calculate distance to room center
            dx = position["x"] - room_center_x
            dy = position["y"] - room_center_y
            distance = (dx * dx + dy * dy) ** 0.5
            
            if distance < min_distance:
                min_distance = distance
                closest_idx = i
                
        return closest_idx

    def _enhanced_room_boundary_detection(self, image_bytes: bytes, width: int, height: int) -> List[Dict]:
        """
        Enhanced room boundary detection using OpenCV contour analysis
        """
        try:
            # Convert image to OpenCV format
            image = Image.open(io.BytesIO(image_bytes))
            cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
            
            # Convert to grayscale
            gray = cv2.cvtColor(cv_image, cv2.COLOR_BGR2GRAY)
            
            # Apply threshold to get binary image
            _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            
            # Invert if necessary (walls should be black)
            if np.mean(binary) > 127:
                binary = cv2.bitwise_not(binary)
            
            # Apply morphological operations to clean up the image
            kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
            binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
            binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)
            
            # Find contours
            contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            
            rooms = []
            colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FECA57"]
            
            # Filter and process contours
            for i, contour in enumerate(contours):
                area = cv2.contourArea(contour)
                
                # Filter out very small areas (noise)
                min_area = (width * height) * 0.01  # At least 1% of image
                if area < min_area:
                    continue
                
                # Get bounding rectangle
                x, y, w, h = cv2.boundingRect(contour)
                
                # Filter out very thin rectangles (likely walls)
                aspect_ratio = max(w, h) / min(w, h)
                if aspect_ratio > 10:
                    continue
                
                # Calculate room properties
                room_area_sqm = (area / (width * height)) * 100  # Approximate conversion
                
                room = {
                    "room_id": i + 1,
                    "default_name": f"Room {i + 1}",
                    "boundaries": {"x": x, "y": y, "width": w, "height": h},
                    "color": colors[i % len(colors)],
                    "confidence": 0.7,
                    "doors": [],
                    "windows": [],
                    "measurements": [],
                    "area_pixels": int(area),
                    "estimated_dimensions": {
                        "width_cm": int(w * 0.5),  # Rough conversion
                        "length_cm": int(h * 0.5),
                        "area_sqm": round(room_area_sqm, 2),
                        "estimated_ceiling_height_cm": 250
                    }
                }
                rooms.append(room)
                
                # Limit to reasonable number of rooms
                if len(rooms) >= 8:
                    break
            
            return rooms
            
        except Exception as e:
            print(f"Enhanced room boundary detection failed: {e}")
            return []

# Global instance
vision_service = VisionService() 