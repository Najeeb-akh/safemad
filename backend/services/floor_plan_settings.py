"""
Floor Plan Detection Settings

Based on the sanatladkat/floor-plan-object-detection repository
Configuration settings for floor plan object detection
"""

import os
from pathlib import Path
from typing import Dict, List, Any, Optional

# Base paths
BASE_DIR = Path(__file__).parent.parent
MODEL_DIR = BASE_DIR / "models"
UPLOADS_DIR = BASE_DIR / "uploads" / "floor_plans"

# Model settings
FLOOR_PLAN_MODEL_PATH = MODEL_DIR / "best.pt"
YOLO_MODEL_PATH = BASE_DIR / "yolov8n.pt"  # Fallback general YOLO model

# Detection settings
DEFAULT_CONFIDENCE_THRESHOLD = 0.4
MIN_CONFIDENCE_THRESHOLD = 0.1
MAX_CONFIDENCE_THRESHOLD = 0.9

# Image processing settings
MAX_IMAGE_SIZE = 4000  # pixels
MIN_IMAGE_SIZE = 100   # pixels
MAX_IMAGE_FILE_SIZE = 10 * 1024 * 1024  # 10MB

# Supported file formats
SUPPORTED_IMAGE_FORMATS = ['.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif']

# Floor plan object classes (from the trained model)
FLOOR_PLAN_CLASSES = {
    0: 'Column',
    1: 'Curtain Wall', 
    2: 'Dimension',
    3: 'Door',
    4: 'Railing',
    5: 'Sliding Door',
    6: 'Stair Case',
    7: 'Wall',
    8: 'Window'
}

# Class names list (for easy access)
CLASS_NAMES = list(FLOOR_PLAN_CLASSES.values())

# Color scheme for visualization (BGR format for OpenCV)
DETECTION_COLORS = {
    'Column': (255, 0, 0),      # Blue
    'Curtain Wall': (0, 255, 255),  # Yellow
    'Dimension': (255, 0, 255),     # Magenta
    'Door': (0, 255, 0),           # Green
    'Railing': (0, 165, 255),      # Orange
    'Sliding Door': (0, 128, 255),  # Orange-red
    'Stair Case': (128, 0, 128),   # Purple
    'Wall': (128, 128, 128),       # Gray
    'Window': (255, 255, 0)        # Cyan
}

# Priority levels for different elements (for UI display)
ELEMENT_PRIORITY = {
    'Door': 1,
    'Sliding Door': 1,
    'Window': 2,
    'Stair Case': 3,
    'Wall': 4,
    'Column': 5,
    'Railing': 6,
    'Curtain Wall': 7,
    'Dimension': 8
}

# Analysis settings
ROOM_CLUSTERING_THRESHOLD = 100  # pixels
MIN_ROOM_AREA = 1000  # square pixels
MAX_ROOMS_PER_PLAN = 20

# Export settings
CSV_EXPORT_COLUMNS = ['Label', 'Count', 'Confidence_Avg', 'Area_Total']
ANNOTATION_LINE_THICKNESS = 2
ANNOTATION_FONT_SCALE = 0.6
ANNOTATION_TEXT_THICKNESS = 2

# Performance settings
BATCH_SIZE = 1  # Process one image at a time for floor plans
MAX_DETECTION_TIME = 30  # seconds
ENABLE_GPU = True if os.environ.get('CUDA_AVAILABLE', 'false').lower() == 'true' else False

# API settings
MAX_CONCURRENT_REQUESTS = 5
REQUEST_TIMEOUT = 60  # seconds

# Logging settings
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'

# Feature flags
ENABLE_ROOM_DETECTION = True
ENABLE_AREA_ESTIMATION = True
ENABLE_LAYOUT_ANALYSIS = True
ENABLE_DETAILED_INSIGHTS = True

# Validation settings
class ValidationSettings:
    """Settings for input validation"""
    
    # Image validation
    MIN_WIDTH = MIN_IMAGE_SIZE
    MIN_HEIGHT = MIN_IMAGE_SIZE
    MAX_WIDTH = MAX_IMAGE_SIZE
    MAX_HEIGHT = MAX_IMAGE_SIZE
    MAX_FILE_SIZE = MAX_IMAGE_FILE_SIZE
    
    # Aspect ratio limits
    MIN_ASPECT_RATIO = 0.1
    MAX_ASPECT_RATIO = 10.0
    
    # Content validation
    MIN_ELEMENTS_FOR_ANALYSIS = 1
    MAX_ELEMENTS_FOR_PROCESSING = 200

# Detection quality settings
class DetectionQuality:
    """Settings for detection quality control"""
    
    # Confidence thresholds for different quality levels
    HIGH_QUALITY = 0.7
    MEDIUM_QUALITY = 0.5
    LOW_QUALITY = 0.3
    
    # Minimum detections for reliable analysis
    MIN_RELIABLE_DETECTIONS = 3
    
    # IoU threshold for non-maximum suppression
    NMS_IOU_THRESHOLD = 0.5

