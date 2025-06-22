from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from ..services.annotation_service import annotation_service
from ..services.explosive_risk_heatmap_service import ExplosiveRiskHeatmapService
from ..auth import get_current_user
import json

router = APIRouter()

class FloorPlanAnnotation(BaseModel):
    rooms: Optional[List[Dict[str, Any]]] = []
    annotations: Optional[List[Dict[str, Any]]] = []  # Drawing annotations
    imageSize: Optional[Dict[str, float]] = {}
    image_dimensions: Optional[Dict[str, float]] = {}
    display_dimensions: Optional[Dict[str, float]] = {}
    metadata: Optional[Dict[str, Any]] = {}

class AnnotationResponse(BaseModel):
    success: bool
    annotation_id: str
    message: str
    summary: Dict[str, Any]

class RoomSafetyAssessment(BaseModel):
    annotation_id: str
    room_safety_data: List[Dict[str, Any]]

class ExplosiveRiskHeatmapRequest(BaseModel):
    house_boundaries: Dict[str, Any]
    rooms: List[Dict[str, Any]]
    external_walls: List[Dict[str, Any]]
    windows: List[Dict[str, Any]]
    doors: List[Dict[str, Any]]
    safety_assessments: List[Dict[str, Any]]
    staircases: Optional[List[Dict[str, Any]]] = []

@router.post("/save-floor-plan-annotations", response_model=AnnotationResponse)
async def save_floor_plan_annotations(
    annotation: FloorPlanAnnotation
):
    """
    Save user-annotated floor plan data
    """
    try:
        # Use anonymous user ID since auth is disabled
        user_id = "anonymous"
        
        result = annotation_service.save_annotations(
            user_id=user_id,
            annotations=annotation.dict()
        )
        
        return AnnotationResponse(**result)
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save annotations: {str(e)}")

@router.get("/annotations/{annotation_id}")
async def get_annotation(
    annotation_id: str,
    current_user: Optional[Dict] = Depends(get_current_user)
):
    """
    Retrieve a specific floor plan annotation
    """
    try:
        annotation = annotation_service.get_annotations(annotation_id)
        
        if "error" in annotation:
            raise HTTPException(status_code=404, detail="Annotation not found")
        
        return annotation
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to retrieve annotation: {str(e)}")

