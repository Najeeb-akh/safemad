from fastapi import APIRouter, UploadFile, File, HTTPException, Form, Query
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import uuid
from datetime import datetime
from backend.services.vision_service import vision_service
from backend.services.annotation_service import annotation_service
from backend.services.enhanced_floor_plan_service import EnhancedFloorPlanService
import os

router = APIRouter()

# Models for floor plan annotations
class RoomAnnotation(BaseModel):
    id: str
    name: str
    type: str
    placement: Dict[str, Any]
    size: Dict[str, Any]
    boundary: Dict[str, Any]

class FloorPlanAnnotations(BaseModel):
    rooms: List[RoomAnnotation]
    imageSize: Dict[str, float]

class AnnotationResponse(BaseModel):
    annotation_id: str
    message: str

# Model for point-based segmentation
class PointSegmentationRequest(BaseModel):
    point_coords: List[List[int]]  # [[x1, y1], [x2, y2], ...]
    point_labels: Optional[List[int]] = None  # [1, 1, 0, ...] (1=positive, 0=negative)
    multimask_output: bool = True

# In-memory storage for demo purposes (use database in production)
annotations_storage = {}

@router.post("/analyze-floor-plan-with-sam")
async def analyze_floor_plan_with_sam(
    file: UploadFile = File(...),
    confidence: float = Query(0.4, description="YOLO confidence threshold for architectural detection (0.0-1.0)"),
    enable_sam: bool = Query(True, description="Enable SAM room segmentation")
):
    """
    AI Detect Button Endpoint: Complete floor plan analysis with YOLO + SAM
    
    This endpoint performs the complete analysis workflow:
    1. YOLO detection for doors, windows, walls, stairs, columns, etc.
    2. SAM segmentation for intelligent room detection
    3. Combined analysis for enhanced insights
    
    Perfect for the frontend "AI Detect" button functionality.
    """
    print(f"🚀 AI Detect triggered: {file.filename}")
    
    # Validate file
    if file.content_type is None or not (file.content_type.startswith('image/') or file.content_type == 'application/octet-stream'):
        raise HTTPException(status_code=400, detail=f"File must be an image, got {file.content_type}")
    
    try:
        # Read the file
        image_bytes = await file.read()
        print(f"📁 Processing file: {file.filename} ({len(image_bytes)} bytes)")
        
        # Initialize enhanced service
        from backend.services.enhanced_floor_plan_service import EnhancedFloorPlanService
        service = EnhancedFloorPlanService()
        
        # Perform complete analysis (YOLO + SAM)
        results = await service.analyze_floor_plan_with_room_segmentation(
            image_bytes, 
            confidence=confidence, 
            enable_sam=enable_sam
        )
        
        # Add request metadata
        results['request_info'] = {
            'filename': file.filename,
            'file_size': len(image_bytes),
            'content_type': file.content_type,
            'yolo_confidence': confidence,
            'sam_enabled': enable_sam,
            'endpoint': 'ai_detect_yolo_plus_sam'
        }
        
        return results
        
    except Exception as e:
        print(f"❌ Error in AI Detect analysis: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to analyze floor plan with AI Detect: {str(e)}"
        )

@router.post("/analyze-floor-plan")
async def analyze_floor_plan(
    file: UploadFile = File(...),
    method: str = Query("auto", description="Analysis method: 'auto', 'google_vision', 'yolo', 'enhanced'"),
    confidence: float = Query(0.4, description="Confidence threshold for enhanced detection (0.0-1.0)")
):
    """
    Analyze a floor plan image using the specified method to detect rooms, doors, windows, and measurements
    
    Methods:
    - auto: Automatically select the best available method (Enhanced > YOLO > Google Vision)
    - enhanced: Use specialized floor plan YOLOv8 model (requires trained model)
    - yolo: Use YOLOv8 + Computer Vision hybrid approach
    - google_vision: Use Google Cloud Vision API with multi-pass analysis
    """
    # Debug: Print file details
    print(f"Received file: {file.filename}, content_type: {file.content_type}, method: {method}, confidence: {confidence}")
    
    # Validate method parameter
    valid_methods = ["auto", "google_vision", "yolo", "enhanced"]
    if method not in valid_methods:
        raise HTTPException(
            status_code=400, 
            detail=f"Invalid method '{method}'. Must be one of: {', '.join(valid_methods)}"
        )
    
    # Validate confidence parameter
    if not 0.0 <= confidence <= 1.0:
        raise HTTPException(
            status_code=400,
            detail="Confidence must be between 0.0 and 1.0"
        )
    
    # Accept both image/* and application/octet-stream (for binary data)
    if file.content_type is None or not (file.content_type.startswith('image/') or file.content_type == 'application/octet-stream'):
        print(f"Error: Invalid content type: {file.content_type}")
        raise HTTPException(status_code=400, detail=f"File must be an image, got {file.content_type}")
    
    try:
        # Read the file
        image_bytes = await file.read()
        print(f"Read {len(image_bytes)} bytes from uploaded file")
        
        # Process with specified method
        analysis_result = await vision_service.analyze_floor_plan(image_bytes, method=method, confidence=confidence)
        
        # Add method information to response
        analysis_result["requested_method"] = method
        analysis_result["requested_confidence"] = confidence
        analysis_result["file_info"] = {
            "filename": file.filename,
            "size_bytes": len(image_bytes),
            "content_type": file.content_type
        }
        
        return analysis_result
        
    except Exception as e:
        print(f"Error analyzing floor plan: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to analyze floor plan image with method '{method}': {str(e)}"
        )

