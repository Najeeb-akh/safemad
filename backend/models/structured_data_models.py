from typing import List, Dict, Any, Optional, Union
from pydantic import BaseModel, Field
from datetime import datetime
from enum import Enum

# ===== ENUMS FOR STANDARDIZATION =====

class ObjectType(str, Enum):
    # Rooms and spaces
    ROOM = "room"
    MAMAD = "mamad"
    STAIRCASE = "staircase"
    
    # Structural elements
    WALL = "wall"
    DOOR = "door"
    WINDOW = "window"
    COLUMN = "column"
    
    # Other elements
    FURNITURE = "furniture"
    FIXTURE = "fixture"
    OTHER = "other"

class LocationContext(str, Enum):
    INDOOR = "indoor"
    OUTDOOR = "outdoor"
    SEMI_OUTDOOR = "semi_outdoor"  # e.g., covered balcony

class WallMaterial(str, Enum):
    CONCRETE_BLOCKS = "concrete_blocks"
    JERUSALEM_STONE = "jerusalem_stone"
    REINFORCED_CONCRETE = "reinforced_concrete"
    RED_BRICK = "red_brick"
    THERMAL_BLOCKS = "thermal_blocks"
    NATURAL_STONE = "natural_stone"
    AERATED_CONCRETE = "aerated_concrete"
    STEEL_FRAME = "steel_frame"
    PREFAB_PANELS = "prefab_panels"
    DRYWALL = "drywall"
    OTHER = "other"

class DetectionSource(str, Enum):
    AI_YOLO = "ai_yolo"
    AI_SAM = "ai_sam"
    AI_VISION_API = "ai_vision_api"
    USER_DRAWN = "user_drawn"
    USER_ANNOTATED = "user_annotated"
    COMBINED = "combined"

# ===== BASE OBJECT STRUCTURE =====

class BaseObjectLocation(BaseModel):
    """Base location information for all objects"""
    floor_plan_coordinates: Dict[str, float] = Field(
        description="X, Y coordinates on the floor plan image"
    )
    relative_position: str = Field(
        description="Descriptive position (e.g., 'top_left', 'center', 'bottom_right')"
    )
    bounding_box: Optional[Dict[str, float]] = Field(
        None, description="x1, y1, x2, y2 coordinates of bounding box"
    )
    center_point: Optional[Dict[str, float]] = Field(
        None, description="Center coordinates of the object"
    )

class BaseObjectSize(BaseModel):
    """Base size information for objects"""
    area_pixels: Optional[float] = Field(None, description="Area in pixels")
    area_square_meters: Optional[float] = Field(None, description="Estimated area in square meters")
    width_pixels: Optional[float] = Field(None, description="Width in pixels")
    height_pixels: Optional[float] = Field(None, description="Height in pixels")
    width_meters: Optional[float] = Field(None, description="Estimated width in meters")
    height_meters: Optional[float] = Field(None, description="Estimated height in meters")
    perimeter: Optional[float] = Field(None, description="Perimeter measurement")

class DetectionMetadata(BaseModel):
    """Metadata about how the object was detected"""
    detection_source: DetectionSource
    confidence: float = Field(0.0, ge=0.0, le=1.0, description="Detection confidence score")
    detection_timestamp: datetime = Field(default_factory=datetime.now)
    ai_model_version: Optional[str] = None
    user_verified: bool = Field(False, description="Whether user has verified this detection")
    user_modified: bool = Field(False, description="Whether user has modified this detection")

# ===== SPECIFIC OBJECT TYPES =====