# Analysis configuration
class AnalysisConfig:
    """Configuration for floor plan analysis features"""
    
    # Room detection parameters
    ROOM_DETECTION_ENABLED = ENABLE_ROOM_DETECTION
    MIN_ROOM_ELEMENTS = 2
    ROOM_BOUNDARY_BUFFER = 50  # pixels
    
    # Layout analysis parameters
    LAYOUT_ANALYSIS_ENABLED = ENABLE_LAYOUT_ANALYSIS
    SPATIAL_CLUSTERING_DISTANCE = 150  # pixels
    
    # Insights generation
    INSIGHTS_ENABLED = ENABLE_DETAILED_INSIGHTS
    MIN_CONFIDENCE_FOR_INSIGHTS = 0.4

# Model configuration
class ModelConfig:
    """Configuration for model loading and inference"""
    
    # Model paths
    PRIMARY_MODEL = FLOOR_PLAN_MODEL_PATH
    FALLBACK_MODEL = YOLO_MODEL_PATH
    
    # Inference settings
    DEFAULT_CONF = DEFAULT_CONFIDENCE_THRESHOLD
    DEFAULT_IOU = DetectionQuality.NMS_IOU_THRESHOLD
    MAX_DET = 300  # Maximum detections per image
    
    # Device settings
    DEVICE = 'cuda' if ENABLE_GPU else 'cpu'
    HALF_PRECISION = False  # Use FP16 for faster inference on GPU

# UI/API response settings
class ResponseSettings:
    """Settings for API responses and UI display"""
    
    # Response format
    INCLUDE_ANNOTATED_IMAGE = True
    INCLUDE_ELEMENT_DETAILS = True
    INCLUDE_LAYOUT_INSIGHTS = True
    
    # Image encoding
    ANNOTATED_IMAGE_FORMAT = 'PNG'
    ANNOTATED_IMAGE_QUALITY = 95
    
    # Data precision
    CONFIDENCE_DECIMAL_PLACES = 3
    AREA_DECIMAL_PLACES = 1

def get_model_path() -> str:
    """Get the appropriate model path based on availability"""
    if FLOOR_PLAN_MODEL_PATH.exists():
        return str(FLOOR_PLAN_MODEL_PATH)
    elif YOLO_MODEL_PATH.exists():
        return str(YOLO_MODEL_PATH)
    else:
        raise FileNotFoundError("No suitable model found. Please ensure model files are available.")

def get_detection_color(class_name: str) -> tuple:
    """Get color for a specific class"""
    return DETECTION_COLORS.get(class_name, (255, 255, 255))  # Default to white

def get_element_priority(class_name: str) -> int:
    """Get priority level for UI display ordering"""
    return ELEMENT_PRIORITY.get(class_name, 99)

def create_directories():
    """Create necessary directories if they don't exist"""
    directories = [MODEL_DIR, UPLOADS_DIR]
    for directory in directories:
        directory.mkdir(parents=True, exist_ok=True)

def validate_settings():
    """Validate configuration settings"""
    errors = []
    
    # Check critical paths
    if not BASE_DIR.exists():
        errors.append(f"Base directory does not exist: {BASE_DIR}")
    
    # Check model availability
    try:
        get_model_path()
    except FileNotFoundError as e:
        errors.append(str(e))
    
    # Check confidence thresholds
    if not (0 <= DEFAULT_CONFIDENCE_THRESHOLD <= 1):
        errors.append("Default confidence threshold must be between 0 and 1")
    
    # Check image size limits
    if MIN_IMAGE_SIZE >= MAX_IMAGE_SIZE:
        errors.append("Minimum image size must be less than maximum image size")
    
    if errors:
        raise ValueError("Configuration validation failed:\n" + "\n".join(errors))
    
    return True

# Environment-specific overrides
def load_environment_overrides():
    """Load settings from environment variables"""
    global DEFAULT_CONFIDENCE_THRESHOLD, ENABLE_GPU, LOG_LEVEL
    
    # Override confidence threshold if set
    if 'FLOOR_PLAN_CONFIDENCE' in os.environ:
        try:
            DEFAULT_CONFIDENCE_THRESHOLD = float(os.environ['FLOOR_PLAN_CONFIDENCE'])
        except ValueError:
            pass
    
    # Override GPU setting
    if 'DISABLE_GPU' in os.environ:
        ENABLE_GPU = False
    
    # Override log level
    LOG_LEVEL = os.environ.get('LOG_LEVEL', LOG_LEVEL)

# Initialize settings
def initialize():
    """Initialize the settings module"""
    try:
        create_directories()
        load_environment_overrides()
        validate_settings()
        return True
    except Exception as e:
        print(f"Warning: Settings initialization failed: {e}")
        return False

# Auto-initialize when imported
_initialized = initialize() 