from fastapi import APIRouter, HTTPException, Depends
from typing import List, Dict, Any, Optional
from pydantic import BaseModel

from ..services.structured_safety_assessment_service import StructuredSafetyAssessmentService
from ..services.structured_data_service import StructuredDataService
from ..models.structured_data_models import FloorPlanStructuredData

router = APIRouter(prefix="/api/structured-safety", tags=["structured_safety"])

# Pydantic models for requests
class StructuredSafetyAssessmentRequest(BaseModel):
    analysis_id: str
    room_assessments: List[Dict[str, Any]]

class ConvertOldAssessmentRequest(BaseModel):
    old_assessment_data: Dict[str, Any]
    annotation_id: str

class StructuredHeatmapRequest(BaseModel):
    analysis_id: str

# Initialize services
structured_safety_service = StructuredSafetyAssessmentService()
structured_data_service = StructuredDataService()

@router.post("/convert-old-assessment")
async def convert_old_assessment_to_structured(request: ConvertOldAssessmentRequest):
    """
    Convert old unstructured safety assessment data to new structured format
    
    This endpoint helps migrate from the old safety assessment system to the new structured approach.
    """
    try:
        analysis_id = structured_safety_service.convert_unstructured_assessment_to_structured(
            old_assessment_data=request.old_assessment_data,
            annotation_id=request.annotation_id
        )
        
        return {
            'success': True,
            'analysis_id': analysis_id,
            'message': 'Old assessment data successfully converted to structured format'
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to convert assessment: {str(e)}")

@router.post("/submit-assessment")
async def submit_structured_safety_assessment(request: StructuredSafetyAssessmentRequest):
    """
    Submit safety assessment using structured data system
    
    This replaces the old /submit-room-safety-assessment endpoint and uses the new structured data system.
    """
    try:
        # Submit assessment using structured service
        assessment_result = structured_safety_service.submit_structured_safety_assessment(
            analysis_id=request.analysis_id,
            room_assessments=request.room_assessments
        )
        
        return {
            'success': True,
            **assessment_result
        }
        
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to process assessment: {str(e)}")

@router.get("/assessment-results/{analysis_id}")
async def get_structured_assessment_results(analysis_id: str):
    """
    Get safety assessment results for a specific analysis
    """
    try:
        assessment_result = structured_safety_service.get_safety_assessment(analysis_id)
        
        if not assessment_result:
            raise HTTPException(status_code=404, detail="Assessment results not found")
        
        return assessment_result
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to retrieve assessment: {str(e)}")

@router.get("/structured-data/{analysis_id}")
async def get_structured_data_for_analysis(analysis_id: str):
    """
    Get structured floor plan data for an analysis
    """
    try:
        structured_data = structured_data_service.get_structured_data(analysis_id)
        
        if not structured_data:
            raise HTTPException(status_code=404, detail="Structured data not found")
        
        # Convert to dict for response
        return {
            'analysis_id': structured_data.analysis_id,
            'user_id': structured_data.user_id,
            'timestamp': structured_data.timestamp.isoformat(),
            'total_objects_count': structured_data.total_objects_count,
            'objects_by_type': structured_data.objects_by_type,
            'rooms_count': len(structured_data.rooms),
            'general_objects_count': len(structured_data.general_objects),
            'staircases_count': len(structured_data.staircases),
            'has_mamad': any(room.is_mamad for room in structured_data.rooms),
            'floor_plan_metadata': structured_data.floor_plan_metadata
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to retrieve structured data: {str(e)}")

@router.post("/generate-heatmap")
async def generate_structured_heatmap(request: StructuredHeatmapRequest):
    """
    Generate heatmap using structured data
    
    This replaces the old /generate-explosive-risk-heatmap endpoint and uses structured data.
    """
    try:
        print(f"[STRUCTURED_HEATMAP_DEBUG] Generating heatmap for analysis_id: {request.analysis_id}")
        
        # Get structured data formatted for heatmap
        heatmap_data = await structured_safety_service.get_assessment_for_heatmap(request.analysis_id)
        print(f"[STRUCTURED_HEATMAP_DEBUG] Retrieved heatmap data: {type(heatmap_data)}")
        
        # Import the heatmap service
        from ..services.explosive_risk_heatmap_service import ExplosiveRiskHeatmapService
        heatmap_service = ExplosiveRiskHeatmapService()
        
        # Generate heatmap using structured data
        print(f"[STRUCTURED_HEATMAP_DEBUG] Calling generate_heatmap with analysis_id")
        heatmap_result = await heatmap_service.generate_heatmap(heatmap_data, request.analysis_id)
        print(f"[STRUCTURED_HEATMAP_DEBUG] Heatmap generation successful")
        
        return {
            'success': True,
            'heatmap_data': heatmap_result,
            'analysis_id': request.analysis_id,
            'message': 'Heatmap generated successfully using structured data'
        }
        
    except ValueError as e:
        print(f"[STRUCTURED_HEATMAP_DEBUG] ValueError: {e}")
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        print(f"[STRUCTURED_HEATMAP_DEBUG] Exception: {e}")
        import traceback
        print(f"[STRUCTURED_HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Heatmap generation failed: {str(e)}")

@router.get("/room-analysis/{analysis_id}")
async def get_structured_room_analysis(analysis_id: str):
    """
    Get detailed room analysis using structured data
    
    This replaces the old /room-safety-analysis endpoint.
    """
    try:
        structured_data = structured_data_service.get_structured_data(analysis_id)
        
        if not structured_data:
            raise HTTPException(status_code=404, detail="Structured data not found")
        
        # Build room analysis from structured data
        room_analysis = []
        for room in structured_data.rooms:
            analysis = {
                'room_id': room.room_id,
                'name': room.name,
                'type': room.room_type,
                'is_mamad': room.is_mamad,
                'wall_material': room.wall_material.value if room.wall_material else None,
                'wall_thickness_cm': room.wall_thickness_cm,
                'doors_count': room.doors_count,
                'windows_count': room.windows_count,
                'has_multiple_exits': room.has_multiple_exits,
                'emergency_egress_rating': room.emergency_egress_rating,
                'accessibility_score': room.accessibility_score,
                'area_m2': room.size.area_m2 if room.size else None,
                'detection_source': room.detection_metadata.detection_source.value,
                'user_modified': room.detection_metadata.user_modified,
                'mamad_features': {
                    'has_air_filtration': room.has_air_filtration,
                    'has_blast_door': room.has_blast_door,
                    'has_communication_system': room.has_communication_system,
                    'has_emergency_supplies': room.has_emergency_supplies
                } if room.is_mamad else None
            }
            room_analysis.append(analysis)
        
        return {
            'analysis_id': analysis_id,
            'total_rooms': len(structured_data.rooms),
            'room_analysis': room_analysis,
            'structured_data_summary': {
                'total_objects': structured_data.total_objects_count,
                'objects_by_type': structured_data.objects_by_type,
                'user_interactions': len(structured_data.user_interaction_log)
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to analyze rooms: {str(e)}")

@router.put("/update-room/{analysis_id}/{room_id}")
async def update_room_in_structured_data(
    analysis_id: str,
    room_id: str,
    updates: Dict[str, Any]
):
    """
    Update a specific room in the structured data
    """
    try:
        success = structured_data_service.update_object(
            analysis_id=analysis_id,
            object_id=room_id,
            updates=updates,
            user_action="room_update"
        )
        
        if not success:
            raise HTTPException(status_code=404, detail="Room not found or update failed")
        
        return {
            'success': True,
            'message': f'Room {room_id} updated successfully'
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update room: {str(e)}")

@router.get("/user-analyses/{user_id}")
async def get_user_analyses(user_id: str):
    """
    Get all analyses for a specific user
    """
    try:
        analyses = structured_data_service.list_user_analyses(user_id)
        
        return {
            'user_id': user_id,
            'analyses_count': len(analyses),
            'analyses': analyses
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to retrieve user analyses: {str(e)}")

# Compatibility endpoints for gradual migration
@router.post("/submit-room-safety-assessment")
async def submit_room_safety_assessment_compatibility(assessment_data: Dict[str, Any]):
    """
    Compatibility endpoint for old safety assessment format
    
    This automatically converts old format to structured format and processes it.
    This allows gradual migration without breaking existing clients.
    """
    try:
        annotation_id = assessment_data.get('annotation_id', f'compat_{hash(str(assessment_data))}')
        
        # Convert old format to structured
        analysis_id = structured_safety_service.convert_unstructured_assessment_to_structured(
            old_assessment_data=assessment_data,
            annotation_id=annotation_id
        )
        
        # Process the assessment
        room_safety_data = assessment_data.get('room_safety_data', [])
        assessment_result = structured_safety_service.submit_structured_safety_assessment(
            analysis_id=analysis_id,
            room_assessments=room_safety_data
        )
        
        # Return in old format for compatibility
        return {
            'annotation_id': annotation_id,
            'analysis_id': analysis_id,  # Add new field for future use
            'room_scores': assessment_result['room_scores'],
            'safest_room': assessment_result['safest_room'],
            'recommendations': assessment_result['recommendations'],
            'overall_assessment': assessment_result['overall_assessment']
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to process assessment: {str(e)}")

@router.post("/generate-explosive-risk-heatmap")
async def generate_explosive_risk_heatmap_compatibility(request_data: Dict[str, Any]):
    """
    Compatibility endpoint for old heatmap generation
    
    This converts old format requests to structured format automatically.
    """
    try:
        print(f"[COMPAT_HEATMAP_DEBUG] Compatibility heatmap generation called")
        print(f"[COMPAT_HEATMAP_DEBUG] Request data keys: {list(request_data.keys())}")
        
        # Try to extract analysis_id if provided
        analysis_id = request_data.get('analysis_id')
        print(f"[COMPAT_HEATMAP_DEBUG] analysis_id: {analysis_id}")
        
        if analysis_id:
            # Use structured approach
            print(f"[COMPAT_HEATMAP_DEBUG] Using structured approach")
            heatmap_data = await structured_safety_service.get_assessment_for_heatmap(analysis_id)
        else:
            # Use old format data directly
            print(f"[COMPAT_HEATMAP_DEBUG] Using old format data directly")
            heatmap_data = request_data
        
        # Import and use heatmap service
        from ..services.explosive_risk_heatmap_service import ExplosiveRiskHeatmapService
        heatmap_service = ExplosiveRiskHeatmapService()
        
        print(f"[COMPAT_HEATMAP_DEBUG] Calling heatmap service")
        heatmap_result = await heatmap_service.generate_heatmap(heatmap_data, analysis_id)
        print(f"[COMPAT_HEATMAP_DEBUG] Heatmap generation successful")
        
        return {
            'success': True,
            'heatmap_data': heatmap_result,
            'message': 'Heatmap generated successfully',
            'used_structured_data': analysis_id is not None
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Heatmap generation failed: {str(e)}") 