@router.post("/save-floor-plan-annotations", response_model=AnnotationResponse)
async def save_floor_plan_annotations(annotations: FloorPlanAnnotations):
    """Save user-annotated floor plan data"""
    try:
        # Generate unique annotation ID
        annotation_id = str(uuid.uuid4())
        
        # Store annotations with timestamp
        annotations_storage[annotation_id] = {
            "id": annotation_id,
            "rooms": [room.dict() for room in annotations.rooms],
            "imageSize": annotations.imageSize,
            "created_at": datetime.now().isoformat(),
            "status": "saved"
        }
        
        print(f"Saved floor plan annotations with ID: {annotation_id}")
        print(f"Number of rooms: {len(annotations.rooms)}")
        
        return AnnotationResponse(
            annotation_id=annotation_id,
            message=f"Successfully saved {len(annotations.rooms)} room annotations"
        )
        
    except Exception as e:
        print(f"Error saving annotations: {e}")
        raise HTTPException(
            status_code=500, 
            detail=f"Failed to save floor plan annotations: {str(e)}"
        )

@router.get("/floor-plan-annotations/{annotation_id}")
async def get_floor_plan_annotations(annotation_id: str):
    """Retrieve saved floor plan annotations"""
    if annotation_id not in annotations_storage:
        raise HTTPException(
            status_code=404, 
            detail="Floor plan annotations not found"
        )
    
    return annotations_storage[annotation_id]

@router.get("/floor-plan-annotations")
async def list_floor_plan_annotations():
    """List all saved floor plan annotations"""
    return {
        "annotations": list(annotations_storage.values()),
        "total": len(annotations_storage)
    }

@router.post("/set-floor-plan-model")
async def set_floor_plan_model(model_path: str = Query(..., description="Path to the trained floor plan model (.pt file)")):
    """
    Set the path to the specialized floor plan detection model
    
    This endpoint allows you to specify a custom-trained YOLOv8 model for floor plan detection
    that can detect architectural elements like doors, windows, walls, etc.
    """
    try:
        # Check if file exists
        if not os.path.exists(model_path):
            raise HTTPException(
                status_code=400,
                detail=f"Model file not found at path: {model_path}"
            )
        
        # Check if it's a .pt file
        if not model_path.endswith('.pt'):
            raise HTTPException(
                status_code=400,
                detail="Model file must be a PyTorch model file (.pt)"
            )
        
        # Set the model in the vision service
        vision_service.set_floor_plan_model(model_path)
        
        # Save the model path for persistent loading
        model_path_file = os.path.join(os.path.dirname(__file__), "../models/ENHANCED_MODEL_PATH.txt")
        with open(model_path_file, "w") as f:
            f.write(model_path)
        
        return {
            "message": "Floor plan model set successfully",
            "model_path": model_path,
            "status": "ready"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error setting floor plan model: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to set floor plan model: {str(e)}"
        )

@router.get("/model-status")
async def get_model_status():
    """
    Get the status of available detection methods including SAM integration
    """
    from backend.services.vision_service import YOLO_AVAILABLE, ENHANCED_FLOOR_PLAN_AVAILABLE
    from backend.services.enhanced_floor_plan_service import enhanced_floor_plan_service
    
    # Check the current state of the enhanced service
    enhanced_model_loaded = False
    if enhanced_floor_plan_service is not None:
        try:
            enhanced_model_loaded = enhanced_floor_plan_service.floor_plan_detector is not None
        except AttributeError:
            enhanced_model_loaded = False
    
    # Check SAM availability
    sam_available = False
    sam_model_loaded = False
    try:
        from backend.services.enhanced_floor_plan_service import SAM_INTEGRATION_AVAILABLE
        from backend.services.sam_room_segmentation_service import sam_service, SAM_AVAILABLE
        sam_available = SAM_AVAILABLE
        sam_model_loaded = sam_service is not None and sam_service.sam_predictor is not None
    except ImportError:
        sam_available = False
        sam_model_loaded = False
    
    status = {
        "google_vision_api": not vision_service.use_dummy,
        "yolo_available": YOLO_AVAILABLE,
        "enhanced_floor_plan_available": ENHANCED_FLOOR_PLAN_AVAILABLE,
        "enhanced_model_loaded": enhanced_model_loaded,
        "sam_available": sam_available,
        "sam_model_loaded": sam_model_loaded,
        "ai_detect_ready": enhanced_model_loaded and sam_available,
        "recommended_method": "auto"
    }
    
    # Determine recommended method
    if status["ai_detect_ready"]:
        status["recommended_method"] = "ai_detect_yolo_plus_sam"
    elif status["enhanced_model_loaded"]:
        status["recommended_method"] = "enhanced"
    elif status["yolo_available"]:
        status["recommended_method"] = "yolo"
    elif status["google_vision_api"]:
        status["recommended_method"] = "google_vision"
    else:
        status["recommended_method"] = "dummy"
    
    # Add detailed SAM information
    status["sam_info"] = {
        "available": sam_available,
        "model_loaded": sam_model_loaded,
        "integration_status": "ready" if sam_model_loaded else "needs_setup" if sam_available else "unavailable"
    }
    
    return status 

