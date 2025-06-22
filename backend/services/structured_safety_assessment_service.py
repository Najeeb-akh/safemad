from typing import List, Dict, Any, Optional
import json
from datetime import datetime
import uuid

from .structured_data_service import StructuredDataService
from ..models import (
    FloorPlanStructuredData,
    GeneralObject,
    RoomObject,
    StaircaseObject,
    ObjectType,
    LocationContext,
    WallMaterial,
    DetectionSource,
    log_user_interaction
)

class StructuredSafetyAssessmentService:
    """
    Safety assessment service using structured data system
    
    This service replaces the old unstructured safety assessment approach
    and uses the new structured data system for all safety-related operations.
    """
    
    def __init__(self):
        self.structured_data_service = StructuredDataService()
        self.safety_assessments: Dict[str, Dict[str, Any]] = {}
    
    def convert_unstructured_assessment_to_structured(
        self,
        old_assessment_data: Dict[str, Any],
        annotation_id: str
    ) -> str:
        """
        Convert old unstructured safety assessment data to new structured format
        
        Args:
            old_assessment_data: Old format assessment data
            annotation_id: ID of the floor plan annotation
            
        Returns:
            str: Analysis ID for the structured data
        """
        
        # Extract data from old format
        room_safety_data = old_assessment_data.get('room_safety_data', [])
        
        # Convert to structured format
        ai_detections = {'rooms': [], 'walls': [], 'doors': [], 'windows': []}
        user_annotations = []
        user_assessments = {}
        
        # Process each room assessment
        for room_data in room_safety_data:
            room_id = room_data.get('room_id', str(uuid.uuid4()))
            room_name = room_data.get('room_name', 'Unknown Room')
            room_type = room_data.get('room_type', 'room')
            responses = room_data.get('responses', {})
            
            # Add room to AI detections (even if user-created)
            ai_detections['rooms'].append({
                'id': room_id,
                'name': room_name,
                'type': room_type,
                'boundaries': [],  # Will be filled from annotation if available
                'area': 0,  # Will be calculated if boundaries available
                'confidence': 0.8  # Assume good confidence for existing data
            })
            
            # Convert responses to structured user assessments
            user_assessments[room_id] = {
                'room_responses': responses,
                'room_type': room_type,
                'room_name': room_name
            }
            
            # Extract wall information if available
            wall_material = responses.get('wall_material')
            wall_thickness = responses.get('wall_thickness')
            
            if wall_material or wall_thickness:
                # Create wall objects for this room
                wall_id = f"wall_{room_id}_perimeter"
                ai_detections['walls'].append({
                    'id': wall_id,
                    'room_id': room_id,
                    'material': wall_material,
                    'thickness_description': wall_thickness,
                    'location': 'room_perimeter'
                })
        
        # Convert to structured data
        analysis_id = self.structured_data_service.convert_and_store_data(
            ai_detections=ai_detections,
            user_annotations=user_annotations,
            user_assessments=user_assessments,
            user_id=annotation_id,  # Use annotation_id as user_id for now
            floor_plan_metadata={
                'converted_from_old_format': True,
                'original_annotation_id': annotation_id,
                'conversion_timestamp': datetime.now().isoformat()
            }
        )
        
        return analysis_id
    
    def submit_structured_safety_assessment(
        self,
        analysis_id: str,
        room_assessments: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """
        Submit safety assessment using structured data
        
        Args:
            analysis_id: ID of the structured floor plan data
            room_assessments: List of room assessment data
            
        Returns:
            Dict containing safety assessment results
        """
        
        # Get structured data
        structured_data = self.structured_data_service.get_structured_data(analysis_id)
        if not structured_data:
            raise ValueError(f"No structured data found for analysis ID: {analysis_id}")
        
        # Update room objects with assessment data
        self._update_rooms_with_assessments(structured_data, room_assessments)
        
        # Calculate safety scores using structured data
        room_scores = []
        for room in structured_data.rooms:
            score = self._calculate_structured_room_safety_score(room, structured_data)
            room_scores.append(score)
        
        # Find the safest room
        safest_room = max(room_scores, key=lambda x: x['safety_score']) if room_scores else None
        
        # Generate recommendations using structured data
        recommendations = self._generate_structured_safety_recommendations(structured_data, safest_room)
        
        # Generate overall assessment
        overall_assessment = self._generate_structured_overall_assessment(structured_data, room_scores)
        
        # Store the assessment result
        assessment_result = {
            'analysis_id': analysis_id,
            'room_scores': room_scores,
            'safest_room': safest_room,
            'recommendations': recommendations,
            'overall_assessment': overall_assessment,
            'assessment_timestamp': datetime.now().isoformat(),
            'structured_data_summary': {
                'total_objects': structured_data.total_objects_count,
                'rooms_count': len(structured_data.rooms),
                'walls_count': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.WALL]),
                'doors_count': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.DOOR]),
                'windows_count': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.WINDOW]),
                'mamad_count': len([room for room in structured_data.rooms if room.is_mamad])
            }
        }
        
        self.safety_assessments[analysis_id] = assessment_result
        
        return assessment_result
    
    def _update_rooms_with_assessments(
        self,
        structured_data: FloorPlanStructuredData,
        room_assessments: List[Dict[str, Any]]
    ):
        """Update room objects with assessment data"""
        
        assessment_by_room = {
            assessment.get('room_id'): assessment 
            for assessment in room_assessments
        }
        
        for room in structured_data.rooms:
            assessment = assessment_by_room.get(room.room_id)
            if not assessment:
                continue
                
            responses = assessment.get('responses', {})
            
            # Update wall thickness if provided
            wall_thickness = responses.get('wall_thickness')
            if wall_thickness:
                thickness_cm = self._parse_thickness_to_cm(wall_thickness)
                if thickness_cm:
                    room.wall_thickness_cm = thickness_cm
            
            # Update wall material
            wall_material = responses.get('wall_material')
            if wall_material:
                room.wall_material = self._parse_wall_material(wall_material)
            
            # Update door and window counts
            doors_count = responses.get('windows_count', '0')
            windows_count = responses.get('windows_count', '0')
            room.doors_count = self._parse_count(doors_count)
            room.windows_count = self._parse_count(windows_count)
            
            # Update accessibility information
            if responses.get('multiple_exits') == 'yes':
                room.has_multiple_exits = True
                room.emergency_egress_rating = 'good'
            elif responses.get('multiple_exits') == 'no':
                room.has_multiple_exits = False
                room.emergency_egress_rating = 'limited'
            
            # Update MAMAD-specific information
            if room.is_mamad or 'mamad' in room.room_type.lower():
                room.is_mamad = True
                room.has_air_filtration = responses.get('air_filtration') == 'yes'
                room.has_communication_system = responses.get('communication_device') == 'yes'
                room.has_emergency_supplies = responses.get('emergency_supplies') == 'yes'
            
            # Store all user assessments
            room.user_assessments.update(responses)
            
            # Log the assessment as user interaction
            log_user_interaction(
                structured_data=structured_data,
                action="safety_assessment",
                object_id=room.room_id,
                details=responses
            )
    
    def _calculate_structured_room_safety_score(
        self,
        room: RoomObject,
        structured_data: FloorPlanStructuredData
    ) -> Dict[str, Any]:
        """Calculate safety score for a room using structured data"""
        
        # Base scoring weights
        score_weights = {
            'structural': 0.35,      # Wall material, thickness, structural integrity
            'safety_features': 0.25, # Safety equipment and features
            'accessibility': 0.20,   # Multiple exits, clear pathways
            'environmental': 0.10,   # Ventilation, lighting, size
            'room_specific': 0.10    # Room-type specific factors
        }
        
        scores = {}
        
        # Structural Safety Score (0-100)
        structural_score = self._calculate_structural_score(room, structured_data)
        scores['structural'] = structural_score
        
        # Safety Features Score (0-100)
        safety_features_score = self._calculate_safety_features_score(room)
        scores['safety_features'] = safety_features_score
        
        # Accessibility Score (0-100)
        accessibility_score = self._calculate_accessibility_score(room)
        scores['accessibility'] = accessibility_score
        
        # Environmental Score (0-100)
        environmental_score = self._calculate_environmental_score(room)
        scores['environmental'] = environmental_score
        
        # Room-Specific Score (0-100)
        room_specific_score = self._calculate_room_specific_score(room)
        scores['room_specific'] = room_specific_score
        
        # Calculate weighted total score
        total_score = sum(scores[category] * score_weights[category] for category in scores)
        
        # Determine safety rating
        if total_score >= 85:
            rating = 'Excellent'
        elif total_score >= 70:
            rating = 'Good'
        elif total_score >= 55:
            rating = 'Fair'
        elif total_score >= 40:
            rating = 'Poor'
        else:
            rating = 'Very Poor'
        
        return {
            'room_id': room.room_id,
            'room_name': room.name,
            'room_type': room.room_type,
            'safety_score': round(total_score, 1),
            'safety_rating': rating,
            'score_breakdown': {
                'structural': round(scores['structural'], 1),
                'safety_features': round(scores['safety_features'], 1),
                'accessibility': round(scores['accessibility'], 1),
                'environmental': round(scores['environmental'], 1),
                'room_specific': round(scores['room_specific'], 1)
            },
            'is_mamad': room.is_mamad,
            'wall_material': room.wall_material.value if room.wall_material else None,
            'wall_thickness_cm': room.wall_thickness_cm,
            'has_multiple_exits': room.has_multiple_exits
        }
    
    def _calculate_structural_score(
        self,
        room: RoomObject,
        structured_data: FloorPlanStructuredData
    ) -> float:
        """Calculate structural safety score"""
        
        structural_score = 30  # Base score
        
        # Wall material scoring
        if room.wall_material:
            material_scores = {
                WallMaterial.CONCRETE: 100,
                WallMaterial.REINFORCED_CONCRETE: 100,
                WallMaterial.BRICK: 85,
                WallMaterial.CONCRETE_BLOCK: 80,
                WallMaterial.STEEL_FRAME: 75,
                WallMaterial.DRYWALL_STEEL_STUDS: 60,
                WallMaterial.DRYWALL_WOOD_STUDS: 50,
                WallMaterial.WOOD_FRAME: 45,
                WallMaterial.PREFAB_CONCRETE: 85,
                WallMaterial.UNKNOWN: 40
            }
            structural_score = material_scores.get(room.wall_material, 40) * 0.6
        
        # Wall thickness scoring
        if room.wall_thickness_cm:
            if room.wall_thickness_cm >= 30:
                thickness_score = 100
            elif room.wall_thickness_cm >= 20:
                thickness_score = 80
            elif room.wall_thickness_cm >= 10:
                thickness_score = 60
            else:
                thickness_score = 40
            
            structural_score += thickness_score * 0.4
        
        return min(100, structural_score)
    
    def _calculate_safety_features_score(self, room: RoomObject) -> float:
        """Calculate safety features score"""
        
        score = 40  # Base score
        responses = room.user_assessments
        
        # Safety equipment
        if responses.get('smoke_detector') == 'yes':
            score += 25
        if responses.get('fire_extinguisher') == 'yes':
            score += 20
        if responses.get('emergency_lighting') == 'yes':
            score += 15
        
        # MAMAD-specific features
        if room.is_mamad:
            score += 20  # Bonus for being a protected room
            if room.has_air_filtration:
                score += 25
            if room.has_communication_system:
                score += 20
            if room.has_emergency_supplies:
                score += 15
        
        # Deduct for hazards
        if responses.get('gas_lines') == 'yes':
            score -= 15
        
        return max(0, min(100, score))
    
    def _calculate_accessibility_score(self, room: RoomObject) -> float:
        """Calculate accessibility score"""
        
        score = 30  # Base score
        responses = room.user_assessments
        
        # Multiple exits
        if room.has_multiple_exits:
            score += 35
        elif room.doors_count > 1:
            score += 25
        elif room.doors_count == 1:
            score += 15
        
        # Clear pathways
        if responses.get('clear_pathways') == 'yes':
            score += 25
        
        # Window escape
        if responses.get('window_escape') == 'yes':
            score += 20
        
        # Handrails (for stairs and difficult access)
        if responses.get('handrails') == 'yes':
            score += 10
        
        return min(100, score)
    
    def _calculate_environmental_score(self, room: RoomObject) -> float:
        """Calculate environmental score"""
        
        score = 40  # Base score
        responses = room.user_assessments
        
        # Ventilation
        if responses.get('ventilation') == 'yes':
            score += 25
        
        # Water access
        if responses.get('water_access') == 'yes':
            score += 20
        
        # Ceiling height
        ceiling_height = responses.get('ceiling_height', '')
        if 'High' in ceiling_height:
            score += 20
        elif 'Normal' in ceiling_height:
            score += 15
        elif 'Low' in ceiling_height:
            score += 5
        
        # Windows for natural light and ventilation
        if room.windows_count > 0:
            score += min(15, room.windows_count * 5)
        
        return min(100, score)
    
    def _calculate_room_specific_score(self, room: RoomObject) -> float:
        """Calculate room-type specific score"""
        
        room_type = room.room_type.lower()
        responses = room.user_assessments
        score = 50  # Base score
        
        if 'mamad' in room_type:
            score = 85  # MAMAD is designed for safety
            if room.has_air_filtration:
                score += 10
            if room.has_communication_system:
                score += 5
                
        elif 'kitchen' in room_type:
            score = 25  # Kitchens have inherent risks
            if responses.get('fire_extinguisher') == 'yes':
                score += 30
            if responses.get('gas_lines') != 'yes':
                score += 20
                
        elif 'bedroom' in room_type:
            score = 60
            if responses.get('smoke_detector') == 'yes':
                score += 20
            if responses.get('window_escape') == 'yes':
                score += 15
                
        elif 'bathroom' in room_type:
            score = 55
            if responses.get('water_access') == 'yes':
                score += 25
            if responses.get('ventilation') == 'yes':
                score += 15
                
        elif 'balcony' in room_type:
            score = 35  # Outdoor areas are vulnerable
            if responses.get('weather_protection') == 'yes':
                score += 15
            if responses.get('structural_integrity') == 'yes':
                score += 25
        
        return max(0, min(100, score))
    
    def _generate_structured_safety_recommendations(
        self,
        structured_data: FloorPlanStructuredData,
        safest_room: Optional[Dict[str, Any]]
    ) -> List[str]:
        """Generate safety recommendations using structured data"""
        
        recommendations = []
        
        # Safest room recommendation
        if safest_room:
            recommendations.append(
                f"🏆 SAFEST ROOM: {safest_room['room_name']} ({safest_room['room_type']}) "
                f"with safety score of {safest_room['safety_score']}/100"
            )
        
        # Recommendations based on structured data
        for room in structured_data.rooms:
            responses = room.user_assessments
            room_name = room.name
            
            # Wall reinforcement recommendations
            if room.wall_material in [WallMaterial.DRYWALL_WOOD_STUDS, WallMaterial.WOOD_FRAME]:
                recommendations.append(f"🏗️ Consider reinforcing walls in {room_name}")
            
            # Thickness recommendations
            if room.wall_thickness_cm and room.wall_thickness_cm < 15:
                recommendations.append(f"📏 Walls in {room_name} are thin - consider reinforcement")
            
            # Safety equipment recommendations
            if responses.get('smoke_detector') == 'no':
                recommendations.append(f"🚨 Install smoke detector in {room_name}")
            
            if not room.has_multiple_exits and room.doors_count <= 1:
                recommendations.append(f"🚪 Consider additional exit routes for {room_name}")
            
            # MAMAD-specific recommendations
            if room.is_mamad:
                if not room.has_air_filtration:
                    recommendations.append(f"💨 Install air filtration system in MAMAD ({room_name})")
                if not room.has_communication_system:
                    recommendations.append(f"📞 Add communication equipment to MAMAD ({room_name})")
        
        # House-level recommendations
        mamad_rooms = [room for room in structured_data.rooms if room.is_mamad]
        if not mamad_rooms:
            recommendations.append("🏠 Consider designating or creating a MAMAD (protected room)")
        
        strong_rooms = [room for room in structured_data.rooms 
                       if room.wall_material in [WallMaterial.CONCRETE, WallMaterial.REINFORCED_CONCRETE]]
        if not strong_rooms:
            recommendations.append("🏗️ Consider reinforcing at least one room with concrete walls")
        
        return recommendations[:10]  # Limit to top 10 recommendations
    
    def _generate_structured_overall_assessment(
        self,
        structured_data: FloorPlanStructuredData,
        room_scores: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """Generate overall assessment using structured data"""
        
        if not room_scores:
            return {
                'average_safety_score': 0,
                'overall_rating': 'No Assessment',
                'total_rooms_assessed': 0
            }
        
        avg_score = sum(room['safety_score'] for room in room_scores) / len(room_scores)
        
        high_score_rooms = [room for room in room_scores if room['safety_score'] >= 70]
        low_score_rooms = [room for room in room_scores if room['safety_score'] < 50]
        mamad_rooms = [room for room in room_scores if room['is_mamad']]
        
        assessment = {
            'average_safety_score': round(avg_score, 1),
            'total_rooms_assessed': len(room_scores),
            'high_safety_rooms': len(high_score_rooms),
            'rooms_needing_improvement': len(low_score_rooms),
            'mamad_rooms_count': len(mamad_rooms),
            'overall_rating': (
                'Excellent' if avg_score >= 80 else 
                'Good' if avg_score >= 65 else 
                'Fair' if avg_score >= 50 else 
                'Needs Improvement'
            ),
            'structured_data_insights': {
                'total_objects_analyzed': structured_data.total_objects_count,
                'detection_sources': list(set([
                    obj.detection_metadata.detection_source.value 
                    for obj in structured_data.general_objects + structured_data.rooms + structured_data.staircases
                ])),
                'user_interactions_count': len(structured_data.user_interaction_log),
                'has_mamad': len(mamad_rooms) > 0,
                'concrete_rooms_count': len([
                    room for room in structured_data.rooms 
                    if room.wall_material in [WallMaterial.CONCRETE, WallMaterial.REINFORCED_CONCRETE]
                ])
            }
        }
        
        return assessment
    
    # Helper methods
    def _parse_thickness_to_cm(self, thickness_str: str) -> Optional[float]:
        """Parse thickness string to centimeters"""
        thickness_str = thickness_str.lower()
        
        if 'very thick' in thickness_str or '>30cm' in thickness_str:
            return 35.0
        elif 'thick' in thickness_str or '20-30cm' in thickness_str:
            return 25.0
        elif 'medium' in thickness_str or '10-20cm' in thickness_str:
            return 15.0
        elif 'thin' in thickness_str or '<10cm' in thickness_str:
            return 8.0
        
        # Try to extract number
        import re
        numbers = re.findall(r'\d+', thickness_str)
        if numbers:
            return float(numbers[0])
        
        return None
    
    def _parse_wall_material(self, material_str: str) -> WallMaterial:
        """Parse wall material string to enum"""
        material_str = material_str.lower()
        
        if 'concrete' in material_str:
            return WallMaterial.CONCRETE
        elif 'brick' in material_str:
            return WallMaterial.BRICK
        elif 'steel' in material_str:
            return WallMaterial.STEEL_FRAME
        elif 'drywall' in material_str:
            return WallMaterial.DRYWALL_STEEL_STUDS
        elif 'wood' in material_str:
            return WallMaterial.WOOD_FRAME
        else:
            return WallMaterial.UNKNOWN
    
    def _parse_count(self, count_str: str) -> int:
        """Parse count string to integer"""
        if not count_str or count_str.lower() == 'none':
            return 0
        
        count_str = count_str.lower()
        if '4+' in count_str or 'more' in count_str:
            return 4
        
        # Extract first number
        import re
        numbers = re.findall(r'\d+', count_str)
        if numbers:
            return int(numbers[0])
        
        return 0
    
    def get_safety_assessment(self, analysis_id: str) -> Optional[Dict[str, Any]]:
        """Get safety assessment results"""
        return self.safety_assessments.get(analysis_id)
    
    def get_assessment_for_heatmap(self, analysis_id: str) -> Dict[str, Any]:
        """Get assessment data formatted for heatmap generation"""
        
        structured_data = self.structured_data_service.get_structured_data(analysis_id)
        if not structured_data:
            raise ValueError(f"No structured data found for analysis ID: {analysis_id}")
        
        # Format for heatmap
        rooms_data = []
        for room in structured_data.rooms:
            room_data = {
                'id': room.room_id,
                'name': room.name,
                'type': room.room_type,
                'boundaries': room.floor_plan_reference.get('boundaries', []),
                'area_m2': room.size.area_m2 if room.size else 0,
                'internal_wall_thickness_cm': room.wall_thickness_cm or 10.0,
                'is_mamad': room.is_mamad,
                'has_air_filtration': room.has_air_filtration or False,
                'has_blast_door': room.has_blast_door or False,
                'has_communication_system': room.has_communication_system or False,
                'has_emergency_supplies': room.has_emergency_supplies or False,
            }
            rooms_data.append(room_data)
            
            # Debug logging for MAMAD rooms
            if room.is_mamad:
                print(f"🔒 MAMAD room found in structured data: {room.name} (ID: {room.room_id})")
                print(f"   Room type: {room.room_type}")
                print(f"   Is MAMAD: {room.is_mamad}")
                print(f"   Has air filtration: {room.has_air_filtration}")
                print(f"   Has communication: {room.has_communication_system}")
        
        print(f"📊 Total rooms formatted for heatmap: {len(rooms_data)}")
        print(f"🔒 MAMAD rooms count: {sum(1 for r in rooms_data if r['is_mamad'])}")
        
        walls_data = []
        doors_data = []
        windows_data = []
        
        for obj in structured_data.general_objects:
            obj_data = {
                'id': obj.object_id,
                'name': obj.name,
                'location': obj.location.model_dump() if obj.location else {},
                'size': obj.size.model_dump() if obj.size else {},
            }
            
            if obj.object_type == ObjectType.WALL:
                obj_data.update({
                    'material': obj.material.value if hasattr(obj, 'material') and obj.material else 'unknown',
                    'thickness_cm': obj.thickness_cm if hasattr(obj, 'thickness_cm') else 10.0,
                    'indoor_outdoor': obj.indoor_outdoor.value if hasattr(obj, 'indoor_outdoor') else 'indoor'
                })
                walls_data.append(obj_data)
                
            elif obj.object_type == ObjectType.DOOR:
                doors_data.append(obj_data)
                
            elif obj.object_type == ObjectType.WINDOW:
                windows_data.append(obj_data)
        
        return {
            'house_boundaries': structured_data.house_boundaries,
            'rooms': rooms_data,
            'external_walls': walls_data,  # All walls for now
            'windows': windows_data,
            'doors': doors_data,
            'safety_assessments': [],  # Will be filled by assessment service
            'staircases': [
                {
                    'id': stair.staircase_id,
                    'name': stair.name,
                    'location': stair.location.model_dump() if stair.location else {},
                    'size': stair.size.model_dump() if stair.size else {},
                }
                for stair in structured_data.staircases
            ]
        }