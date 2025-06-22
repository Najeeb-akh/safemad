from fastapi import APIRouter, UploadFile, File, HTTPException, Form
from fastapi.responses import JSONResponse
from ..services.wall_thickness_service import WallThicknessAnalyzer
import logging

logger = logging.getLogger(__name__)
router = APIRouter()

# Initialize analyzer
try:
    wall_thickness_analyzer = WallThicknessAnalyzer()
except Exception as e:
    logger.error(f"Failed to initialize analyzer: {e}")
    wall_thickness_analyzer = None

@router.post("/analyze-wall-thickness")
async def analyze_wall_thickness(
    file: UploadFile = File(...),
    room_id: str = Form(None)
):
    """
    Analyze wall thickness from door/window frame image using Depth Anything V2
    
    Args:
        file: Image file (JPG, PNG, etc.)
        room_id: Optional room identifier for context
        
    Returns:
        JSON response with wall thickness analysis results
    """
    try:
        logger.info(f"🔍 [WALL THICKNESS API DEBUG] Received request for room_id: {room_id}")
        logger.info(f"🔍 [WALL THICKNESS API DEBUG] File info - Name: {file.filename}, Content-Type: {file.content_type}, Size: {file.size if hasattr(file, 'size') else 'unknown'}")
        
        # Validate file
        if not file.content_type.startswith('image/'):
            logger.error(f"🔍 [WALL THICKNESS API DEBUG] Invalid content type: {file.content_type}")
            raise HTTPException(status_code=400, detail="File must be an image")
        
        # Read file
        logger.info(f"🔍 [WALL THICKNESS API DEBUG] Reading file content...")
        content = await file.read()
        logger.info(f"🔍 [WALL THICKNESS API DEBUG] File content read - Size: {len(content)} bytes")
        
        if len(content) == 0:
            logger.error(f"🔍 [WALL THICKNESS API DEBUG] Empty file received")
            raise HTTPException(status_code=400, detail="Empty file")
        
        # Check analyzer availability
        if wall_thickness_analyzer is None:
            logger.error(f"🔍 [WALL THICKNESS API DEBUG] Wall thickness analyzer is None - service unavailable")
            raise HTTPException(status_code=503, detail="Service unavailable")
        
        logger.info(f"🔍 [WALL THICKNESS API DEBUG] Analyzer available - calling analyze_wall_thickness...")
        
        # Analyze
        results = await wall_thickness_analyzer.analyze_wall_thickness(content, room_id)
        
        logger.info(f"🔍 [WALL THICKNESS API DEBUG] Analysis completed successfully")
        logger.info(f"🔍 [WALL THICKNESS API DEBUG] Results summary - Success: {results.get('success', False)}, Thickness: {results.get('wall_thickness_cm', 'N/A')} cm")
        
        return JSONResponse(status_code=200, content=results)
        
    except HTTPException as he:
        logger.error(f"🔍 [WALL THICKNESS API DEBUG] HTTP Exception: {he.status_code} - {he.detail}")
        raise
    except Exception as e:
        logger.error(f"🔍 [WALL THICKNESS API DEBUG] Unexpected error: {str(e)}")
        import traceback
        logger.error(f"🔍 [WALL THICKNESS API DEBUG] Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/wall-thickness-status")
async def get_status():
    logger.info(f"🔍 [WALL THICKNESS API DEBUG] Status check requested")
    
    if wall_thickness_analyzer is not None:
        logger.info(f"🔍 [WALL THICKNESS API DEBUG] Analyzer available - Device: {wall_thickness_analyzer.device}, Model loaded: {wall_thickness_analyzer.model is not None}")
        return {
            "available": True,
            "message": "Wall thickness analyzer ready",
            "device": str(wall_thickness_analyzer.device),
            "model_loaded": wall_thickness_analyzer.model is not None,
            "service_type": "Depth Anything V2"
        }
    else:
        logger.error(f"🔍 [WALL THICKNESS API DEBUG] Analyzer not available")
        return {
            "available": False,
            "message": "Service unavailable - analyzer not initialized",
            "device": None,
            "model_loaded": False,
            "service_type": None
        } 