class GeneralObject(BaseModel):
    """For objects that are not rooms, mamad, or staircases"""
    object_id: str = Field(description="Unique identifier")
    name: str = Field(description="Object name/label")
    object_type: ObjectType
    location: BaseObjectLocation
    size: Optional[BaseObjectSize] = None
    location_context: LocationContext = LocationContext.INDOOR
    detection_metadata: DetectionMetadata
    
    # Wall-specific fields (if object_type is WALL)
    wall_material: Optional[WallMaterial] = None
    wall_thickness_cm: Optional[float] = Field(None, description="Wall thickness in centimeters")
    is_load_bearing: Optional[bool] = None
    
    # Additional properties based on user input from enhanced_detection_results_screen.dart
    user_notes: Optional[str] = None
    safety_rating: Optional[float] = Field(None, ge=0.0, le=10.0)
    
    # Relationships to other objects
    connected_objects: List[str] = Field(default_factory=list, description="IDs of connected objects")
    parent_room_id: Optional[str] = Field(None, description="ID of the room this object belongs to")

class RoomObject(BaseModel):
    """For rooms and mamad (protected rooms)"""
    room_id: str = Field(description="Unique room identifier")
    name: str = Field(description="Room name")
    room_type: str = Field(description="Type of room (living room, bedroom, etc.)")
    location: BaseObjectLocation
    size: Optional[BaseObjectSize] = None
    detection_metadata: DetectionMetadata
    
    # Wall properties from user input
    wall_thickness_cm: Optional[float] = Field(None, description="Wall thickness in centimeters")
    wall_material: Optional[WallMaterial] = None
    
    # Doors and windows count from user assessments
    doors_count: int = Field(0, description="Number of doors in the room")
    windows_count: int = Field(0, description="Number of windows in the room")
    
    # Door and window details
    doors: List[str] = Field(default_factory=list, description="IDs of door objects in this room")
    windows: List[str] = Field(default_factory=list, description="IDs of window objects in this room")
    walls: List[str] = Field(default_factory=list, description="IDs of wall objects for this room")
    
    # Location reference to floor plan
    floor_plan_reference: Dict[str, Any] = Field(
        default_factory=dict, 
        description="Reference coordinates and boundaries within the floor plan"
    )
    
    # Room-specific properties from room_safety_assessment_screen.dart
    accessibility_score: Optional[float] = Field(None, ge=0.0, le=10.0)
    has_multiple_exits: bool = Field(False)
    emergency_egress_rating: str = Field("unknown", description="poor, limited, good")
    
    # MAMAD-specific properties
    is_mamad: bool = Field(False, description="Whether this is a protected room (MAMAD)")
    has_blast_door: Optional[bool] = None
    has_air_filtration: Optional[bool] = None
    has_communication_system: Optional[bool] = None
    has_emergency_supplies: Optional[bool] = None
    
    # User assessments and measurements
    user_assessments: Dict[str, Any] = Field(default_factory=dict)
    manual_measurements: Dict[str, float] = Field(default_factory=dict)

class StaircaseObject(BaseModel):
    """For staircases and stairwells"""
    staircase_id: str = Field(description="Unique staircase identifier")
    name: str = Field(description="Staircase name/identifier")
    location: BaseObjectLocation
    size: Optional[BaseObjectSize] = None
    detection_metadata: DetectionMetadata
    
    # Staircase-specific properties
    number_of_steps: Optional[int] = None
    floor_connections: List[str] = Field(default_factory=list, description="Which floors it connects")
    stair_width_cm: Optional[float] = None
    has_handrails: Optional[bool] = None
    
    # Safety properties
    emergency_exit_capability: bool = Field(False)
    accessibility_compliant: Optional[bool] = None
    
    # Location reference to floor plan
    floor_plan_reference: Dict[str, Any] = Field(default_factory=dict)

# ===== MAIN STRUCTURE CONTAINER =====

