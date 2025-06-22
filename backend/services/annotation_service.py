from typing import List, Dict, Any
import json
from datetime import datetime

class AnnotationService:
    def __init__(self):
        # In a real app, you'd store this in a database
        self.saved_annotations = {}
    
    def save_annotations(self, user_id: str, annotations: Dict[str, Any]) -> Dict[str, Any]:
        """
        Save user-annotated floor plan data including drawing annotations
        """
        annotation_id = f"{user_id}_{datetime.now().timestamp()}"
        
        # Handle different annotation types
        rooms = annotations.get("rooms", [])
        drawings = annotations.get("annotations", [])  # Drawing annotations from Flutter
        image_size = annotations.get("imageSize", {})
        
        processed_annotations = {
            "id": annotation_id,
            "user_id": user_id,
            "timestamp": datetime.now().isoformat(),
            "rooms": self._process_rooms(rooms),
            "drawing_annotations": self._process_drawing_annotations(drawings),
            "image_size": image_size,
            "image_dimensions": annotations.get("image_dimensions", image_size),
            "display_dimensions": annotations.get("display_dimensions", {}),
            "metadata": {
                "total_rooms": len(rooms),
                "total_drawings": len(drawings),
                "room_types": self._extract_room_types(rooms),
                "drawing_tools_used": self._extract_drawing_tools(drawings),
                "annotation_method": "interactive_with_drawings" if drawings else "manual_interactive"
            }
        }
        
        # Store annotations (in production, save to database)
        self.saved_annotations[annotation_id] = processed_annotations
        
        return {
            "success": True,
            "annotation_id": annotation_id,
            "message": "Floor plan annotations and drawings saved successfully",
            "summary": processed_annotations["metadata"]
        }
    
    def _process_rooms(self, rooms: List[Dict]) -> List[Dict]:
        """
        Process and validate room data
        """
        processed_rooms = []
        
        for room in rooms:
            processed_room = {
                "id": room.get("id"),
                "name": room.get("name", "Unnamed Room"),
                "type": room.get("type", "Other"),
                "color": room.get("color"),
                "boundary": self._process_boundary(room.get("boundary", {})),
                "area": self._calculate_area(room.get("boundary", {})),
                "safety_features": self._analyze_room_safety(room)
            }
            processed_rooms.append(processed_room)
        
        return processed_rooms
    
    def _process_boundary(self, boundary: Dict) -> Dict:
        """
        Process room boundary data
        """
        if boundary.get("type") == "rectangle":
            return {
                "type": "rectangle",
                "coordinates": {
                    "top_left": boundary.get("topLeft", {}),
                    "bottom_right": boundary.get("bottomRight", {})
                }
            }
        elif boundary.get("type") == "polygon":
            return {
                "type": "polygon",
                "coordinates": {
                    "points": boundary.get("points", [])
                }
            }
        return boundary
    
    def _calculate_area(self, boundary: Dict) -> float:
        """
        Calculate room area based on boundary type
        """
        if boundary.get("type") == "rectangle":
            top_left = boundary.get("topLeft", {})
            bottom_right = boundary.get("bottomRight", {})
            
            if top_left and bottom_right:
                width = abs(bottom_right.get("x", 0) - top_left.get("x", 0))
                height = abs(bottom_right.get("y", 0) - top_left.get("y", 0))
                return width * height
        
        elif boundary.get("type") == "polygon":
            points = boundary.get("points", [])
            if len(points) >= 3:
                # Calculate polygon area using shoelace formula
                area = 0
                n = len(points)
                for i in range(n):
                    j = (i + 1) % n
                    area += points[i].get("x", 0) * points[j].get("y", 0)
                    area -= points[j].get("x", 0) * points[i].get("y", 0)
                return abs(area) / 2
        
        return 0.0
    
    def _extract_room_types(self, rooms: List[Dict]) -> List[str]:
        """
        Extract unique room types from the annotations
        """
        room_types = set()
        for room in rooms:
            room_types.add(room.get("type", "Other"))
        return list(room_types)
    
    def _analyze_room_safety(self, room: Dict) -> Dict[str, Any]:
        """
        Analyze room safety features based on room type and layout
        """
        room_type = room.get("type", "").lower()
        safety_features = {
            "fire_safety_rating": "medium",  # Default
            "accessibility": "unknown",
            "emergency_exits": 1,  # Assume at least one door
            "recommendations": []
        }
        
        # Room-specific safety analysis
        if "bedroom" in room_type:
            safety_features.update({
                "fire_safety_rating": "high",
                "recommendations": [
                    "Install smoke detector",
                    "Ensure clear path to exit",
                    "Consider escape ladder for upper floors"
                ]
            })
        elif "kitchen" in room_type:
            safety_features.update({
                "fire_safety_rating": "high",
                "recommendations": [
                    "Install fire extinguisher",
                    "Ensure proper ventilation",
                    "Keep exit path clear"
                ]
            })
        elif "bathroom" in room_type:
            safety_features.update({
                "accessibility": "requires_assessment",
                "recommendations": [
                    "Install non-slip surfaces",
                    "Ensure adequate lighting",
                    "Consider grab bars"
                ]
            })
        elif "living" in room_type or "family" in room_type:
            safety_features.update({
                "fire_safety_rating": "medium",
                "recommendations": [
                    "Keep furniture away from exits",
                    "Secure heavy furniture to walls",
                    "Install adequate lighting"
                ]
            })
        elif "mamad" in room_type:
            safety_features.update({
                "fire_safety_rating": "very_high",
                "accessibility": "reinforced",
                "emergency_exits": 1,
                "recommendations": [
                    "Verify structural integrity regularly",
                    "Keep emergency supplies stocked",
                    "Ensure ventilation system works",
                    "Check door sealing mechanism",
                    "Maintain communication equipment"
                ]
            })
        elif "staircase" in room_type:
            safety_features.update({
                "fire_safety_rating": "critical",
                "accessibility": "high_risk",
                "emergency_exits": 0,  # Staircases are pathways, not destinations
                "recommendations": [
                    "Install proper lighting with backup power",
                    "Ensure handrails are secure",
                    "Keep stairs clear of obstacles",
                    "Install non-slip surfaces",
                    "Consider emergency lighting"
                                 ]
             })
        elif "balcony" in room_type:
            safety_features.update({
                "fire_safety_rating": "medium",
                "accessibility": "weather_dependent",
                "emergency_exits": 1,
                "recommendations": [
                    "Ensure proper railing height and integrity",
                    "Install adequate lighting",
                    "Keep drainage clear",
                    "Consider weather protection",
                    "Secure loose items that could fall"
                ]
            })
        
        return safety_features
    
    def _process_drawing_annotations(self, drawings: List[Dict]) -> List[Dict]:
        """
        Process and structure drawing annotations consistently with rooms and other objects
        """
        processed_drawings = []
        
        for drawing in drawings:
            # Extract points and calculate geometric properties
            points = drawing.get("points", [])
            
            # Structure drawing annotation like rooms and architectural elements
            processed_drawing = {
                "id": drawing.get("id"),
                "type": "user_annotation",
                "element_type": self._classify_drawing_element(drawing.get("tool", "freehand")),
                "tool_used": drawing.get("tool", "freehand"),
                "color": drawing.get("color"),
                "stroke_width": drawing.get("strokeWidth", 1.0),
                "timestamp": drawing.get("timestamp"),
                
                # Geometric properties (consistent with architectural elements)
                "geometry": {
                    "points": points,
                    "total_points": len(points),
                    "path_length": self._calculate_path_length(points),
                    "bounding_box": self._calculate_bounding_box(points),
                    "center": self._calculate_center(points),
                    "area": self._calculate_drawing_area(points, drawing.get("tool")),
                },
                
                # Mathematical properties for future calculations
                "mathematical_properties": {
                    "coordinate_system": "image_pixels",
                    "precision": "user_drawn",
                    "confidence": self._calculate_drawing_confidence(drawing),
                    "smoothness": self._calculate_path_smoothness(points),
                    "complexity": self._calculate_drawing_complexity(points),
                },
                
                # Spatial relationships (like rooms)
                "spatial_properties": {
                    "relative_position": self._calculate_relative_position(points),
                    "orientation": self._calculate_drawing_orientation(points),
                    "scale_factor": 1.0,  # Can be adjusted based on image scaling
                },
                
                # Safety and functional analysis (consistent with room analysis)
                "functional_analysis": {
                    "purpose": self._infer_drawing_purpose(drawing.get("tool")),
                    "safety_impact": self._analyze_drawing_safety_impact(drawing.get("tool")),
                    "structural_relevance": self._assess_structural_relevance(drawing.get("tool")),
                },
                
                # Quality metrics
                "quality_metrics": {
                    "drawing_quality": self._assess_drawing_quality(points),
                    "completeness": self._assess_drawing_completeness(drawing.get("tool"), points),
                    "accuracy_estimate": self._estimate_drawing_accuracy(drawing.get("tool"), points),
                }
            }
            
            processed_drawings.append(processed_drawing)
        
        return processed_drawings
    
    def _classify_drawing_element(self, tool: str) -> str:
        """
        Classify what architectural element the drawing represents
        """
        tool_mapping = {
            "wall": "structural_wall",
            "door": "door_opening",
            "window": "window_opening",
            "area": "room_boundary",
            "freehand": "user_annotation"
        }
        return tool_mapping.get(tool, "user_annotation")
    
    def _calculate_drawing_confidence(self, drawing: Dict) -> float:
        """
        Calculate confidence score for user drawings based on tool and stroke quality
        """
        tool = drawing.get("tool", "freehand")
        points = drawing.get("points", [])
        
        # Base confidence based on tool type
        tool_confidence = {
            "wall": 0.9,    # Walls are usually drawn intentionally
            "door": 0.85,   # Doors are specific elements
            "window": 0.85, # Windows are specific elements
            "area": 0.8,    # Area boundaries are intentional
            "freehand": 0.6 # Freehand could be notes or corrections
        }
        
        base_confidence = tool_confidence.get(tool, 0.5)
        
        # Adjust based on stroke characteristics
        if len(points) < 2:
            return 0.1  # Very low confidence for single points
        elif len(points) < 5:
            return base_confidence * 0.7  # Reduce for very short strokes
        else:
            return base_confidence
    
    def _extract_drawing_tools(self, drawings: List[Dict]) -> List[str]:
        """
        Extract unique drawing tools used in the annotations
        """
        tools = set()
        for drawing in drawings:
            tools.add(drawing.get("tool", "freehand"))
        return list(tools)
    
    def _calculate_path_length(self, points: List[Dict]) -> float:
        """Calculate the total length of a drawn path"""
        if len(points) < 2:
            return 0.0
        
        total_length = 0.0
        for i in range(1, len(points)):
            x1, y1 = points[i-1].get('x', 0), points[i-1].get('y', 0)
            x2, y2 = points[i].get('x', 0), points[i].get('y', 0)
            total_length += ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
        
        return total_length
    
    def _calculate_bounding_box(self, points: List[Dict]) -> Dict[str, float]:
        """Calculate bounding box of drawn points"""
        if not points:
            return {"x": 0, "y": 0, "width": 0, "height": 0}
        
        x_coords = [p.get('x', 0) for p in points]
        y_coords = [p.get('y', 0) for p in points]
        
        min_x, max_x = min(x_coords), max(x_coords)
        min_y, max_y = min(y_coords), max(y_coords)
        
        return {
            "x": min_x,
            "y": min_y,
            "width": max_x - min_x,
            "height": max_y - min_y
        }
    
    def _calculate_center(self, points: List[Dict]) -> Dict[str, float]:
        """Calculate center point of drawn annotation"""
        if not points:
            return {"x": 0, "y": 0}
        
        x_coords = [p.get('x', 0) for p in points]
        y_coords = [p.get('y', 0) for p in points]
        
        return {
            "x": sum(x_coords) / len(x_coords),
            "y": sum(y_coords) / len(y_coords)
        }
    
    def _calculate_drawing_area(self, points: List[Dict], tool: str) -> float:
        """Calculate area enclosed by drawing (for area tool) or approximate coverage area"""
        if not points or len(points) < 3:
            return 0.0
        
        if tool == "area":
            # Use shoelace formula for polygon area
            area = 0.0
            n = len(points)
            for i in range(n):
                j = (i + 1) % n
                area += points[i].get('x', 0) * points[j].get('y', 0)
                area -= points[j].get('x', 0) * points[i].get('y', 0)
            return abs(area) / 2.0
        else:
            # For other tools, calculate approximate coverage area based on bounding box
            bbox = self._calculate_bounding_box(points)
            return bbox["width"] * bbox["height"]
    
    def _calculate_path_smoothness(self, points: List[Dict]) -> float:
        """Calculate smoothness of drawn path (0-1, higher is smoother)"""
        if len(points) < 3:
            return 1.0
        
        # Calculate angle changes between consecutive line segments
        angle_changes = []
        for i in range(1, len(points) - 1):
            p1 = points[i-1]
            p2 = points[i]
            p3 = points[i+1]
            
            # Calculate vectors
            v1_x, v1_y = p2.get('x', 0) - p1.get('x', 0), p2.get('y', 0) - p1.get('y', 0)
            v2_x, v2_y = p3.get('x', 0) - p2.get('x', 0), p3.get('y', 0) - p2.get('y', 0)
            
            # Calculate angle change (simplified)
            if v1_x != 0 or v1_y != 0 and v2_x != 0 or v2_y != 0:
                dot_product = v1_x * v2_x + v1_y * v2_y
                mag1 = (v1_x ** 2 + v1_y ** 2) ** 0.5
                mag2 = (v2_x ** 2 + v2_y ** 2) ** 0.5
                
                if mag1 > 0 and mag2 > 0:
                    cos_angle = dot_product / (mag1 * mag2)
                    cos_angle = max(-1, min(1, cos_angle))  # Clamp to [-1, 1]
                    angle_changes.append(abs(cos_angle))
        
        if not angle_changes:
            return 1.0
        
        # Average smoothness (higher values = smoother)
        return sum(angle_changes) / len(angle_changes)
    
    def _calculate_drawing_complexity(self, points: List[Dict]) -> float:
        """Calculate complexity of drawing based on point density and path changes"""
        if len(points) < 2:
            return 0.0
        
        path_length = self._calculate_path_length(points)
        if path_length == 0:
            return 0.0
        
        # Complexity based on points per unit length
        point_density = len(points) / path_length
        
        # Normalize to 0-1 scale (adjust multiplier as needed)
        return min(1.0, point_density * 100)
    
    def _calculate_relative_position(self, points: List[Dict]) -> str:
        """Calculate relative position in image (similar to room positioning)"""
        if not points:
            return "unknown"
        
        center = self._calculate_center(points)
        x, y = center["x"], center["y"]
        
        # Assume image coordinates (adjust based on actual image dimensions)
        # This is a simplified version - you might want to use actual image dimensions
        if x < 300 and y < 300:
            return "top_left"
        elif x > 700 and y < 300:
            return "top_right"
        elif x < 300 and y > 700:
            return "bottom_left"
        elif x > 700 and y > 700:
            return "bottom_right"
        elif y < 300:
            return "top_center"
        elif y > 700:
            return "bottom_center"
        elif x < 300:
            return "center_left"
        elif x > 700:
            return "center_right"
        else:
            return "center"
    
    def _calculate_drawing_orientation(self, points: List[Dict]) -> str:
        """Calculate general orientation of the drawing"""
        if len(points) < 2:
            return "point"
        
        bbox = self._calculate_bounding_box(points)
        width, height = bbox["width"], bbox["height"]
        
        if width > height * 1.5:
            return "horizontal"
        elif height > width * 1.5:
            return "vertical"
        else:
            return "diagonal"
    
    def _infer_drawing_purpose(self, tool: str) -> str:
        """Infer the purpose of the drawing based on the tool used"""
        purposes = {
            "wall": "structural_element",
            "door": "access_point",
            "window": "opening",
            "area": "space_definition",
            "freehand": "general_annotation"
        }
        return purposes.get(tool, "unknown")
    
    def _analyze_drawing_safety_impact(self, tool: str) -> str:
        """Analyze safety impact of the drawn element"""
        safety_impacts = {
            "wall": "structural_safety",
            "door": "egress_safety",
            "window": "emergency_access",
            "area": "space_safety",
            "freehand": "annotation_only"
        }
        return safety_impacts.get(tool, "neutral")
    
    def _assess_structural_relevance(self, tool: str) -> str:
        """Assess structural relevance of the drawing"""
        relevance = {
            "wall": "high",
            "door": "medium",
            "window": "medium",
            "area": "low",
            "freehand": "low"
        }
        return relevance.get(tool, "unknown")
    
    def _assess_drawing_quality(self, points: List[Dict]) -> str:
        """Assess the quality of the drawing"""
        if len(points) < 2:
            return "poor"
        elif len(points) < 5:
            return "basic"
        elif len(points) < 20:
            return "good"
        else:
            return "detailed"
    
    def _assess_drawing_completeness(self, tool: str, points: List[Dict]) -> str:
        """Assess if the drawing appears complete for its intended purpose"""
        if not points:
            return "incomplete"
        
        path_length = self._calculate_path_length(points)
        
        if tool == "area" and len(points) >= 3:
            # Check if area is closed (first and last points are close)
            first, last = points[0], points[-1]
            distance = ((last.get('x', 0) - first.get('x', 0)) ** 2 + 
                       (last.get('y', 0) - first.get('y', 0)) ** 2) ** 0.5
            return "complete" if distance < 20 else "open"
        elif tool in ["wall", "door", "window"] and path_length > 50:
            return "complete"
        elif tool == "freehand":
            return "complete"  # Freehand is always considered complete
        else:
            return "partial"
    
    def _estimate_drawing_accuracy(self, tool: str, points: List[Dict]) -> float:
        """Estimate accuracy of the drawing (0-1 scale)"""
        if not points:
            return 0.0
        
        # Base accuracy on tool type and drawing characteristics
        base_accuracy = {
            "wall": 0.8,      # Walls are usually drawn with intent
            "door": 0.7,      # Doors require specific placement
            "window": 0.7,    # Windows require specific placement
            "area": 0.6,      # Areas can be approximate
            "freehand": 0.5   # Freehand is most subjective
        }.get(tool, 0.5)
        
        # Adjust based on smoothness and complexity
        smoothness = self._calculate_path_smoothness(points)
        complexity = self._calculate_drawing_complexity(points)
        
        # Higher smoothness and moderate complexity suggest better accuracy
        accuracy_adjustment = (smoothness * 0.3) + (min(complexity, 0.5) * 0.2)
        
        return min(1.0, base_accuracy + accuracy_adjustment)
    
    def get_annotations(self, annotation_id: str) -> Dict[str, Any]:
        """
        Retrieve saved annotations by ID
        """
        if annotation_id in self.saved_annotations:
            return self.saved_annotations[annotation_id]
        return {"error": "Annotation not found"}
    
    def get_user_annotations(self, user_id: str) -> List[Dict[str, Any]]:
        """
        Get all annotations for a specific user
        """
        user_annotations = []
        for annotation_id, annotation in self.saved_annotations.items():
            if annotation.get("user_id") == user_id:
                user_annotations.append(annotation)
        return user_annotations
    
    def generate_safety_report(self, annotation_id: str) -> Dict[str, Any]:
        """
        Generate a comprehensive safety report based on annotated floor plan
        """
        annotation = self.get_annotations(annotation_id)
        if "error" in annotation:
            return annotation
        
        rooms = annotation.get("rooms", [])
        total_area = sum(room.get("area", 0) for room in rooms)
        
        # Analyze overall home safety
        safety_score = self._calculate_overall_safety_score(rooms)
        
        report = {
            "annotation_id": annotation_id,
            "generated_at": datetime.now().isoformat(),
            "summary": {
                "total_rooms": len(rooms),
                "total_area": total_area,
                "overall_safety_score": safety_score,
                "room_types": annotation.get("metadata", {}).get("room_types", [])
            },
            "room_analysis": rooms,
            "recommendations": self._generate_home_recommendations(rooms),
            "emergency_plan": self._create_emergency_plan(rooms)
        }
        
        return report
    
    def _calculate_overall_safety_score(self, rooms: List[Dict]) -> int:
        """
        Calculate overall home safety score (0-100)
        """
        if not rooms:
            return 0
        
        room_scores = []
        for room in rooms:
            safety_features = room.get("safety_features", {})
            rating = safety_features.get("fire_safety_rating", "medium")
            
            if rating == "high":
                room_scores.append(85)
            elif rating == "medium":
                room_scores.append(70)
            else:
                room_scores.append(50)
        
        return int(sum(room_scores) / len(room_scores))
    
    def _generate_home_recommendations(self, rooms: List[Dict]) -> List[str]:
        """
        Generate overall home safety recommendations
        """
        recommendations = [
            "Install smoke detectors in all rooms",
            "Create and practice emergency evacuation plan",
            "Keep flashlights and emergency supplies accessible"
        ]
        
        # Room-specific recommendations
        room_types = [room.get("type", "").lower() for room in rooms]
        
        if any("bedroom" in rt for rt in room_types):
            recommendations.append("Install carbon monoxide detectors near bedrooms")
        
        if any("kitchen" in rt for rt in room_types):
            recommendations.append("Keep fire extinguisher in kitchen area")
        
        if len(rooms) > 5:
            recommendations.append("Consider professional home safety assessment")
        
        return recommendations
    
    def _create_emergency_plan(self, rooms: List[Dict]) -> Dict[str, Any]:
        """
        Create basic emergency evacuation plan
        """
        bedrooms = [r for r in rooms if "bedroom" in r.get("type", "").lower()]
        living_areas = [r for r in rooms if any(term in r.get("type", "").lower() 
                                               for term in ["living", "family", "dining"])]
        
        plan = {
            "primary_exit": "Main entrance (front door)",
            "secondary_exit": "Back door or large window",
            "meeting_point": "Outside at a safe distance from house",
            "bedroom_exits": len(bedrooms),
            "evacuation_routes": [
                "From bedrooms: Move to nearest exit avoiding kitchen if possible",
                "From living areas: Use main entrance unless blocked",
                "If smoke present: Stay low and feel doors before opening"
            ],
            "emergency_contacts": {
                "fire_department": "911",
                "police": "911",
                "medical": "911"
            }
        }
        
        return plan

# Global instance
annotation_service = AnnotationService() 