@router.post("/segment-room-with-points")
async def segment_room_with_points(
    file: UploadFile = File(...),
    point_coords: str = Form(..., description="JSON string of point coordinates [[x1,y1],[x2,y2],...]"),
    point_labels: Optional[str] = Form(None, description="JSON string of point labels [1,1,0,...] (1=positive, 0=negative)"),
    multimask_output: bool = Form(True, description="Whether to output multiple masks")
):
    """
    Point-based Room Segmentation (EfficientViTSAM --mode point style)
    
    This endpoint allows users to click on specific points in a floor plan image
    and get segmentation masks for those areas, just like EfficientViTSAM's point mode.
    
    How to use:
    1. Upload a floor plan image
    2. Provide point coordinates where you want to segment (e.g., click locations)
    3. Optionally provide labels (1 for positive points, 0 for negative points)
    4. Get back segmentation masks with visualization
    
    Example:
    - point_coords: "[[400, 300], [450, 350]]" (two points)
    - point_labels: "[1, 1]" (both positive) or null for auto-positive
    """
    print(f"🎯 Point-based segmentation triggered: {file.filename}")
    
    # Validate file
    if not (file.content_type.startswith('image/') or file.content_type == 'application/octet-stream'):
        raise HTTPException(status_code=400, detail=f"File must be an image, got {file.content_type}")
    
    try:
        # Parse point coordinates
        import json
        try:
            coords = json.loads(point_coords)
            if not isinstance(coords, list) or not all(isinstance(p, list) and len(p) == 2 for p in coords):
                raise ValueError("Invalid format")
        except:
            raise HTTPException(
                status_code=400, 
                detail="point_coords must be valid JSON list of [x,y] coordinates, e.g. [[400,300],[450,350]]"
            )
        
        # Parse point labels if provided
        labels = None
        if point_labels:
            try:
                labels = json.loads(point_labels)
                if not isinstance(labels, list) or len(labels) != len(coords):
                    raise ValueError("Labels must match coords length")
            except:
                raise HTTPException(
                    status_code=400,
                    detail="point_labels must be valid JSON list of integers (1 or 0) matching point_coords length"
                )
        
        print(f"📍 Processing {len(coords)} points: {coords}")
        if labels:
            print(f"🏷️ Using labels: {labels}")
        
        # Read the file
        image_bytes = await file.read()
        print(f"📁 Processing file: {file.filename} ({len(image_bytes)} bytes)")
        
        # Get SAM service
        from backend.services.sam_room_segmentation_service import sam_service
        if not sam_service:
            raise HTTPException(
                status_code=503,
                detail="SAM service not available. Please ensure SAM is properly installed and initialized."
            )
        
        # Perform point-based segmentation
        results = await sam_service.segment_room_with_point_prompt(
            image_bytes=image_bytes,
            point_coords=coords,
            point_labels=labels,
            multimask_output=multimask_output
        )
        
        # Add request metadata
        results['request_info'] = {
            'filename': file.filename,
            'file_size': len(image_bytes),
            'content_type': file.content_type,
            'point_coords': coords,
            'point_labels': labels,
            'multimask_output': multimask_output,
            'endpoint': 'point_based_segmentation'
        }
        
        # Add usage examples to help frontend developers
        results['usage_example'] = {
            'description': 'This endpoint works like EfficientViTSAM --mode point',
            'frontend_integration': {
                'step1': 'User clicks on image to get coordinates',
                'step2': 'Send coordinates as JSON string in point_coords',
                'step3': 'Receive segmentation masks and visualization',
                'example_coords': '[[400,300],[450,350]]',
                'example_labels': '[1,1]'
            }
        }
        
        return results
        
    except HTTPException:
        raise  # Re-raise HTTP exceptions
    except Exception as e:
        print(f"❌ Error in point-based segmentation: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to perform point-based segmentation: {str(e)}"
        ) 