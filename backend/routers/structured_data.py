from fastapi import APIRouter, HTTPException, Depends, Body
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from datetime import datetime

from ..services.structured_data_service import structured_data_service
from ..models import (
    FloorPlanStructuredData,
    GeneralObject,
    RoomObject,
    StaircaseObject,
    ObjectType,
    LocationContext,
    WallMaterial,
    DetectionSource
)

router = APIRouter()

# ===== REQUEST/RESPONSE MODELS =====

class ConvertDataRequest(BaseModel):
    """Request model for converting unstructured data to structured format"""
    ai_detections: Dict[str, Any]
    user_annotations: List[Dict[str, Any]]
    user_assessments: Dict[str, Any]
    user_id: Optional[str] = None
    floor_plan_metadata: Optional[Dict[str, Any]] = None

class ConvertDataResponse(BaseModel):
    """Response model for data conversion"""
    success: bool
    analysis_id: str
    message: str
    summary: Dict[str, Any]

class UpdateObjectRequest(BaseModel):
    """Request model for updating an object"""
    object_id: str
    updates: Dict[str, Any]
    user_action: str = "modified"

class AddObjectRequest(BaseModel):
    """Request model for adding a new object"""
    object_data: Dict[str, Any]
    object_category: str = "general"  # "general", "room", "staircase"

class AnalysisListResponse(BaseModel):
    """Response model for listing analyses"""
    analyses: List[Dict[str, Any]]
    total_count: int

# ===== API ENDPOINTS =====

@router.post("/convert-and-store", response_model=ConvertDataResponse)
async def convert_and_store_data(request: ConvertDataRequest):
    """
    Convert unstructured detection data to structured format and store it
    
    This endpoint takes raw AI detections, user annotations, and user assessments
    and converts them into a well-organized structured format for analysis.
    """
    try:
        # Convert and store the data
        analysis_id = structured_data_service.convert_and_store_data(
            ai_detections=request.ai_detections,
            user_annotations=request.user_annotations,
            user_assessments=request.user_assessments,
            user_id=request.user_id,
            floor_plan_metadata=request.floor_plan_metadata
        )
        
        # Get metadata for response
        metadata = structured_data_service.get_analysis_metadata(analysis_id)
        
        return ConvertDataResponse(
            success=True,
            analysis_id=analysis_id,
            message=f"Successfully converted and stored structured data",
            summary=metadata or {}
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to convert and store data: {str(e)}"
        )

@router.get("/analysis/{analysis_id}")
async def get_structured_data(analysis_id: str):
    """
    Get structured data by analysis ID
    
    Returns the complete structured data for a specific analysis.
    """
    try:
        structured_data = structured_data_service.get_structured_data(analysis_id)
        
        if not structured_data:
            raise HTTPException(
                status_code=404,
                detail=f"Analysis {analysis_id} not found"
            )
        
        return {
            "success": True,
            "analysis_id": analysis_id,
            "data": structured_data.dict()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve structured data: {str(e)}"
        )

@router.get("/analysis/{analysis_id}/for-safety-analysis")
async def get_data_for_analysis(analysis_id: str):
    """
    Get structured data formatted specifically for safety analysis
    
    Returns data in a format optimized for safety assessment algorithms.
    """
    try:
        analysis_data = structured_data_service.get_objects_for_analysis(analysis_id)
        
        if not analysis_data:
            raise HTTPException(
                status_code=404,
                detail=f"Analysis {analysis_id} not found"
            )
        
        return {
            "success": True,
            "analysis_data": analysis_data
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve analysis data: {str(e)}"
        )

@router.get("/user/{user_id}/analyses", response_model=AnalysisListResponse)
async def list_user_analyses(user_id: str):
    """
    List all analyses for a specific user
    """
    try:
        analyses = structured_data_service.list_user_analyses(user_id)
        
        return AnalysisListResponse(
            analyses=analyses,
            total_count=len(analyses)
        )
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to list user analyses: {str(e)}"
        )

@router.put("/analysis/{analysis_id}/object")
async def update_object(analysis_id: str, request: UpdateObjectRequest):
    """
    Update a specific object in the structured data
    
    Allows updating object properties while maintaining audit trail.
    """
    try:
        success = structured_data_service.update_object(
            analysis_id=analysis_id,
            object_id=request.object_id,
            updates=request.updates,
            user_action=request.user_action
        )
        
        if not success:
            raise HTTPException(
                status_code=404,
                detail=f"Analysis {analysis_id} or object {request.object_id} not found"
            )
        
        return {
            "success": True,
            "message": f"Object {request.object_id} updated successfully"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to update object: {str(e)}"
        )

@router.post("/analysis/{analysis_id}/object")
async def add_user_object(analysis_id: str, request: AddObjectRequest):
    """
    Add a new user-created object to the structured data
    """
    try:
        object_id = structured_data_service.add_user_object(
            analysis_id=analysis_id,
            object_data=request.object_data,
            object_category=request.object_category
        )
        
        if not object_id:
            raise HTTPException(
                status_code=400,
                detail=f"Failed to create object in analysis {analysis_id}"
            )
        
        return {
            "success": True,
            "object_id": object_id,
            "message": f"Object created successfully"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to add object: {str(e)}"
        )