class FloorPlanStructuredData(BaseModel):
    """Main container for all structured floor plan data"""
    
    # Identification
    analysis_id: str = Field(description="Unique analysis identifier")
    user_id: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.now)
    
    # Floor plan metadata
    floor_plan_metadata: Dict[str, Any] = Field(
        default_factory=dict,
        description="Original image dimensions, file info, etc."
    )
    
    # All detected/annotated objects organized by type
    general_objects: List[GeneralObject] = Field(default_factory=list)
    rooms: List[RoomObject] = Field(default_factory=list)
    staircases: List[StaircaseObject] = Field(default_factory=list)
    
    # Summary statistics
    total_objects_count: int = Field(0)
    objects_by_type: Dict[str, int] = Field(default_factory=dict)
    ai_detection_confidence: float = Field(0.0, description="Overall AI detection confidence")
    user_verification_status: str = Field("pending", description="pending, partial, complete")
    
    # User interaction logs
    user_logs: List[Dict[str, Any]] = Field(
        default_factory=list,
        description="Log of all user interactions, modifications, and inputs"
    )
    
    # House-level properties from enhanced_detection_results_screen.dart
    house_boundary: Optional[Dict[str, Any]] = Field(
        None, description="Overall house boundary coordinates"
    )
    house_materials: Dict[str, float] = Field(
        default_factory=dict, 
        description="House construction materials with percentages"
    )
    
    # Analysis results and insights
    safety_analysis: Optional[Dict[str, Any]] = Field(
        None, description="Safety assessment results"
    )
    structural_analysis: Optional[Dict[str, Any]] = Field(
        None, description="Structural analysis results"
    )

# ===== HELPER FUNCTIONS =====

