from typing import List, Dict, Any, Optional
import json
from datetime import datetime
import uuid

from ..models import (
    FloorPlanStructuredData,
    GeneralObject,
    RoomObject,
    StaircaseObject,
    ObjectType,
    LocationContext,
    WallMaterial,
    DetectionSource,
    BaseObjectLocation,
    BaseObjectSize,
    DetectionMetadata,
    create_from_existing_data,
    log_user_interaction
)

class StructuredDataService:
    """
    Service for managing structured floor plan data
    
    This service handles:
    - Converting unstructured data to structured format
    - Storing and retrieving structured data
    - Managing user interactions and logs
    - Providing analysis-ready data structure
    """
    
    def __init__(self):
        # In production, this would be replaced with database storage
        self.structured_data_storage: Dict[str, FloorPlanStructuredData] = {}
        self.analysis_metadata: Dict[str, Dict[str, Any]] = {}
    
    def convert_and_store_data(
        self,
        ai_detections: Dict[str, Any],
        user_annotations: List[Dict[str, Any]],
        user_assessments: Dict[str, Any],
        user_id: Optional[str] = None,
        floor_plan_metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Convert unstructured data to structured format and store it
        
        Args:
            ai_detections: Raw AI detection results
            user_annotations: User-drawn annotations  
            user_assessments: User safety assessments and measurements
            user_id: Optional user identifier
            floor_plan_metadata: Metadata about the floor plan image
        
        Returns:
            str: Analysis ID for the stored structured data
        """
        
        # Convert to structured format
        structured_data = create_from_existing_data(
            ai_detections=ai_detections,
            user_annotations=user_annotations,
            user_assessments=user_assessments
        )
        
        # Set user ID and metadata
        structured_data.user_id = user_id
        if floor_plan_metadata:
            structured_data.floor_plan_metadata = floor_plan_metadata
        
        # Extract house-level data from user annotations if available
        self._extract_house_level_data(structured_data, user_annotations, ai_detections)
        
        # Store the structured data
        analysis_id = structured_data.analysis_id
        self.structured_data_storage[analysis_id] = structured_data
        
        # Store analysis metadata for quick access
        self.analysis_metadata[analysis_id] = {
            'user_id': user_id,
            'timestamp': structured_data.timestamp.isoformat(),
            'total_objects': structured_data.total_objects_count,
            'objects_by_type': structured_data.objects_by_type,
            'has_mamad': any(room.is_mamad for room in structured_data.rooms),
            'detection_sources': list(set([
                obj.detection_metadata.detection_source for obj in structured_data.general_objects
            ] + [
                room.detection_metadata.detection_source for room in structured_data.rooms  
            ] + [
                stair.detection_metadata.detection_source for stair in structured_data.staircases
            ]))
        }
        
        print(f"✅ newwwww Structured data stored with analysis ID: {analysis_id}")
        print(f"   Total objects: {structured_data.total_objects_count}")
        print(f"   Rooms: {len(structured_data.rooms)}")
        print(f"   General objects: {len(structured_data.general_objects)}")
        print(f"   Staircases: {len(structured_data.staircases)}")
        
        return analysis_id
    
    def get_structured_data(self, analysis_id: str) -> Optional[FloorPlanStructuredData]:
        """Get structured data by analysis ID"""
        return self.structured_data_storage.get(analysis_id)
    
    def get_analysis_metadata(self, analysis_id: str) -> Optional[Dict[str, Any]]:
        """Get analysis metadata by ID"""
        return self.analysis_metadata.get(analysis_id)
    
    def list_user_analyses(self, user_id: str) -> List[Dict[str, Any]]:
        """List all analyses for a specific user"""
        user_analyses = []
        for analysis_id, metadata in self.analysis_metadata.items():
            if metadata.get('user_id') == user_id:
                user_analyses.append({
                    'analysis_id': analysis_id,
                    **metadata
                })
        return user_analyses
    
    def update_object(
        self, 
        analysis_id: str, 
        object_id: str, 
        updates: Dict[str, Any],
        user_action: str = "modified"
    ) -> bool:
        """
        Update a specific object in the structured data
        
        Args:
            analysis_id: ID of the analysis
            object_id: ID of the object to update
            updates: Dictionary of field updates
            user_action: Description of the user action
        
        Returns:
            bool: Success status
        """
        
        structured_data = self.structured_data_storage.get(analysis_id)
        if not structured_data:
            return False
        
        # Find and update the object
        updated = False
        
        # Check general objects
        for obj in structured_data.general_objects:
            if obj.object_id == object_id:
                for field, value in updates.items():
                    if hasattr(obj, field):
                        setattr(obj, field, value)
                obj.detection_metadata.user_modified = True
                updated = True
                break
        
        # Check rooms
        if not updated:
            for room in structured_data.rooms:
                if room.room_id == object_id:
                    for field, value in updates.items():
                        if hasattr(room, field):
                            setattr(room, field, value)
                    room.detection_metadata.user_modified = True
                    updated = True
                    break
        
        # Check staircases
        if not updated:
            for stair in structured_data.staircases:
                if stair.staircase_id == object_id:
                    for field, value in updates.items():
                        if hasattr(stair, field):
                            setattr(stair, field, value)
                    stair.detection_metadata.user_modified = True
                    updated = True
                    break
        
        if updated:
            # Log the user interaction
            log_user_interaction(
                structured_data=structured_data,
                action=user_action,
                object_id=object_id,
                details=updates
            )
        
        return updated
    
    def add_user_object(
        self,
        analysis_id: str,
        object_data: Dict[str, Any],
        object_category: str = "general"  # "general", "room", "staircase"
    ) -> Optional[str]:
        """
        Add a new user-created object to the structured data
        
        Args:
            analysis_id: ID of the analysis
            object_data: Data for the new object
            object_category: Category of object to create
        
        Returns:
            Optional[str]: ID of the created object, or None if failed
        """
        
        structured_data = self.structured_data_storage.get(analysis_id)
        if not structured_data:
            return None
        
        try:
            if object_category == "room":
                # Create new room object
                room_id = f"user_room_{int(datetime.now().timestamp())}"
                room = RoomObject(
                    room_id=room_id,
                    name=object_data.get('name', 'User Room'),
                    room_type=object_data.get('room_type', 'room'),
                    location=BaseObjectLocation(
                        floor_plan_coordinates=object_data.get('coordinates', {}),
                        relative_position=object_data.get('position', 'user_defined')
                    ),
                    detection_metadata=DetectionMetadata(
                        detection_source=DetectionSource.USER_DRAWN,
                        confidence=1.0
                    ),
                    is_mamad=object_data.get('is_mamad', False)
                )
                
                # Add size if provided
                if 'size' in object_data:
                    room.size = BaseObjectSize(**object_data['size'])
                
                structured_data.rooms.append(room)
                object_id = room_id
                
            elif object_category == "staircase":
                # Create new staircase object
                stair_id = f"user_stair_{int(datetime.now().timestamp())}"
                staircase = StaircaseObject(
                    staircase_id=stair_id,
                    name=object_data.get('name', 'User Staircase'),
                    location=BaseObjectLocation(
                        floor_plan_coordinates=object_data.get('coordinates', {}),
                        relative_position=object_data.get('position', 'user_defined')
                    ),
                    detection_metadata=DetectionMetadata(
                        detection_source=DetectionSource.USER_DRAWN,
                        confidence=1.0
                    )
                )
                
                structured_data.staircases.append(staircase)
                object_id = stair_id
                
            else:  # general object
                # Create new general object
                obj_id = f"user_obj_{int(datetime.now().timestamp())}"
                obj = GeneralObject(
                    object_id=obj_id,
                    name=object_data.get('name', 'User Object'),
                    object_type=ObjectType(object_data.get('object_type', 'other')),
                    location=BaseObjectLocation(
                        floor_plan_coordinates=object_data.get('coordinates', {}),
                        relative_position=object_data.get('position', 'user_defined')
                    ),
                    location_context=LocationContext(object_data.get('location_context', 'indoor')),
                    detection_metadata=DetectionMetadata(
                        detection_source=DetectionSource.USER_DRAWN,
                        confidence=1.0
                    )
                )
                
                # Add wall-specific data if applicable
                if obj.object_type == ObjectType.WALL:
                    obj.wall_material = WallMaterial(object_data.get('wall_material', 'other'))
                    obj.wall_thickness_cm = object_data.get('wall_thickness_cm')
                
                structured_data.general_objects.append(obj)
                object_id = obj_id
            
            # Update counts
            structured_data.total_objects_count += 1
            self._update_object_counts(structured_data)
            
            # Log the user interaction
            log_user_interaction(
                structured_data=structured_data,
                action="created",
                object_id=object_id,
                details={
                    'object_category': object_category,
                    'object_data': object_data
                }
            )
            
            return object_id
            
        except Exception as e:
            print(f"❌ Error adding user object: {e}")
            return None
    
    def delete_object(self, analysis_id: str, object_id: str) -> bool:
        """Delete an object from the structured data"""
        
        structured_data = self.structured_data_storage.get(analysis_id)
        if not structured_data:
            return False
        
        # Try to find and remove the object
        removed = False
        
        # Check general objects
        for i, obj in enumerate(structured_data.general_objects):
            if obj.object_id == object_id:
                structured_data.general_objects.pop(i)
                removed = True
                break
        
        # Check rooms
        if not removed:
            for i, room in enumerate(structured_data.rooms):
                if room.room_id == object_id:
                    structured_data.rooms.pop(i)
                    removed = True
                    break
        
        # Check staircases
        if not removed:
            for i, stair in enumerate(structured_data.staircases):
                if stair.staircase_id == object_id:
                    structured_data.staircases.pop(i)
                    removed = True
                    break
        
        if removed:
            # Update counts
            structured_data.total_objects_count -= 1
            self._update_object_counts(structured_data)
            
            # Log the user interaction
            log_user_interaction(
                structured_data=structured_data,
                action="deleted",
                object_id=object_id,
                details={}
            )
        
        return removed
    
    def get_objects_for_analysis(self, analysis_id: str) -> Optional[Dict[str, Any]]:
        """
        Get structured data formatted for safety analysis
        
        Returns data in a format suitable for safety assessment algorithms
        """
        
        structured_data = self.structured_data_storage.get(analysis_id)
        if not structured_data:
            return None
        
        # Format data for analysis
        analysis_data = {
            'analysis_id': analysis_id,
            'timestamp': structured_data.timestamp.isoformat(),
            
            # Rooms with safety-relevant data
            'rooms': [
                {
                    'id': room.room_id,
                    'name': room.name,
                    'type': room.room_type,
                    'is_mamad': room.is_mamad,
                    'area_sqm': room.size.area_square_meters if room.size else None,
                    'doors_count': room.doors_count,
                    'windows_count': room.windows_count,
                    'wall_thickness_cm': room.wall_thickness_cm,
                    'wall_material': room.wall_material.value if room.wall_material else None,
                    'has_multiple_exits': room.has_multiple_exits,
                    'accessibility_score': room.accessibility_score,
                    'emergency_egress_rating': room.emergency_egress_rating,
                    'location': room.location.dict(),
                    'detection_confidence': room.detection_metadata.confidence,
                    'user_verified': room.detection_metadata.user_verified,
                    'mamad_features': {
                        'has_blast_door': room.has_blast_door,
                        'has_air_filtration': room.has_air_filtration,
                        'has_communication_system': room.has_communication_system,
                        'has_emergency_supplies': room.has_emergency_supplies
                    } if room.is_mamad else None
                }
                for room in structured_data.rooms
            ],
            
            # Walls with material and thickness data
            'walls': [
                {
                    'id': obj.object_id,
                    'material': obj.wall_material.value if obj.wall_material else None,
                    'thickness_cm': obj.wall_thickness_cm,
                    'is_load_bearing': obj.is_load_bearing,
                    'location': obj.location.dict(),
                    'size': obj.size.dict() if obj.size else None,
                    'detection_confidence': obj.detection_metadata.confidence,
                    'parent_room_id': obj.parent_room_id
                }
                for obj in structured_data.general_objects
                if obj.object_type == ObjectType.WALL
            ],
            
            # Doors and windows for egress analysis
            'doors': [
                {
                    'id': obj.object_id,
                    'name': obj.name,
                    'location': obj.location.dict(),
                    'size': obj.size.dict() if obj.size else None,
                    'parent_room_id': obj.parent_room_id,
                    'detection_confidence': obj.detection_metadata.confidence
                }
                for obj in structured_data.general_objects
                if obj.object_type == ObjectType.DOOR
            ],
            
            'windows': [
                {
                    'id': obj.object_id,
                    'name': obj.name,
                    'location': obj.location.dict(),
                    'size': obj.size.dict() if obj.size else None,
                    'parent_room_id': obj.parent_room_id,
                    'detection_confidence': obj.detection_metadata.confidence
                }
                for obj in structured_data.general_objects
                if obj.object_type == ObjectType.WINDOW
            ],
            
            # Staircases for evacuation route analysis
            'staircases': [
                {
                    'id': stair.staircase_id,
                    'name': stair.name,
                    'location': stair.location.dict(),
                    'emergency_exit_capability': stair.emergency_exit_capability,
                    'accessibility_compliant': stair.accessibility_compliant,
                    'floor_connections': stair.floor_connections,
                    'detection_confidence': stair.detection_metadata.confidence
                }
                for stair in structured_data.staircases
            ],
            
            # House-level data
            'house_data': {
                'boundary': structured_data.house_boundary,
                'materials': structured_data.house_materials,
                'floor_plan_metadata': structured_data.floor_plan_metadata
            },
            
            # Summary statistics
            'summary': {
                'total_objects': structured_data.total_objects_count,
                'objects_by_type': structured_data.objects_by_type,
                'ai_confidence': structured_data.ai_detection_confidence,
                'user_verification_status': structured_data.user_verification_status,
                'has_mamad': any(room.is_mamad for room in structured_data.rooms),
                'mamad_count': sum(1 for room in structured_data.rooms if room.is_mamad)
            },
            
            # User interaction history
            'user_interaction_summary': {
                'total_interactions': len(structured_data.user_logs),
                'last_interaction': structured_data.user_logs[-1]['timestamp'] if structured_data.user_logs else None,
                'modification_count': sum(1 for log in structured_data.user_logs if log['action'] == 'modified'),
                'creation_count': sum(1 for log in structured_data.user_logs if log['action'] == 'created')
            }
        }
        
        return analysis_data
    
    def _extract_house_level_data(
        self, 
        structured_data: FloorPlanStructuredData, 
        user_annotations: List[Dict[str, Any]],
        ai_detections: Dict[str, Any]
    ):
        """Extract house-level data from annotations and detections"""
        
        # Look for house boundary in user annotations
        for annotation in user_annotations:
            if annotation.get('tool') == 'house_boundary':
                structured_data.house_boundary = annotation.get('points', {})
                break
        
        # Look for house materials selection
        house_materials = {}
        for annotation in user_annotations:
            if 'material' in annotation.get('tool', '').lower():
                material_name = annotation.get('material_name', '')
                percentage = annotation.get('percentage', 0.0)
                if material_name and percentage > 0:
                    house_materials[material_name] = percentage
        
        if house_materials:
            structured_data.house_materials = house_materials
        
        # Extract floor plan metadata from AI detections
        if 'image_dimensions' in ai_detections:
            structured_data.floor_plan_metadata.update({
                'image_dimensions': ai_detections['image_dimensions'],
                'processing_method': ai_detections.get('processing_method', 'unknown'),
                'analysis_summary': ai_detections.get('analysis_summary', '')
            })
    
    def _update_object_counts(self, structured_data: FloorPlanStructuredData):
        """Update object count statistics"""
        
        structured_data.objects_by_type = {
            'rooms': len(structured_data.rooms),
            'staircases': len(structured_data.staircases),
            'walls': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.WALL]),
            'doors': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.DOOR]),
            'windows': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.WINDOW]),
            'columns': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.COLUMN]),
            'other': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.OTHER])
        }

# Global service instance
structured_data_service = StructuredDataService() 