@router.delete("/analysis/{analysis_id}/object/{object_id}")
async def delete_object(analysis_id: str, object_id: str):
    """
    Delete an object from the structured data
    """
    try:
        success = structured_data_service.delete_object(analysis_id, object_id)
        
        if not success:
            raise HTTPException(
                status_code=404,
                detail=f"Analysis {analysis_id} or object {object_id} not found"
            )
        
        return {
            "success": True,
            "message": f"Object {object_id} deleted successfully"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to delete object: {str(e)}"
        )

@router.get("/analysis/{analysis_id}/metadata")
async def get_analysis_metadata(analysis_id: str):
    """
    Get metadata for a specific analysis
    """
    try:
        metadata = structured_data_service.get_analysis_metadata(analysis_id)
        
        if not metadata:
            raise HTTPException(
                status_code=404,
                detail=f"Analysis {analysis_id} not found"
            )
        
        return {
            "success": True,
            "metadata": metadata
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve metadata: {str(e)}"
        )

@router.get("/analysis/{analysis_id}/summary")
async def get_analysis_summary(analysis_id: str):
    """
    Get a summary of the structured data for an analysis
    
    Returns key statistics and insights about the detected objects.
    """
    try:
        structured_data = structured_data_service.get_structured_data(analysis_id)
        
        if not structured_data:
            raise HTTPException(
                status_code=404,
                detail=f"Analysis {analysis_id} not found"
            )
        
        # Create comprehensive summary
        rooms_summary = []
        for room in structured_data.rooms:
            room_summary = {
                "id": room.room_id,
                "name": room.name,
                "type": room.room_type,
                "is_mamad": room.is_mamad,
                "doors_count": room.doors_count,
                "windows_count": room.windows_count,
                "wall_thickness_cm": room.wall_thickness_cm,
                "wall_material": room.wall_material.value if room.wall_material else None,
                "area_sqm": room.size.area_square_meters if room.size else None,
                "detection_source": room.detection_metadata.detection_source.value,
                "confidence": room.detection_metadata.confidence,
                "user_verified": room.detection_metadata.user_verified
            }
            rooms_summary.append(room_summary)
        
        # Walls summary
        walls_summary = []
        for obj in structured_data.general_objects:
            if obj.object_type == ObjectType.WALL:
                wall_summary = {
                    "id": obj.object_id,
                    "material": obj.wall_material.value if obj.wall_material else None,
                    "thickness_cm": obj.wall_thickness_cm,
                    "is_load_bearing": obj.is_load_bearing,
                    "location_context": obj.location_context.value,
                    "detection_source": obj.detection_metadata.detection_source.value,
                    "confidence": obj.detection_metadata.confidence
                }
                walls_summary.append(wall_summary)
        
        # Safety features summary
        safety_summary = {
            "total_mamad_rooms": sum(1 for room in structured_data.rooms if room.is_mamad),
            "rooms_with_multiple_exits": sum(1 for room in structured_data.rooms if room.has_multiple_exits),
            "total_emergency_exits": len([obj for obj in structured_data.general_objects if obj.object_type == ObjectType.DOOR]),
            "emergency_staircases": len([stair for stair in structured_data.staircases if stair.emergency_exit_capability]),
            "wall_materials_used": list(set([
                obj.wall_material.value for obj in structured_data.general_objects 
                if obj.object_type == ObjectType.WALL and obj.wall_material
            ])),
            "house_materials": structured_data.house_materials
        }
        
        summary = {
            "analysis_id": analysis_id,
            "timestamp": structured_data.timestamp.isoformat(),
            "total_objects": structured_data.total_objects_count,
            "objects_by_type": structured_data.objects_by_type,
            "rooms": rooms_summary,
            "walls": walls_summary,
            "safety_features": safety_summary,
            "user_interaction_stats": {
                "total_logs": len(structured_data.user_logs),
                "last_interaction": structured_data.user_logs[-1]['timestamp'] if structured_data.user_logs else None,
                "user_verification_status": structured_data.user_verification_status
            },
            "ai_detection_confidence": structured_data.ai_detection_confidence
        }
        
        return {
            "success": True,
            "summary": summary
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate summary: {str(e)}"
        )

# ===== HELPER ENDPOINTS =====

@router.get("/enums/object-types")
async def get_object_types():
    """Get available object types"""
    return {
        "object_types": [obj_type.value for obj_type in ObjectType]
    }

@router.get("/enums/wall-materials")
async def get_wall_materials():
    """Get available wall materials"""
    return {
        "wall_materials": [material.value for material in WallMaterial]
    }

@router.get("/enums/detection-sources")
async def get_detection_sources():
    """Get available detection sources"""
    return {
        "detection_sources": [source.value for source in DetectionSource]
    }

@router.get("/enums/location-contexts")
async def get_location_contexts():
    """Get available location contexts"""
    return {
        "location_contexts": [context.value for context in LocationContext]
    } 