def create_from_existing_data(
    ai_detections: Dict[str, Any],
    user_annotations: List[Dict[str, Any]],
    user_assessments: Dict[str, Any]
) -> FloorPlanStructuredData:
    """
    Convert existing unstructured data into the new structured format
    
    Args:
        ai_detections: Raw AI detection results
        user_annotations: User-drawn annotations
        user_assessments: User safety assessments and measurements
    
    Returns:
        FloorPlanStructuredData: Structured data object
    """
    
    structured_data = FloorPlanStructuredData(
        analysis_id=f"analysis_{int(datetime.now().timestamp())}"
    )
    
    # Process AI detections
    detected_rooms = ai_detections.get('detected_rooms', [])
    architectural_elements = ai_detections.get('architectural_elements', [])
    
    # Convert detected rooms
    for room_data in detected_rooms:
        room = RoomObject(
            room_id=room_data.get('room_id', f"room_{len(structured_data.rooms)}"),
            name=room_data.get('default_name', 'Unknown Room'),
            room_type=room_data.get('default_name', 'room'),
            location=BaseObjectLocation(
                floor_plan_coordinates=room_data.get('boundaries', {}).get('center', {}),
                relative_position=room_data.get('boundaries', {}).get('position', 'unknown')
            ),
            detection_metadata=DetectionMetadata(
                detection_source=DetectionSource.AI_YOLO,
                confidence=room_data.get('confidence', 0.0)
            ),
            doors_count=len(room_data.get('doors', [])),
            windows_count=len(room_data.get('windows', [])),
            floor_plan_reference=room_data.get('boundaries', {})
        )
        
        if room_data.get('estimated_dimensions'):
            room.size = BaseObjectSize(
                area_square_meters=room_data['estimated_dimensions'].get('area_sqm'),
                width_meters=room_data['estimated_dimensions'].get('width_m'),
                height_meters=room_data['estimated_dimensions'].get('length_m')
            )
        
        structured_data.rooms.append(room)
    
    # Convert architectural elements to general objects
    for element in architectural_elements:
        if element.get('type') in ['Door', 'Window', 'Wall', 'Column']:
            obj = GeneralObject(
                object_id=f"{element.get('type', 'obj').lower()}_{len(structured_data.general_objects)}",
                name=element.get('type', 'Unknown'),
                object_type=ObjectType(element.get('type', 'other').lower()),
                location=BaseObjectLocation(
                    floor_plan_coordinates=element.get('center', {}),
                    relative_position=element.get('relative_position', 'unknown'),
                    bounding_box=element.get('bbox', {})
                ),
                detection_metadata=DetectionMetadata(
                    detection_source=DetectionSource.AI_YOLO,
                    confidence=element.get('confidence', 0.0)
                )
            )
            
            if element.get('dimensions'):
                obj.size = BaseObjectSize(
                    width_pixels=element['dimensions'].get('width'),
                    height_pixels=element['dimensions'].get('height'),
                    area_pixels=element.get('area')
                )
            
            structured_data.general_objects.append(obj)
    
    # Process user annotations
    for annotation in user_annotations:
        if annotation.get('tool') in ['room', 'mamad']:
            # User-drawn room
            room_data = annotation.get('roomData', {})
            room = RoomObject(
                room_id=annotation.get('id', f"user_room_{len(structured_data.rooms)}"),
                name=room_data.get('defaultName', 'User Room'),
                room_type=annotation.get('tool', 'room'),
                location=BaseObjectLocation(
                    floor_plan_coordinates={'x': 0, 'y': 0},  # Would need to extract from points
                    relative_position='user_defined'
                ),
                detection_metadata=DetectionMetadata(
                    detection_source=DetectionSource.USER_DRAWN,
                    confidence=1.0
                ),
                is_mamad=(annotation.get('tool') == 'mamad')
            )
            structured_data.rooms.append(room)
        
        elif annotation.get('tool') == 'stairway':
            # User-drawn staircase
            staircase = StaircaseObject(
                staircase_id=annotation.get('id', f"user_stair_{len(structured_data.staircases)}"),
                name="User-drawn Staircase",
                location=BaseObjectLocation(
                    floor_plan_coordinates={'x': 0, 'y': 0},  # Would need to extract from points
                    relative_position='user_defined'
                ),
                detection_metadata=DetectionMetadata(
                    detection_source=DetectionSource.USER_DRAWN,
                    confidence=1.0
                )
            )
            structured_data.staircases.append(staircase)
        
        else:
            # General user annotation (wall, door, window, etc.)
            obj = GeneralObject(
                object_id=annotation.get('id', f"user_obj_{len(structured_data.general_objects)}"),
                name=annotation.get('tool', 'User Annotation'),
                object_type=ObjectType(annotation.get('tool', 'other')),
                location=BaseObjectLocation(
                    floor_plan_coordinates={'x': 0, 'y': 0},  # Would need to extract from points
                    relative_position='user_defined'
                ),
                detection_metadata=DetectionMetadata(
                    detection_source=DetectionSource.USER_DRAWN,
                    confidence=1.0
                )
            )
            structured_data.general_objects.append(obj)
    
    # Add user assessments to rooms
    for room_id, assessment in user_assessments.items():
        # Find corresponding room and add assessment data
        for room in structured_data.rooms:
            if room.room_id == room_id:
                room.user_assessments = assessment
                # Extract specific fields from assessment
                if 'wall_thickness' in assessment:
                    room.wall_thickness_cm = assessment['wall_thickness']
                if 'wall_material' in assessment:
                    try:
                        room.wall_material = WallMaterial(assessment['wall_material'].lower().replace(' ', '_'))
                    except ValueError:
                        room.wall_material = WallMaterial.OTHER
                break
    
    # Update summary statistics
    structured_data.total_objects_count = (
        len(structured_data.general_objects) + 
        len(structured_data.rooms) + 
        len(structured_data.staircases)
    )
    
    structured_data.objects_by_type = {
        'rooms': len(structured_data.rooms),
        'staircases': len(structured_data.staircases),
        'walls': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.WALL]),
        'doors': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.DOOR]),
        'windows': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.WINDOW]),
        'other': len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.OTHER])
    }
    
    return structured_data

def log_user_interaction(
    structured_data: FloorPlanStructuredData,
    action: str,
    object_id: str,
    details: Dict[str, Any]
):
    """
    Log user interactions with the structured data
    
    Args:
        structured_data: The main structured data object
        action: Type of action (created, modified, deleted, verified)
        object_id: ID of the affected object
        details: Additional details about the interaction
    """
    
    log_entry = {
        'timestamp': datetime.now().isoformat(),
        'action': action,
        'object_id': object_id,
        'details': details,
        'user_agent': details.get('user_agent', 'unknown')
    }
    
    structured_data.user_logs.append(log_entry) 