@router.get("/user-annotations")
async def get_user_annotations(
    current_user: Optional[Dict] = Depends(get_current_user)
):
    """
    Get all annotations for the current user
    """
    try:
        user_id = current_user.get("user_id", "anonymous") if current_user else "anonymous"
        annotations = annotation_service.get_user_annotations(user_id)
        
        return {
            "user_id": user_id,
            "annotations": annotations,
            "count": len(annotations)
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to retrieve user annotations: {str(e)}")

@router.get("/safety-report/{annotation_id}")
async def generate_safety_report(
    annotation_id: str,
    current_user: Optional[Dict] = Depends(get_current_user)
):
    """
    Generate a comprehensive safety report based on annotated floor plan
    """
    try:
        report = annotation_service.generate_safety_report(annotation_id)
        
        if "error" in report:
            raise HTTPException(status_code=404, detail="Annotation not found")
        
        return report
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate safety report: {str(e)}")

@router.get("/room-safety-analysis/{annotation_id}")
async def get_room_safety_analysis(
    annotation_id: str,
    current_user: Optional[Dict] = Depends(get_current_user)
):
    """
    Get detailed safety analysis for each room
    """
    try:
        annotation = annotation_service.get_annotations(annotation_id)
        
        if "error" in annotation:
            raise HTTPException(status_code=404, detail="Annotation not found")
        
        rooms = annotation.get("rooms", [])
        
        analysis = {
            "annotation_id": annotation_id,
            "total_rooms": len(rooms),
            "room_analysis": []
        }
        
        for room in rooms:
            room_analysis = {
                "room_id": room.get("id"),
                "name": room.get("name"),
                "type": room.get("type"),
                "area": room.get("area"),
                "safety_features": room.get("safety_features"),
                "risk_level": _calculate_room_risk_level(room)
            }
            analysis["room_analysis"].append(room_analysis)
        
        return analysis
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to analyze room safety: {str(e)}")

def _calculate_room_risk_level(room: Dict[str, Any]) -> str:
    """
    Calculate risk level for a room based on type and safety features
    """
    room_type = room.get("type", "").lower()
    safety_features = room.get("safety_features", {})
    fire_rating = safety_features.get("fire_safety_rating", "medium")
    
    # Very high-risk rooms
    if "staircase" in room_type:
        return "critical"
    
    # High-risk rooms
    if "kitchen" in room_type or "garage" in room_type:
        return "high"
    
    # Medium-risk rooms
    if "bedroom" in room_type or "living" in room_type:
        if fire_rating == "high":
            return "medium"
        else:
            return "high"
    
    # Special secure rooms (Mamad)
    if "mamad" in room_type:
        return "low"  # Mamad is designed for safety
    
    # Lower-risk rooms
    if "bathroom" in room_type or "storage" in room_type:
        return "low"
    
    return "medium"

@router.get("/emergency-plan/{annotation_id}")
async def get_emergency_plan(
    annotation_id: str,
    current_user: Optional[Dict] = Depends(get_current_user)
):
    """
    Get customized emergency evacuation plan
    """
    try:
        report = annotation_service.generate_safety_report(annotation_id)
        
        if "error" in report:
            raise HTTPException(status_code=404, detail="Annotation not found")
        
        return {
            "annotation_id": annotation_id,
            "emergency_plan": report.get("emergency_plan", {}),
            "safety_score": report.get("summary", {}).get("overall_safety_score", 0),
            "critical_recommendations": _get_critical_recommendations(report)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate emergency plan: {str(e)}")

def _get_critical_recommendations(report: Dict[str, Any]) -> List[str]:
    """
    Extract critical safety recommendations from the report
    """
    recommendations = report.get("recommendations", [])
    critical = []
    
    for rec in recommendations:
        if any(keyword in rec.lower() for keyword in ["smoke detector", "fire extinguisher", "emergency", "evacuation"]):
            critical.append(rec)
    
    return critical[:5]  # Return top 5 critical recommendations

@router.post("/submit-room-safety-assessment")
async def submit_room_safety_assessment(
    assessment: RoomSafetyAssessment
):
    """
    Submit room safety assessment and calculate safety scores
    
    DEPRECATED: This endpoint is deprecated. Use /api/structured-safety/submit-assessment instead.
    This endpoint now automatically converts to structured format for backward compatibility.
    """
    try:
        print("⚠️ WARNING: Using deprecated endpoint /submit-room-safety-assessment")
        print("   Please migrate to /api/structured-safety/submit-assessment")
        
        # Import the new structured service
        from ..services.structured_safety_assessment_service import StructuredSafetyAssessmentService
        structured_safety_service = StructuredSafetyAssessmentService()
        
        # Convert old format to structured format
        assessment_data = {
            'annotation_id': assessment.annotation_id,
            'room_safety_data': [room.dict() if hasattr(room, 'dict') else room for room in assessment.room_safety_data]
        }
        
        # Convert to structured format
        analysis_id = structured_safety_service.convert_unstructured_assessment_to_structured(
            old_assessment_data=assessment_data,
            annotation_id=assessment.annotation_id
        )
        
        # Process using structured approach
        room_assessments = assessment_data['room_safety_data']
        assessment_result = structured_safety_service.submit_structured_safety_assessment(
            analysis_id=analysis_id,
            room_assessments=room_assessments
        )
        
        # Return in old format for compatibility
        result = {
            'annotation_id': assessment.annotation_id,
            'analysis_id': analysis_id,  # Add new field
            'room_scores': assessment_result['room_scores'],
            'safest_room': assessment_result['safest_room'],
            'recommendations': assessment_result['recommendations'],
            'overall_assessment': assessment_result['overall_assessment'],
            '_migration_info': {
                'converted_to_structured': True,
                'new_endpoint': '/api/structured-safety/submit-assessment',
                'analysis_id': analysis_id
            }
        }
        
        return result
        
    except Exception as e:
        print(f"❌ Error in deprecated endpoint: {str(e)}")
        # Fallback to old implementation if structured conversion fails
        try:
            # Calculate safety scores for each room
            room_scores = []
            for room_data in assessment.room_safety_data:
                score = _calculate_room_safety_score(room_data)
                room_scores.append({
                    'room_id': room_data['room_id'],
                    'room_name': room_data['room_name'],
                    'room_type': room_data['room_type'],
                    'safety_score': score['total_score'],
                    'score_breakdown': score['breakdown'],
                    'safety_rating': score['rating'],
                    'responses': room_data['responses']
                })
            
            # Find the safest room
            safest_room = max(room_scores, key=lambda x: x['safety_score'])
            
            # Generate recommendations
            recommendations = _generate_safety_recommendations(room_scores, safest_room)
            
            result = {
                'annotation_id': assessment.annotation_id,
                'room_scores': room_scores,
                'safest_room': safest_room,
                'recommendations': recommendations,
                'overall_assessment': _generate_overall_assessment(room_scores),
                '_fallback_used': True
            }
            
            return result
        except Exception as fallback_error:
            raise HTTPException(status_code=500, detail=f"Failed to process assessment: {str(fallback_error)}")

def _calculate_room_safety_score(room_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calculate comprehensive safety score for a room based on responses
    """
    responses = room_data.get('responses', {})
    room_type = room_data.get('room_type', '').lower()
    
    # Base scoring weights
    score_weights = {
        'structural': 0.35,      # Wall material, thickness, structural integrity
        'safety_features': 0.25, # Smoke detectors, fire extinguishers, etc.
        'accessibility': 0.20,   # Multiple exits, clear pathways
        'environmental': 0.10,   # Ventilation, lighting, ceiling height
        'room_specific': 0.10    # Room-type specific factors
    }
    
    scores = {}
    
    # Structural Safety Score (0-100)
    structural_score = 0
    wall_material = responses.get('wall_material', 'Unknown')
    wall_thickness = responses.get('wall_thickness', 'Unknown')
    
    # Wall material scoring
    material_scores = {
        'Concrete': 100, 'Steel': 95, 'Brick': 85, 
        'Drywall': 60, 'Wood': 50, 'Unknown': 30
    }
    structural_score += material_scores.get(wall_material, 30) * 0.6
    
    # Wall thickness scoring
    thickness_scores = {
        'Very Thick (>30cm)': 100, 'Thick (20-30cm)': 80,
        'Medium (10-20cm)': 60, 'Thin (<10cm)': 40, 'Unknown': 30
    }
    structural_score += thickness_scores.get(wall_thickness, 30) * 0.4
    
    scores['structural'] = min(100, structural_score)
    
    # Safety Features Score (0-100)
    safety_features_score = 50  # Base score
    
    if responses.get('smoke_detector') == 'yes':
        safety_features_score += 25
    if responses.get('fire_extinguisher') == 'yes':
        safety_features_score += 20
    if responses.get('emergency_lighting') == 'yes':
        safety_features_score += 15
    if responses.get('communication_device') == 'yes':
        safety_features_score += 20
    if responses.get('air_filtration') == 'yes':
        safety_features_score += 30
    
    # Deduct for hazards
    if responses.get('gas_lines') == 'yes':
        safety_features_score -= 15
        
    scores['safety_features'] = max(0, min(100, safety_features_score))
    
    # Accessibility Score (0-100)
    accessibility_score = 40  # Base score
    
    if responses.get('multiple_exits') == 'yes':
        accessibility_score += 30
    if responses.get('clear_pathways') == 'yes':
        accessibility_score += 25
    if responses.get('window_escape') == 'yes':
        accessibility_score += 20
    if responses.get('handrails') == 'yes':
        accessibility_score += 10
        
    scores['accessibility'] = min(100, accessibility_score)
    
    # Environmental Score (0-100)
    environmental_score = 50  # Base score
    
    if responses.get('ventilation') == 'yes':
        environmental_score += 20
    if responses.get('water_access') == 'yes':
        environmental_score += 15
    
    ceiling_height = responses.get('ceiling_height', 'Unknown')
    height_scores = {'High (>3m)': 20, 'Normal (2.5-3m)': 15, 'Low (<2.5m)': 5, 'Unknown': 10}
    environmental_score += height_scores.get(ceiling_height, 10)
    
    windows_count = responses.get('windows_count', 'Unknown')
    window_scores = {'None': 5, '1': 10, '2': 15, '3': 18, '4+': 20, 'Unknown': 10}
    environmental_score += window_scores.get(windows_count, 10)
    
    scores['environmental'] = min(100, environmental_score)
    
    # Room-Specific Score (0-100)
    room_specific_score = _calculate_room_specific_score(room_type, responses)
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
        'total_score': round(total_score, 1),
        'rating': rating,
        'breakdown': {
            'structural': round(scores['structural'], 1),
            'safety_features': round(scores['safety_features'], 1),
            'accessibility': round(scores['accessibility'], 1),
            'environmental': round(scores['environmental'], 1),
            'room_specific': round(scores['room_specific'], 1)
        }
    }

def _calculate_room_specific_score(room_type: str, responses: Dict[str, Any]) -> float:
    """
    Calculate room-type specific safety score
    """
    score = 50  # Base score
    
    if 'mamad' in room_type:
        # Mamad gets bonus for being designed for safety
        score = 80
        if responses.get('air_filtration') == 'yes':
            score += 10
        if responses.get('communication_device') == 'yes':
            score += 10
        if responses.get('emergency_supplies') == 'yes':
            score += 5
            
    elif 'kitchen' in room_type:
        # Kitchen has inherent risks
        score = 30
        if responses.get('fire_extinguisher') == 'yes':
            score += 25
        if responses.get('gas_lines') == 'no':
            score += 20
        else:
            score -= 10
            
    elif 'bedroom' in room_type:
        score = 60
        if responses.get('smoke_detector') == 'yes':
            score += 20
        if responses.get('window_escape') == 'yes':
            score += 15
            
    elif 'bathroom' in room_type:
        score = 55
        if responses.get('water_access') == 'yes':
            score += 20
        if responses.get('ventilation') == 'yes':
            score += 15
            
    elif 'balcony' in room_type:
        score = 40  # Outdoor areas have weather risks
        if responses.get('weather_protection') == 'yes':
            score += 15
        if responses.get('structural_integrity') == 'yes':
            score += 20
        else:
            score -= 20
            
    elif 'staircase' in room_type:
        score = 20  # Staircases are not good shelter locations
        if responses.get('emergency_lighting') == 'yes':
            score += 15
        if responses.get('handrails') == 'yes':
            score += 10
    
    return max(0, min(100, score))

def _generate_safety_recommendations(room_scores: List[Dict], safest_room: Dict) -> List[str]:
    """
    Generate safety recommendations based on assessment
    """
    recommendations = []
    
    # Safest room recommendation
    recommendations.append(
        f"🏆 SAFEST ROOM: {safest_room['room_name']} ({safest_room['room_type']}) "
        f"with safety score of {safest_room['safety_score']}/100"
    )
    
    # General improvements
    for room in room_scores:
        responses = room.get('responses', {})
        room_name = room['room_name']
        
        if responses.get('smoke_detector') == 'no':
            recommendations.append(f"🚨 Install smoke detector in {room_name}")
            
        if responses.get('fire_extinguisher') == 'no' and 'kitchen' in room['room_type'].lower():
            recommendations.append(f"🧯 Add fire extinguisher near {room_name}")
            
        if responses.get('clear_pathways') == 'no':
            recommendations.append(f"🚪 Clear pathways in {room_name}")
            
        if responses.get('multiple_exits') == 'no':
            recommendations.append(f"🚪 Consider additional exit routes for {room_name}")
    
    # Specific recommendations based on safest room type
    safest_type = safest_room['room_type'].lower()
    if 'mamad' in safest_type:
        recommendations.append("✅ Excellent choice! Mamad rooms are specifically designed for safety")
        recommendations.append("🔧 Regularly check air filtration and sealing systems")
    elif 'bedroom' in safest_type:
        recommendations.append("🛏️ Good choice! Ensure clear path to exits and emergency supplies nearby")
    elif 'bathroom' in safest_type:
        recommendations.append("🚿 Decent option due to water access, but ensure adequate ventilation")
    
    return recommendations[:10]  # Limit to top 10 recommendations

def _generate_overall_assessment(room_scores: List[Dict]) -> Dict[str, Any]:
    """
    Generate overall home safety assessment
    """
    avg_score = sum(room['safety_score'] for room in room_scores) / len(room_scores)
    
    high_score_rooms = [room for room in room_scores if room['safety_score'] >= 70]
    low_score_rooms = [room for room in room_scores if room['safety_score'] < 50]
    
    assessment = {
        'average_safety_score': round(avg_score, 1),
        'total_rooms_assessed': len(room_scores),
        'high_safety_rooms': len(high_score_rooms),
        'rooms_needing_improvement': len(low_score_rooms),
        'overall_rating': 'Excellent' if avg_score >= 80 else 
                         'Good' if avg_score >= 65 else 
                         'Fair' if avg_score >= 50 else 'Needs Improvement'
    }
    
    return assessment 

@router.post("/generate-explosive-risk-heatmap")
async def generate_explosive_risk_heatmap(
    request: ExplosiveRiskHeatmapRequest
):
    """
    Generate explosive risk heatmap for floor plan with safety grid visualization
    
    DEPRECATED: This endpoint is deprecated. Use /api/structured-safety/generate-heatmap instead.
    This endpoint now automatically converts to structured format when possible.
    """
    try:
        print("⚠️ WARNING: Using deprecated endpoint /generate-explosive-risk-heatmap")
        print("   Please migrate to /api/structured-safety/generate-heatmap")
        print(f"[DEBUG] Incoming request: {request}")
        
        # Initialize heatmap service
        heatmap_service = ExplosiveRiskHeatmapService()
        
        # Prepare floor plan data
        floor_plan_data = {
            'house_boundaries': request.house_boundaries,
            'rooms': request.rooms,
            'external_walls': request.external_walls,
            'windows': request.windows,
            'doors': request.doors,
            'safety_assessments': request.safety_assessments,
            'staircases': request.staircases
        }
        print(f"[DEBUG] Constructed floor_plan_data: {json.dumps(floor_plan_data, default=str)[:1000]}...")
        
        # Try to use structured approach if analysis_id is available
        analysis_id = floor_plan_data.get('analysis_id')
        if analysis_id:
            try:
                from ..services.structured_safety_assessment_service import StructuredSafetyAssessmentService
                structured_safety_service = StructuredSafetyAssessmentService()
                
                # Get structured data for heatmap
                structured_heatmap_data = await structured_safety_service.get_assessment_for_heatmap(analysis_id)
                print(f"[DEBUG] Structured heatmap data: {json.dumps(structured_heatmap_data, default=str)[:1000]}...")
                heatmap_result = await heatmap_service.generate_heatmap(structured_heatmap_data, analysis_id)
                
                return {
                    'success': True,
                    'heatmap_data': heatmap_result,
                    'message': 'Explosive risk heatmap generated successfully using structured data',
                    '_migration_info': {
                        'used_structured_data': True,
                        'new_endpoint': '/api/structured-safety/generate-heatmap',
                        'analysis_id': analysis_id
                    }
                }
            except Exception as structured_error:
                print(f"⚠️ Structured approach failed, falling back to old method: {structured_error}")
                import traceback
                traceback.print_exc()
        
        # Fallback to old method
        try:
            heatmap_result = await heatmap_service.generate_heatmap(floor_plan_data, analysis_id)
            print(f"[DEBUG] Heatmap result: {json.dumps(heatmap_result, default=str)[:1000]}...")
        except Exception as fallback_error:
            print(f"❌ Error in fallback heatmap generation: {fallback_error}")
            import traceback
            traceback.print_exc()
            raise
        
        return {
            'success': True,
            'heatmap_data': heatmap_result,
            'message': 'Explosive risk heatmap generated successfully',
            '_fallback_used': True
        }
        
    except Exception as e:
        print(f"❌ Exception in /generate-explosive-risk-heatmap: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Heatmap generation failed: {str(e)}") 