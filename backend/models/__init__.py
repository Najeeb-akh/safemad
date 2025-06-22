# Models package for SafeMad backend
# This file makes the models directory a proper Python package

# Import structured data models
from .structured_data_models import (
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

__all__ = [
    'FloorPlanStructuredData',
    'GeneralObject', 
    'RoomObject',
    'StaircaseObject',
    'ObjectType',
    'LocationContext',
    'WallMaterial',
    'DetectionSource',
    'BaseObjectLocation',
    'BaseObjectSize',
    'DetectionMetadata',
    'create_from_existing_data',
    'log_user_interaction'
] 