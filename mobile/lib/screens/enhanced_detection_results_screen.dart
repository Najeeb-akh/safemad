import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../services/enhanced_floor_plan_service.dart';
import 'room_safety_assessment_screen.dart';
import 'enhanced_safety_heatmap_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:math' as math;

// Add this constant
const String API_BASE_URL = 'http://127.0.0.1:8000'; // or your actual backend URL

class EnhancedDetectionResultsScreen extends StatefulWidget {
  final Map<String, dynamic> detectionResult;
  
  const EnhancedDetectionResultsScreen({
    Key? key,
    required this.detectionResult,
  }) : super(key: key);

  @override
  _EnhancedDetectionResultsScreenState createState() => _EnhancedDetectionResultsScreenState();
}

class _EnhancedDetectionResultsScreenState extends State<EnhancedDetectionResultsScreen>
    with SingleTickerProviderStateMixin {
  late EnhancedFloorPlanResult _result;
  int _selectedRoomIndex = 0;
  late TabController _tabController;
  
  // ===== ANNOTATION/DRAWING STATE VARIABLES =====
  bool _isAnnotationMode = false;
  String _currentDrawingTool = 'wall'; // wall, window, door, column, stairway, mamad, room, eraser
  Color _currentDrawingColor = Colors.lightGreen;
  double _strokeWidth = 3.0;
  List<Map<String, dynamic>> _userAnnotations = [];
  List<Offset> _currentStroke = [];
  bool _hasUnsavedAnnotations = false;
  bool _isCurrentlyDrawing = false; // Track if user is actively drawing
  bool _isProcessingAnnotation = false; // Track if we're updating the YOLO view
  bool _showOriginalImage = false; // Control which image to show
  
  // Room-specific drawing variables
  String _roomShape = 'rectangle'; // 'rectangle' or 'triangle'
  List<Offset> _roomCorners = []; // For tracking room shape corners
  bool _isDrawingRoom = false; // Special mode for room drawing
  
  // Enhanced drawing variables for room, mamad, and stairway
  String _selectedDrawingTool = 'rectangle'; // 'rectangle' or 'polygon'
  String _selectedRoomType = 'Living Room';
  bool _isCreatingWithBackend = false; // Whether we're using backend API
  List<Offset> _currentPolygonPoints = []; // For polygon drawing
  bool _showDrawingControls = false; // Show drawing controls
  
  // Keep original room drawing variables for compatibility
  String _selectedRoomDrawingTool = 'rectangle'; // 'rectangle' or 'polygon'
  bool _isCreatingRoomWithBackend = false; // Whether we're using backend API
  List<Offset> _currentRoomPolygonPoints = []; // For polygon room drawing
  bool _showRoomTypeSelector = false; // Show room type dropdown
  
  final List<String> _availableRoomTypes = [
    'Living Room', 'Bedroom', 'Kitchen', 'Bathroom', 'Dining Room',
    'Office', 'Laundry', 'Storage', 'Garage', 'Hallway',
     'Balcony', 'Other'
  ];
  
  // Global key for the painting widget
  final GlobalKey _paintingKey = GlobalKey();
  
  // Store original image dimensions for coordinate mapping
  double? _imageWidth;
  double? _imageHeight;
  double? _displayWidth;
  double? _displayHeight;
  
  // Controllers for editing room information
  final Map<int, TextEditingController> _roomNameControllers = {};
  final Map<int, TextEditingController> _roomDescControllers = {};
  bool _isEditingRoomInfo = false;
  
  // Controllers for editing user room information
  final Map<String, TextEditingController> _userRoomNameControllers = {};
  final Map<String, TextEditingController> _userRoomDescControllers = {};
  bool _isEditingUserRoom = false;
  String? _editingUserRoomId;

  // ===== HOUSE BOUNDARY DRAWING STATE VARIABLES =====
  List<Offset> _houseBoundaryPoints = [];
  bool _isDrawingHouseBoundary = false;
  bool _hasHouseBoundary = false;
  bool _isEditingHouseBoundary = false;
  
  // ===== HOUSE MATERIAL SELECTION STATE VARIABLES =====
  Map<String, double> _selectedHouseMaterials = {}; // Material name -> percentage
  final Map<String, TextEditingController> _percentageControllers = {};
  final List<Map<String, dynamic>> _israeliHouseMaterials = [
    {
      'name': 'Concrete Blocks',
      'hebrew': 'בלוקי בטון',
      'icon': Icons.view_module,
      'description': 'Standard concrete blocks - most common in Israeli construction',
    },
    {
      'name': 'Jerusalem Stone',
      'hebrew': 'אבן ירושלים',
      'icon': Icons.account_balance,
      'description': 'Natural limestone facing - traditional and prestigious',
    },
    {
      'name': 'Reinforced Concrete',
      'hebrew': 'בטון מזוין',
      'icon': Icons.construction,
      'description': 'Structural concrete with steel reinforcement',
    },
    {
      'name': 'Red Brick',
      'hebrew': 'לבני חרס',
      'icon': Icons.grid_view,
      'description': 'Traditional clay bricks - classic construction',
    },
    {
      'name': 'Thermal Blocks',
      'hebrew': 'בלוקים תרמיים',
      'icon': Icons.thermostat,
      'description': 'Insulated concrete blocks for energy efficiency',
    },
    {
      'name': 'Natural Stone',
      'hebrew': 'אבן טבעית',
      'icon': Icons.landscape,
      'description': 'Local stone varieties - durable and aesthetic',
    },
    {
      'name': 'Aerated Concrete',
      'hebrew': 'בטון קל',
      'icon': Icons.bubble_chart,
      'description': 'Lightweight concrete blocks with air bubbles',
    },
    {
      'name': 'Steel Frame',
      'hebrew': 'מסגרת פלדה',
      'icon': Icons.account_tree,
      'description': 'Steel structure with various cladding options',
    },
    {
      'name': 'Prefab Panels',
      'hebrew': 'פאנלים טרומיים',
      'icon': Icons.window,
      'description': 'Precast concrete panels - modern construction',
    },
    {
      'name': 'Other',
      'hebrew': 'אחר',
      'icon': Icons.more_horiz,
      'description': 'Other building materials',
    },
  ];
  
  @override
  void initState() {
    super.initState();
    _result = EnhancedFloorPlanResult.fromJson(widget.detectionResult);
    _tabController = TabController(length: 4, vsync: this);
    
    // Initialize room name controllers
    _initializeRoomControllers();
    
    // Debug information
    print('🔍 Enhanced Detection Results Debug:');
    print('   Processing Method: ${_result.processingMethod}');
    print('   Has Annotated Image: ${_result.annotatedImageBase64 != null}');
    print('   Has SAM Visualization: ${_result.samVisualization != null}');
    print('   Has Original Image: ${_result.originalImageBase64 != null}');
    print('   Detected Rooms: ${_result.detectedRooms.length}');
    print('   Raw Data Keys: ${widget.detectionResult.keys.toList()}');
    print('   Has Individual Visualizations: ${_result.individualVisualizations != null}');
    
    // Enhanced debugging - print ALL raw data
    print('📊 Raw Detection Result Data:');
    widget.detectionResult.forEach((key, value) {
      if (value is List) {
        print('   $key: List with ${value.length} items');
        if (value.isNotEmpty) {
          print('     First item type: ${value.first.runtimeType}');
          if (value.first is Map) {
            print('     First item keys: ${(value.first as Map).keys.toList()}');
          }
        }
      } else if (value is Map) {
        print('   $key: Map with keys: ${value.keys.toList()}');
      } else {
        print('   $key: ${value.runtimeType} - ${value.toString().length > 50 ? value.toString().substring(0, 50) + '...' : value}');
      }
    });
    
    // Debug room details
    print('🏠 Room Details:');
    for (int i = 0; i < _result.detectedRooms.length; i++) {
      final room = _result.detectedRooms[i];
      print('   Room $i: ${room.roomId}');
      print('     Name: ${room.defaultName}');
      print('     Type detected: ${room.defaultName?.toLowerCase()}');
      print('     Doors: ${room.doors.length}');
      print('     Windows: ${room.windows.length}');
      print('     Walls: ${room.walls.length}');
      print('     Boundaries: ${room.boundaries}');
    }
    
    // Debug architectural elements
    print('🏗️ Architectural Elements:');
    for (int i = 0; i < _result.architecturalElements.length; i++) {
      final element = _result.architecturalElements[i];
      print('   Element $i: ${element.type} (confidence: ${element.confidence})');
      print('     Position: ${element.center}');
      print('     Dimensions: ${element.dimensions}');
    }
    
    if (_result.individualVisualizations != null) {
      print('   Individual Viz Keys: ${_result.individualVisualizations!.keys.toList()}');
    }
    
    if (_result.samVisualization != null) {
      print('   SAM Viz Length: ${_result.samVisualization!.length} chars');
    }
    if (_result.annotatedImageBase64 != null) {
      print('   YOLO Viz Length: ${_result.annotatedImageBase64!.length} chars');
    }
  }

  void _initializeRoomControllers() {
    for (int i = 0; i < _result.detectedRooms.length; i++) {
      final room = _result.detectedRooms[i];
      _roomNameControllers[i] = TextEditingController(
        text: (room.defaultName?.isNotEmpty == true) ? room.defaultName! : 'Room ${i + 1}'
      );
      _roomDescControllers[i] = TextEditingController(text: room.description ?? '');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    
    // Dispose room controllers
    for (final controller in _roomNameControllers.values) {
      controller.dispose();
    }
    for (final controller in _roomDescControllers.values) {
      controller.dispose();
    }
    
    // Dispose user room controllers
    for (final controller in _userRoomNameControllers.values) {
      controller.dispose();
    }
    for (final controller in _userRoomDescControllers.values) {
      controller.dispose();
    }
    
    // Dispose percentage controllers
    for (final controller in _percentageControllers.values) {
      controller.dispose();
    }
    
    super.dispose();
  }

  // Helper function to clean base64 string
  Uint8List _decodeBase64Image(String base64String) {
    try {
      // Check if the string is empty or null
      if (base64String.isEmpty) {
        print('Base64 string is empty');
        return Uint8List(0);
      }
      
      // Remove data URL prefix if present
      String cleanBase64 = base64String;
      if (base64String.startsWith('data:')) {
        final commaIndex = base64String.indexOf(',');
        if (commaIndex != -1) {
          cleanBase64 = base64String.substring(commaIndex + 1);
        }
      }
      
      // Remove any whitespace
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');
      
      // Check if the cleaned string is valid base64
      if (cleanBase64.isEmpty) {
        print('Cleaned base64 string is empty');
        return Uint8List(0);
      }
      
      return base64Decode(cleanBase64);
    } catch (e) {
      print('Error decoding base64 image: $e');
      print('Original string length: ${base64String.length}');
      // Return empty bytes as fallback
      return Uint8List(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhanced Detection Results'),
        actions: [
          // Edit mode toggle for room information
          IconButton(
            icon: Icon(_isEditingRoomInfo ? Icons.save : Icons.edit),
            onPressed: _toggleEditMode,
            tooltip: _isEditingRoomInfo ? 'Save Changes' : 'Edit Room Info',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAnalysisInfo,
            tooltip: 'Analysis Information',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.analytics),
              text: 'Analysis',
            ),
            Tab(
              icon: Icon(Icons.image),
              text: 'Visualizations',
            ),
            Tab(
              icon: Icon(Icons.draw),
              text: 'Annotate',
            ),
            Tab(
              icon: Icon(Icons.home_outlined),
              text: 'Vital Info',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAnalysisView(),
          _buildVisualizationView(),
          _buildAnnotationView(),
          _buildVitalInfoView(),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildAnalysisView() {
    return Column(
      children: [
        _buildSummaryCard(),
        Expanded(
          child: Row(
            children: [
              // Left panel - Room list
              Expanded(
                flex: 1,
                child: _buildRoomList(),
              ),
              // Right panel - Room details
              Expanded(
                flex: 2,
                child: _buildRoomDetails(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVisualizationView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Detection Visualizations',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Powered by YOLO and Meta\'s Segment Anything Model (SAM)',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          _buildImageVisualizationSection(),
        ],
      ),
    );
  }

  Widget _buildImageVisualizationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Original Floor Plan
        if (_result.originalImageBase64 != null) ...[
          _buildImageCard(
            'Original Floor Plan',
            _result.originalImageBase64!,
            Icons.home_outlined,
            Colors.blue,
            'The original uploaded floor plan image used for analysis',
          ),
          const SizedBox(height: 20),
        ],
        
        // YOLO Detection Results
        if (_result.annotatedImageBase64 != null) ...[
          _buildImageCard(
            'YOLO Architectural Detection',
            _result.annotatedImageBase64!,
            Icons.auto_awesome,
            Colors.green,
            'Computer vision detection of architectural elements including doors, windows, walls, and stairs. Each element is highlighted with bounding boxes and confidence scores.',
          ),
          const SizedBox(height: 20),
        ],
        
        // SAM Room Segmentation - Composite View
        if (_result.samVisualization != null) ...[
          _buildSamCompositeCard(),
          const SizedBox(height: 20),
        ] else ...[
          _buildSamUnavailableCard(),
          const SizedBox(height: 20),
        ],
        
        // Point Segmentation Results (EfficientViTSAM style)
        _buildPointSegmentationSection(),
        
        // SAM Technical Information
        _buildSamTechnicalInfoCard(),
        
        // Combined Analysis Insights
        const SizedBox(height: 20),
        _buildAnalysisInsightsCard(),
      ],
    );
  }

  Widget _buildPointSegmentationSection() {
    // Check if point segmentation result is available in the data
    final pointSegmentationResult = widget.detectionResult['point_segmentation_result'];
    
    if (pointSegmentationResult != null && pointSegmentationResult['visualization'] != null) {
      return Column(
        children: [
          _buildPointSegmentationCard(pointSegmentationResult),
          const SizedBox(height: 20),
        ],
      );
    } else {
      // Show a card explaining how to use point segmentation
      return Column(
        children: [
          _buildPointSegmentationInfoCard(),
          const SizedBox(height: 20),
        ],
      );
    }
  }

  Widget _buildPointSegmentationCard(Map<String, dynamic> pointResult) {
    final visualization = pointResult['visualization'];
    final masks = pointResult['masks'] ?? [];
    final totalMasks = pointResult['total_masks'] ?? 0;
    final metadata = pointResult['metadata'] ?? {};
    
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.touch_app, color: Colors.indigo, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Point-Based Segmentation Results',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      Text(
                        'EfficientViTSAM-style point segmentation with ${totalMasks} mask(s) generated',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.withOpacity(0.1), Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.withOpacity(0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GestureDetector(
                  onTap: () => _showFullScreenImage('Point-Based Segmentation Results', visualization),
                  child: _buildImageWidget(visualization),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Point Segmentation Details:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo[800]),
                  ),
                  const SizedBox(height: 8),
                  _buildPointSegmentationDetail('Total Masks Generated', totalMasks.toString(), Icons.layers),
                  _buildPointSegmentationDetail('Input Points', '${pointResult['point_count'] ?? 'N/A'}', Icons.touch_app),
                  _buildPointSegmentationDetail('Segmentation Method', 'SAM Point Prompt', Icons.psychology),
                  if (masks.isNotEmpty) ...[
                    _buildPointSegmentationDetail('Best Mask Score', '${(masks[0]['score'] * 100).toStringAsFixed(1)}%', Icons.verified),
                    _buildPointSegmentationDetail('Segmented Area', '${masks[0]['area_percentage'].toStringAsFixed(1)}% of image', Icons.area_chart),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.indigo[600]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'This shows the result of clicking on specific points in the floor plan to segment rooms, similar to EfficientViTSAM\'s --mode point functionality.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.indigo[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointSegmentationDetail(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.indigo[600]),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.indigo[800]),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointSegmentationInfoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.touch_app, color: Colors.teal, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Point-Based Segmentation Available',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[800],
                        ),
                      ),
                      Text(
                        'Click on specific points in floor plans to segment rooms',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to Use Point Segmentation:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[800]),
                  ),
                  const SizedBox(height: 8),
                  _buildHowToItem('1. Upload a floor plan image'),
                  _buildHowToItem('2. Click on specific points where you want to segment'),
                  _buildHowToItem('3. Get precise room segmentation masks'),
                  _buildHowToItem('4. View results with confidence scores'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.api, size: 16, color: Colors.blue[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'API Endpoint: POST /api/segment-room-with-points',
                            style: TextStyle(fontSize: 12, color: Colors.blue[600], fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.psychology, size: 16, color: Colors.purple[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Powered by Meta\'s Segment Anything Model (SAM)',
                            style: TextStyle(fontSize: 12, color: Colors.purple[600]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHowToItem(String instruction) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right, size: 14, color: Colors.teal[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              instruction,
              style: TextStyle(fontSize: 12, color: Colors.teal[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(String title, String base64Image, IconData icon, Color color, String description) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: color.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GestureDetector(
                  onTap: () => _showFullScreenImage(title, base64Image),
                  child: _buildImageWidget(base64Image),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to view full screen',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(String base64Image) {
    Uint8List imageBytes = _decodeBase64Image(base64Image);
    if (imageBytes.isEmpty) {
      return Container(
        height: 200,
        color: Colors.grey[300],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text('Failed to load image', style: TextStyle(color: Colors.red)),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Image.memory(
          imageBytes,
          key: const ValueKey('annotation_image'), // Consistent key for layout stability
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),
        // Custom painter for annotations - only show when not drawing or when using eraser
        Positioned.fill(
          child: CustomPaint(
            painter: AnnotationPainter(
              annotations: _isCurrentlyDrawing && _currentDrawingTool != 'eraser' 
                  ? [] // Hide existing annotations while drawing for smooth experience
                  : _userAnnotations,
              currentStroke: _currentStroke,
              strokeColor: _getToolColor(_currentDrawingTool),
              strokeWidth: _strokeWidth,
              isEraser: _currentDrawingTool == 'eraser',
            ),
          ),
        ),
        // Image mode indicator
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isCurrentlyDrawing 
                  ? Colors.green.withOpacity(0.9)
                  : Colors.blue.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isCurrentlyDrawing ? Icons.edit : Icons.auto_awesome,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _isCurrentlyDrawing ? 'Drawing Mode' : 'AI Detection View',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSamCompositeCard() {
    // Check if individual visualizations are available
    final individualViz = _result.individualVisualizations;
    
    if (individualViz != null && individualViz.isNotEmpty) {
      return _buildIndividualSamVisualizationsCard(individualViz);
    }
    
    // Fallback to composite view if individual visualizations not available
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.view_module, color: Colors.purple, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SAM Room Segmentation',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                      Text(
                        'Multiple visualization styles inspired by Meta\'s official SAM repository',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.withOpacity(0.1), Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GestureDetector(
                  onTap: () => _showFullScreenImage('SAM Room Segmentation - Multiple Views', _result.samVisualization!),
                  child: _buildImageWidget(_result.samVisualization!),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Visualization Components:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple[800]),
                  ),
                  const SizedBox(height: 8),
                  _buildVisualizationComponent('Original Image', 'Left panel - your original floor plan', Icons.image),
                  _buildVisualizationComponent('SAM Masks Overlay', 'Top right - transparent colored masks over original', Icons.layers),
                  _buildVisualizationComponent('Colored Segments', 'Middle right - solid colored room segments', Icons.palette),
                  _buildVisualizationComponent('Boundaries Only', 'Bottom left - room outline boundaries', Icons.border_all),
                  _buildVisualizationComponent('Labeled Segments', 'Bottom right - segments with room information', Icons.label),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.touch_app, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Tap to view full screen with zoom and pan controls',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndividualSamVisualizationsCard(Map<String, dynamic> individualViz) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.view_module, color: Colors.purple, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SAM Room Segmentation Results',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                      Text(
                        'Source image and segmented results with colored room overlays',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Source Image (Original)
            if (individualViz['original'] != null) ...[
              _buildIndividualVisualizationSection(
                'Source Image',
                'Your original floor plan as input to SAM',
                individualViz['original'],
                Icons.image_outlined,
                Colors.blue,
              ),
              const SizedBox(height: 16),
            ],
            
            // Segmentation Result (Masks Overlay)
            if (individualViz['masks_overlay'] != null) ...[
              _buildIndividualVisualizationSection(
                'Segmentation Result',
                'Original image with colored room segment overlays',
                individualViz['masks_overlay'],
                Icons.layers,
                Colors.green,
              ),
              const SizedBox(height: 16),
            ],
            
            // Optional: Show other visualizations in a collapsible section
            _buildOtherVisualizationsSection(individualViz),
            
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.purple[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The segmentation result shows detected rooms with transparent colored overlays. Each color represents a different room segment detected by SAM.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.purple[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndividualVisualizationSection(
    String title,
    String description,
    String base64Image,
    IconData icon,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GestureDetector(
              onTap: () => _showFullScreenImage(title, base64Image),
              child: _buildImageWidget(base64Image),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to view full screen',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[500],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildOtherVisualizationsSection(Map<String, dynamic> individualViz) {
    // Check what other visualizations are available
    final otherViz = <String, String>{};
    
    if (individualViz['colored_segments'] != null) {
      otherViz['Colored Segments'] = individualViz['colored_segments'];
    }
    if (individualViz['boundaries'] != null) {
      otherViz['Boundaries Only'] = individualViz['boundaries'];
    }
    if (individualViz['labeled_segments'] != null) {
      otherViz['Labeled Segments'] = individualViz['labeled_segments'];
    }
    
    if (otherViz.isEmpty) return const SizedBox.shrink();
    
    return ExpansionTile(
      leading: Icon(Icons.visibility, color: Colors.purple[600]),
      title: Text(
        'Additional Visualizations',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.purple[800],
        ),
      ),
      subtitle: Text(
        'View alternative visualization styles',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      children: otherViz.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildIndividualVisualizationSection(
            entry.key,
            _getVisualizationDescription(entry.key),
            entry.value,
            _getVisualizationIcon(entry.key),
            Colors.purple,
          ),
        );
      }).toList(),
    );
  }

  String _getVisualizationDescription(String type) {
    switch (type) {
      case 'Colored Segments':
        return 'Solid colored room segments without original image background';
      case 'Boundaries Only':
        return 'Room boundaries and outlines overlaid on original image';
      case 'Labeled Segments':
        return 'Room segments with labels showing room information and area percentages';
      default:
        return 'Alternative visualization style';
    }
  }

  IconData _getVisualizationIcon(String type) {
    switch (type) {
      case 'Colored Segments':
        return Icons.palette;
      case 'Boundaries Only':
        return Icons.border_all;
      case 'Labeled Segments':
        return Icons.label;
      default:
        return Icons.image;
    }
  }

  Widget _buildVisualizationComponent(String title, String description, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.purple[600]),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.purple[800]),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSamTechnicalInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: Colors.blue[600]),
                const SizedBox(width: 8),
                Text(
                  'Technical Information',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTechnicalInfoRow('Model Architecture', 'YOLO + SAM Hybrid Approach'),
            _buildTechnicalInfoRow('YOLO Model', 'YOLOv8 trained on architectural elements'),
            _buildTechnicalInfoRow('SAM Model', 'Meta\'s Segment Anything Model for room segmentation'),
            _buildTechnicalInfoRow('Processing Method', _result.processingMethod.replaceAll('_', ' ').toUpperCase()),
            _buildTechnicalInfoRow('Detection Confidence', '${(_result.detectionConfidence * 100).toStringAsFixed(0)}%'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Based on Meta AI Research\'s Segment Anything Model',
                      style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisInsightsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: Colors.green[600]),
                const SizedBox(width: 8),
                Text(
                  'Analysis Insights',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              'Rooms Detected',
              '${_result.detectedRooms.length}',
              Icons.room,
              Colors.blue,
            ),
            _buildInsightRow(
              'Architectural Elements',
              '${_result.totalDoors + _result.totalWindows + _result.totalWalls}',
              Icons.architecture,
              Colors.orange,
            ),
            _buildInsightRow(
              'Detection Accuracy',
              _getAccuracyDescription(),
              Icons.verified,
              Colors.green,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _result.analysisSummary,
                style: TextStyle(fontSize: 12, color: Colors.green[700]),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getAnnotationSummary(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            // Add legend if user has annotations
            if (_userAnnotations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      'Legend: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'AI Detected',
                      style: TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'User Drawn',
                      style: TextStyle(fontSize: 11, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInsightRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  String _getAccuracyDescription() {
    if (_result.detectionConfidence >= 0.8) return 'High Confidence';
    if (_result.detectionConfidence >= 0.6) return 'Good Confidence';
    return 'Moderate Confidence';
  }

  Widget _buildSummaryCard() {
    final combinedCounts = _getCombinedElementCounts();
    
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getMethodIcon(_result.processingMethod),
                  color: _getMethodColor(_result.processingMethod),
                ),
                const SizedBox(width: 8),
                Text(
                  'Analysis Summary',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                if (_userAnnotations.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 12, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text(
                          '${_userAnnotations.length} user additions',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildEnhancedSummaryItem('Rooms', combinedCounts['rooms']!.toString(), Icons.room, 0, 0),
                _buildEnhancedSummaryItem('Doors', combinedCounts['doors']!.toString(), Icons.door_front_door, _result.totalDoors, _getUserAnnotationCount('door')),
                _buildEnhancedSummaryItem('Windows', combinedCounts['windows']!.toString(), Icons.window, _result.totalWindows, _getUserAnnotationCount('window')),
                _buildEnhancedSummaryItem('Walls', combinedCounts['walls']!.toString(), Icons.wallpaper, _result.totalWalls, _getUserAnnotationCount('wall')),
                if (combinedCounts['stairs']! > 0)
                  _buildEnhancedSummaryItem('Stairs', combinedCounts['stairs']!.toString(), Icons.stairs, _result.totalStairs, _getUserAnnotationCount('stairway')),
              ],
            ),

            // Show user-only elements if they exist
            if (combinedCounts['columns']! > 0 || combinedCounts['mamad']! > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (combinedCounts['columns']! > 0)
                    _buildEnhancedSummaryItem('Columns', combinedCounts['columns']!.toString(), Icons.view_column, 0, combinedCounts['columns']!),
                  if (combinedCounts['mamad']! > 0)
                    _buildEnhancedSummaryItem('MAMAD', combinedCounts['mamad']!.toString(), Icons.security, 0, combinedCounts['mamad']!),
                  // Add spacers to maintain layout
                  if (combinedCounts['columns']! == 0) const Expanded(child: SizedBox()),
                  if (combinedCounts['mamad']! == 0) const Expanded(child: SizedBox()),
                  const Expanded(child: SizedBox()),
                  const Expanded(child: SizedBox()),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _getAnnotationSummary(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_result.error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _result.error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedSummaryItem(String label, String value, IconData icon, int aiCount, int userCount) {
    return Expanded(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 24, color: Colors.blue),
              if (userCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 8,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (aiCount > 0 && userCount > 0) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  '$aiCount',
                  style: const TextStyle(fontSize: 8, color: Colors.blue),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  '$userCount',
                  style: const TextStyle(fontSize: 8, color: Colors.green),
                ),
              ],
            ),
          ] else if (userCount > 0) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  'user-drawn',
                  style: const TextStyle(fontSize: 8, color: Colors.green),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomList() {
    final allRooms = _getAllRooms();
    
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text(
                  'All Rooms (${allRooms.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_getUserDrawnRooms().isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 10, color: Colors.green[700]),
                        const SizedBox(width: 2),
                        Text(
                          '${_getUserDrawnRooms().length} user-drawn',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: allRooms.length,
              itemBuilder: (context, index) {
                final room = allRooms[index];
                final isSelected = index == _selectedRoomIndex;
                final isUserDrawn = room['isUserDrawn'] as bool;
                
                return ListTile(
                  selected: isSelected,
                  leading: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        backgroundColor: isSelected 
                            ? (isUserDrawn ? Colors.green : Colors.blue)
                            : Colors.grey.shade300,
                        child: Text(
                          (index + 1).toString(),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isUserDrawn)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: Icon(
                              Icons.edit,
                              size: 8,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          room['defaultName'],
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isUserDrawn ? Colors.green[800] : null,
                          ),
                        ),
                      ),
                      if (isUserDrawn) ...[
                        Icon(
                          room['roomData'] != null && (room['roomData'] as Map)['shape'] == 'triangle'
                              ? Icons.change_history
                              : Icons.rectangle_outlined,
                          size: 16,
                          color: Colors.green[600],
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    isUserDrawn 
                        ? 'User-drawn • ${(room['roomData'] as Map)['shape']}'
                        : 'Confidence: ${(room['confidence'] * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: isUserDrawn 
                          ? Colors.green[600]
                          : _getConfidenceColor(room['confidence']),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isUserDrawn) ...[
                        if ((room['doors'] as List).isNotEmpty)
                          Icon(Icons.door_front_door, size: 16, color: Colors.orange),
                        if ((room['windows'] as List).isNotEmpty)
                          Icon(Icons.window, size: 16, color: Colors.blue),
                      ],
                    ],
                  ),
                  onTap: () {
                    setState(() {
                      _selectedRoomIndex = index;
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomDetails() {
    final allRooms = _getAllRooms();
    
    if (allRooms.isEmpty) {
      return const Card(
        margin: EdgeInsets.all(8.0),
        child: Center(
          child: Text('No rooms detected'),
        ),
      );
    }

    final room = allRooms[_selectedRoomIndex];
    
    final isUserDrawn = room['isUserDrawn'] as bool;
    
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isUserDrawn ? Colors.green : Colors.blue,
                  child: Text(
                    (_selectedRoomIndex + 1).toString(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              room['defaultName'] as String,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: isUserDrawn ? Colors.green[800] : null,
                              ),
                            ),
                          ),
                          if (isUserDrawn) ...[
                            Icon(
                              Icons.edit,
                              size: 16,
                              color: Colors.green[600],
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Detection Method: ${room['detectionMethod'] as String}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isUserDrawn ? Colors.green[600] : null,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text('${((room['confidence'] as double) * 100).toStringAsFixed(0)}%'),
                  backgroundColor: _getConfidenceColor(room['confidence'] as double).withOpacity(0.2),
                  labelStyle: TextStyle(color: _getConfidenceColor(room['confidence'] as double)),
                ),
              ],
            ),
            const SizedBox(height: 16),
                         // Room description or user-drawn room details
             if (isUserDrawn && room['roomData'] != null) ...[
               Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: Colors.green.withOpacity(0.05),
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: Colors.green.withOpacity(0.2)),
                 ),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Row(
                       children: [
                         Icon(Icons.person_outline, size: 16, color: Colors.green[600]),
                         const SizedBox(width: 8),
                         Text(
                           'User-Drawn Room',
                           style: TextStyle(
                             fontWeight: FontWeight.bold,
                             color: Colors.green[800],
                           ),
                         ),
                         const Spacer(),
                         // Edit button for user rooms
                         IconButton(
                           onPressed: () => _toggleUserRoomEdit(room['id'] as String),
                           icon: Icon(
                             _isEditingUserRoom && _editingUserRoomId == room['id'] 
                                 ? Icons.save 
                                 : Icons.edit,
                             size: 16,
                             color: Colors.green[600],
                           ),
                           tooltip: _isEditingUserRoom && _editingUserRoomId == room['id'] 
                               ? 'Save Changes' 
                               : 'Edit Room',
                           padding: EdgeInsets.zero,
                           constraints: const BoxConstraints(),
                         ),
                       ],
                     ),
                     const SizedBox(height: 8),
                     // Room name field (editable if in edit mode)
                     _buildUserRoomNameField(room),
                     const SizedBox(height: 8),
                     // Room description field (editable if in edit mode)
                     _buildUserRoomDescriptionField(room),
                     const SizedBox(height: 8),
                     ..._buildUserRoomDetails(room['roomData']),
                   ],
                 ),
               ),
             ] else ...[
              Text(
                room.containsKey('description') ? room['description'] as String : 'No description available',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
                         // Only show architectural elements for AI-detected rooms
             if (!isUserDrawn) ...[
               _buildArchitecturalElementsSection('Doors', (room['doors'] as List<dynamic>).cast<ArchitecturalElement>(), Icons.door_front_door, Colors.orange),
               _buildArchitecturalElementsSection('Windows', (room['windows'] as List<dynamic>).cast<ArchitecturalElement>(), Icons.window, Colors.blue),
               _buildArchitecturalElementsSection('Walls', (room['walls'] as List<dynamic>).cast<ArchitecturalElement>(), Icons.wallpaper, Colors.grey),
              if ((room['estimatedDimensions'] as Map<String, dynamic>).isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildDimensionsSection(room['estimatedDimensions'] as Map<String, double>),
              ],
              const SizedBox(height: 16),
              _buildBoundariesSection(room['boundaries'] as Map<String, dynamic>),
            ] else ...[
              // Show message for user-drawn rooms
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'User-drawn rooms don\'t have detailed architectural element detection. Use the AI detection results to identify doors, windows, and walls.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Add this in the room details section, after the architectural elements
            // Add a new section for wall thickness analysis
            const SizedBox(height: 16),
            _buildWallThicknessAnalysisSection(room),
          ],
        ),
      ),
    );
  }

  Widget _buildArchitecturalElementsSection(
    String title,
    List<ArchitecturalElement> elements,
    IconData icon,
    Color color,
  ) {
    if (elements.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              '$title (${elements.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...elements.map((element) => _buildElementCard(element, color)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildElementCard(ArchitecturalElement element, Color color) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 8, color: color),
                const SizedBox(width: 8),
                Text(
                  element.type,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${(element.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: _getConfidenceColor(element.confidence),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Position: ${element.relativePosition}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              'Size: ${element.dimensions['width']} × ${element.dimensions['height']} px',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionsSection(Map<String, double> dimensions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.straighten, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              'Estimated Dimensions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...dimensions.entries.map((entry) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text('${entry.key}: '),
              Text(
                '${entry.value.toStringAsFixed(2)} m',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildBoundariesSection(Map<String, dynamic> boundaries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.border_all, color: Colors.purple),
            const SizedBox(width: 8),
            Text(
              'Room Boundaries',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Top: ${boundaries['top'] ?? 'N/A'}',
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          'Left: ${boundaries['left'] ?? 'N/A'}',
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          'Bottom: ${boundaries['bottom'] ?? 'N/A'}',
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          'Right: ${boundaries['right'] ?? 'N/A'}',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _proceedToSafetyAssessment,
              icon: const Icon(Icons.security),
              label: const Text('Safety Assessment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAnalysisInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analysis Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Method', _result.processingMethod),
            _buildInfoRow('Confidence', '${(_result.detectionConfidence * 100).toStringAsFixed(0)}%'),
            _buildInfoRow('Image Size', '${_result.imageDimensions['width']} × ${_result.imageDimensions['height']}'),
            const SizedBox(height: 16),
            const Text(
              'Detected Elements:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ..._result.elementCounts.entries.map((entry) => 
              _buildInfoRow(entry.key, entry.value.toString())
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: '),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _convertArchitecturalElements(dynamic elements) {
    if (elements == null) return [];
    
    if (elements is List) {
      return elements.map<Map<String, dynamic>>((e) {
        if (e is Map<String, dynamic>) {
          return {
            'type': e['type']?.toString() ?? 'unknown',
            'confidence': (e['confidence'] is num) ? e['confidence'].toDouble() : 0.0,
            'position': e['position'] ?? e['relativePosition'] ?? {},
          };
        } else {
          // Handle ArchitecturalElement objects
          return {
            'type': e.type?.toString() ?? 'unknown',
            'confidence': (e.confidence is num) ? e.confidence.toDouble() : 0.0,
            'position': e.relativePosition ?? {},
          };
        }
      }).toList();
    } else if (elements is Map) {
      // If it's a Map, convert it to a single-item list
      return [{
        'type': elements['type']?.toString() ?? 'unknown',
        'confidence': (elements['confidence'] is num) ? elements['confidence'].toDouble() : 0.0,
        'position': elements['position'] ?? elements['relativePosition'] ?? {},
      }];
    }
    
    return [];
  }

  int _getSafeListLength(dynamic list) {
    if (list == null) return 0;
    if (list is List) return list.length;
    if (list is Map) return 1; // Treat single map as one item
    return 0;
  }

  void _proceedToSafetyAssessment() {
    List<Map<String, dynamic>> roomsForSafety;
    
    try {
      print('🔍 Starting safety assessment navigation...');
      print('   Detected rooms count: ${_result.detectedRooms.length}');
      
      // Convert enhanced results to the format expected by safety assessment
      roomsForSafety = _result.detectedRooms.asMap().entries.map((entry) {
        final index = entry.key;
        final room = entry.value;
        
        print('   Processing room $index: ${room.roomId}');
        
        return {
          'id': room.roomId ?? 'room_$index',
          'name': (room.defaultName?.isNotEmpty == true) ? room.defaultName : 'Room ${index + 1}',
          'type': (room.defaultName?.isNotEmpty == true) ? room.defaultName!.toLowerCase() : 'room',
          'confidence': room.confidence ?? 0.0,
          'doors': _getSafeListLength(room.doors),
          'windows': _getSafeListLength(room.windows),
          'walls': _getSafeListLength(room.walls),
          'description': room.description ?? '',
          'boundaries': room.boundaries ?? [],
          'architectural_elements': _convertArchitecturalElements(room.architecturalElements),
        };
      }).toList();
      
      print('   Converted ${roomsForSafety.length} rooms for safety assessment');
      
      if (roomsForSafety.isEmpty) {
        print('⚠️ No rooms found for safety assessment');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No rooms detected for safety assessment')),
        );
        return;
      }
    } catch (e) {
      print('❌ Error in room conversion: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error preparing room data: $e')),
      );
      return;
    }

    // Convert all architectural elements from the detection results
    final architecturalElements = _result.architecturalElements.map((element) => {
      'type': element.type,
      'confidence': element.confidence,
      'x': element.center['x']?.toDouble() ?? 0.0,
      'y': element.center['y']?.toDouble() ?? 0.0,
      'width': element.dimensions['width']?.toDouble() ?? 0.0,
      'height': element.dimensions['height']?.toDouble() ?? 0.0,
      'area': element.area?.toDouble() ?? 0.0,
      'bbox': element.bbox,
      'center': element.center,
      'dimensions': element.dimensions,
      'relative_position': element.relativePosition,
    }).toList();

    final annotationId = 'enhanced_${DateTime.now().millisecondsSinceEpoch}';

    // Show assessment type selection
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Safety Assessment Type'),
        content: const Text(
          'Select how you would like to assess the safety of your floor plan:'
        ),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  
                  // Determine the best image to use
                  String? imageToUse = _result.originalImageBase64;
                  if (imageToUse == null || imageToUse.isEmpty) {
                    imageToUse = _result.annotatedImageBase64;
                    print('🖼️ Using annotated image as fallback');
                  } else {
                    print('🖼️ Using original image');
                  }
                  
                  print('   Image data available: ${imageToUse != null}');
                  if (imageToUse != null) {
                    print('   Image length: ${imageToUse.length}');
                    print('   Image starts with: ${imageToUse.substring(0, math.min(50, imageToUse.length))}');
                  }
                  
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EnhancedSafetyHeatmapScreen(
                        rooms: roomsForSafety,
                        architecturalElements: architecturalElements,
                        annotationId: annotationId,
                        floorPlanImagePath: imageToUse,
                        rawDetectionResult: widget.detectionResult,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.grid_on),
                label: const Text('Enhanced Safety Heatmap'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RoomSafetyAssessmentScreen(
                        rooms: roomsForSafety,
                        annotationId: annotationId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.assessment),
                label: const Text('Room-by-Room Assessment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getMethodIcon(String method) {
    switch (method) {
      case 'enhanced_floor_plan_yolo':
        return Icons.auto_awesome;
      case 'yolo_vision_hybrid':
        return Icons.visibility;
      case 'google_vision_api':
        return Icons.cloud;
      default:
        return Icons.analytics;
    }
  }

  Color _getMethodColor(String method) {
    switch (method) {
      case 'enhanced_floor_plan_yolo':
        return Colors.green;
      case 'yolo_vision_hybrid':
        return Colors.blue;
      case 'google_vision_api':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }

  void _showFullScreenImage(String title, String base64Image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: _buildFullScreenImageWidget(base64Image),
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenImageWidget(String base64Image) {
    Uint8List imageBytes = _decodeBase64Image(base64Image);
    if (imageBytes.isEmpty) {
      return Container(
        color: Colors.grey[800],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: Colors.white, size: 60),
            const SizedBox(height: 16),
            Text(
              'Failed to load image',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      );
    }
    return Image.memory(
      imageBytes,
      fit: BoxFit.contain,
    );
  }

  Widget _buildSamUnavailableCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.warning_amber, color: Colors.orange, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SAM Visualization Unavailable',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                      Text(
                        'Room segmentation visualization could not be generated',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Possible Reasons:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800]),
                  ),
                  const SizedBox(height: 8),
                  _buildReasonItem('SAM model not available on the server'),
                  _buildReasonItem('Image processing failed during segmentation'),
                  _buildReasonItem('SAM service not properly initialized'),
                  _buildReasonItem('Network error during analysis'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, size: 16, color: Colors.blue[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'YOLO architectural detection is still available in the Analysis tab',
                            style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonItem(String reason) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 6, color: Colors.orange[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(fontSize: 12, color: Colors.orange[800]),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleEditMode() {
    setState(() {
      _isEditingRoomInfo = !_isEditingRoomInfo;
    });
  }

  Widget _buildVitalInfoView() {
    if (_result.originalImageBase64 == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Original Image Required',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The original floor plan image is required for house boundary annotation.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // House boundary toolbar
        Container(
          height: 80,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.home_outlined, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'House Boundary',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[700],
                ),
              ),
              const Spacer(),
              // Clear boundary button
              if (_hasHouseBoundary)
                IconButton(
                  onPressed: _clearHouseBoundary,
                  icon: Icon(Icons.clear, color: Colors.red[600]),
                  tooltip: 'Clear Boundary',
                ),
              // Finish boundary button
              if (_isDrawingHouseBoundary && _houseBoundaryPoints.length >= 3)
                ElevatedButton.icon(
                  onPressed: _finishHouseBoundary,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Finish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              const SizedBox(width: 8),
              // Edit boundary button
              if (_hasHouseBoundary && !_isDrawingHouseBoundary)
                IconButton(
                  onPressed: _editHouseBoundary,
                  icon: Icon(Icons.edit, color: Colors.blue[600]),
                  tooltip: 'Edit Boundary',
                ),
            ],
          ),
        ),
        // Drawing area
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildHouseBoundaryImageWidget(_result.originalImageBase64!),
              ),
            ),
          ),
        ),
        // House Wall Thickness Section
        if (_hasHouseBoundary) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.05),
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.architecture, size: 20, color: Colors.deepPurple[700]),
                    const SizedBox(width: 8),
                    Text(
                      'House Wall Thickness',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Measure the thickness of your house\'s outer perimeter walls',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.deepPurple[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                _buildHouseWallThicknessSection(),
              ],
            ),
          ),
        ],
        // Material Selection Section
        if (_hasHouseBoundary) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.construction, size: 20, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      'House Material Selection',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'What material is your house exterior made of?',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                _buildMaterialSelection(),
              ],
            ),
          ),
        ],
        // Instructions
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.05),
            border: Border(
              top: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isDrawingHouseBoundary
                          ? 'Click on the image to add points and define the house boundary. Click "Finish" when done.'
                          : _hasHouseBoundary
                              ? 'House boundary has been defined. Click "Edit" to modify or "Clear" to start over.'
                              : 'Click on the image to start drawing the house boundary polygon.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[600],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: Colors.green[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Define the outer boundary of your house to help identify the building perimeter and calculate vital information like total area and perimeter.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              if (_hasHouseBoundary && _selectedHouseMaterials.isEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.arrow_upward, size: 16, color: Colors.blue[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Next: Measure wall thickness and select house material above to complete vital information.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnnotationView() {
    if (_result.annotatedImageBase64 == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No YOLO Detection Image Available',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The annotated image from YOLO detection is required for annotation.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Annotation toolbar with fixed height
        Container(
          height: 120, // Fixed height to prevent resizing
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.draw, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Annotation Tools',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  const Spacer(),
                  // Save button
                  ElevatedButton.icon(
                    onPressed: _hasUnsavedAnnotations ? _saveAnnotations : null,
                    icon: Icon(
                      Icons.save,
                      size: 16,
                      color: _hasUnsavedAnnotations ? Colors.white : Colors.grey,
                    ),
                    label: Text(
                      'Save',
                      style: TextStyle(
                        color: _hasUnsavedAnnotations ? Colors.white : Colors.grey,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasUnsavedAnnotations ? Colors.green : Colors.grey[300],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Undo button
                  IconButton(
                    onPressed: _userAnnotations.isNotEmpty ? _undoLastAnnotation : null,
                    icon: Icon(
                      Icons.undo,
                      color: _userAnnotations.isNotEmpty ? Colors.orange : Colors.grey,
                    ),
                    tooltip: 'Undo Last Annotation',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Tool selection row
              Expanded(
                child: Row(
                  children: [
                    _buildToolButton('wall', Icons.line_style, Colors.lightGreen, 'Wall'),
                    const SizedBox(width: 8),
                    _buildToolButton('window', Icons.window, Colors.green, 'Window'),
                    const SizedBox(width: 8),
                    _buildToolButton('door', Icons.door_front_door, Colors.orange, 'Door'),
                    const SizedBox(width: 8),
                    _buildToolButton('column', Icons.view_column, Colors.red, 'Column'),
                    const SizedBox(width: 8),
                    _buildEnhancedToolButton('stairway', Icons.stairs, Colors.purple, 'Stairway'),
                    const SizedBox(width: 8),
                    _buildEnhancedToolButton('mamad', Icons.security, const Color(0xFFFF1493), 'MAMAD'),
                    const SizedBox(width: 8),
                    _buildRoomToolButton(),
                    const SizedBox(width: 8),
                    _buildToolButton('eraser', Icons.delete_forever, Colors.grey, 'Eraser'),
                    const Spacer(),
                    // Stroke width control
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Stroke: ${_strokeWidth.toInt()}px',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Slider(
                            value: _strokeWidth,
                            min: 1.0,
                            max: 10.0,
                            divisions: 9,
                            onChanged: (value) {
                              setState(() {
                                _strokeWidth = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Drawing area - takes remaining space
        Expanded(
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildDrawableImageWidget(_result.annotatedImageBase64!),
                  ),
                ),
              ),
              // Floating controls overlay
              if (_showDrawingControls && (_currentDrawingTool == 'stairway' || _currentDrawingTool == 'mamad')) 
                _buildFloatingEnhancedControls(),
              if (_showRoomTypeSelector && _currentDrawingTool == 'room')
                _buildFloatingRoomControls(),
            ],
          ),
        ),
        // Instructions
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.05),
            border: Border(
              top: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select a tool above and draw directly on the image to add missing architectural elements. Enhanced tools (MAMAD, Stairway, Room) support both rectangle and polygon drawing modes with advanced controls.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[600],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: Colors.green[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Smart Room Tool: Select room type → Choose rectangle (drag) or polygon (click points) → For polygons, click "Finish" when done. Rooms are sent to backend for enhanced processing!',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The image automatically switches to the original clean image while drawing for smooth interaction, then shows the AI detection results with your annotations.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolButton(String tool, IconData icon, Color color, String label) {
    final isSelected = _currentDrawingTool == tool;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentDrawingTool = tool;
          _currentDrawingColor = color;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedToolButton(String tool, IconData icon, Color color, String label) {
    final isSelected = _currentDrawingTool == tool;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentDrawingTool = tool;
          _currentDrawingColor = color;
          _showDrawingControls = isSelected ? !_showDrawingControls : true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
            if (isSelected && _showDrawingControls) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.settings,
                size: 12,
                color: isSelected ? Colors.white : color,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDrawingModeButton(String mode, IconData icon, String label) {
    final isSelected = _selectedDrawingTool == mode;
    final color = Colors.blue.shade600;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDrawingTool = mode;
          // Reset polygon points when switching tools
          if (mode != 'polygon') {
            _currentPolygonPoints.clear();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawableImageWidget(String base64Image) {
    // Determine which image to show based on the current state
    String imageToShow;
    if (_showOriginalImage && _result.originalImageBase64 != null) {
      // Show original image while drawing
      imageToShow = _result.originalImageBase64!;
    } else {
      // Show YOLO image by default and after processing
      imageToShow = base64Image;
    }
    
    Uint8List imageBytes = _decodeBase64Image(imageToShow);
    if (imageBytes.isEmpty) {
      return Container(
        height: 200,
        color: Colors.grey[300],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text('Failed to load image', style: TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Store display dimensions for coordinate mapping
        _displayWidth = constraints.maxWidth;
        _displayHeight = constraints.maxHeight;
        
        return GestureDetector(
          onPanStart: (details) {
            final RenderBox renderBox = context.findRenderObject() as RenderBox;
            final localPosition = renderBox.globalToLocal(details.globalPosition);
            final adjustedPosition = _adjustCoordinatesForImage(localPosition, constraints);
            
            // Switch to original image when starting to draw
            setState(() {
              _isCurrentlyDrawing = true;
              _showOriginalImage = true;
            });
            
            if (_currentDrawingTool == 'eraser') {
              setState(() {
                _currentStroke = [adjustedPosition];
              });
              _handleEraserTouch(adjustedPosition);
            } else if (_currentDrawingTool == 'room') {
              _startRoomDrawing(adjustedPosition);
            } else if (_currentDrawingTool == 'mamad' || _currentDrawingTool == 'stairway') {
              // Enhanced tools always use enhanced drawing (both rectangle and polygon)
              //_startEnhancedDrawing(adjustedPosition);
              _startRoomDrawing(adjustedPosition);
            } else {
              _startDrawing(adjustedPosition);
            }
          },
          onPanUpdate: (details) {
            final RenderBox renderBox = context.findRenderObject() as RenderBox;
            final localPosition = renderBox.globalToLocal(details.globalPosition);
            final adjustedPosition = _adjustCoordinatesForImage(localPosition, constraints);
            
            if (_currentDrawingTool == 'eraser') {
              setState(() {
                _currentStroke = [adjustedPosition];
              });
              _handleEraserTouch(adjustedPosition);
            } else if (_currentDrawingTool == 'room') {
              _continueRoomDrawing(adjustedPosition);
            } else if (_currentDrawingTool == 'mamad' || _currentDrawingTool == 'stairway') {
              // Enhanced tools always use enhanced drawing (both rectangle and polygon)
              //_continueEnhancedDrawing(adjustedPosition);
              _continueRoomDrawing(adjustedPosition);
            } else {
              _continueDrawing(adjustedPosition);
            }
          },
          onPanEnd: (details) {
            if (_currentDrawingTool == 'room') {
              final RenderBox renderBox = context.findRenderObject() as RenderBox;
              final localPosition = renderBox.globalToLocal(details.globalPosition);
              final adjustedPosition = _adjustCoordinatesForImage(localPosition, constraints);
              _finishRoomDrawing(adjustedPosition);
            } else if ((_currentDrawingTool == 'mamad' || _currentDrawingTool == 'stairway') && _selectedDrawingTool == 'rectangle') {
              // Only finish enhanced drawing for rectangle mode, not polygon mode
              _finishEnhancedDrawing(_currentDrawingTool);
            }
            // Process the annotation and switch back to YOLO view
            _finishDrawingAndProcess();
          },
          onTapDown: (details) {
            final RenderBox renderBox = context.findRenderObject() as RenderBox;
            final localPosition = renderBox.globalToLocal(details.globalPosition);
            final adjustedPosition = _adjustCoordinatesForImage(localPosition, constraints);
            
            if (_currentDrawingTool == 'eraser') {
              setState(() {
                _isCurrentlyDrawing = true;
                _showOriginalImage = true;
                _currentStroke = [adjustedPosition];
              });
              _handleEraserTouch(adjustedPosition);
            } else if (_currentDrawingTool == 'room' && _selectedRoomDrawingTool == 'polygon') {
              // Handle room polygon point addition
              setState(() {
                _isCurrentlyDrawing = true;
                _showOriginalImage = true;
                _currentRoomPolygonPoints.add(adjustedPosition);
                _isDrawingRoom = true;
              });
            } else if ((_currentDrawingTool == 'mamad' || _currentDrawingTool == 'stairway') && _selectedDrawingTool == 'polygon') {
              // Handle enhanced tool polygon point addition
              setState(() {
                _isCurrentlyDrawing = true;
                _showOriginalImage = true;
                _currentPolygonPoints.add(adjustedPosition);
                _isDrawingRoom = true;
              });
            }
          },
          onTapUp: (details) {
            if (_currentDrawingTool == 'eraser') {
              _finishDrawingAndProcess();
            }
            // For polygon rooms, don't finish drawing - user needs to tap "Finish" button
          },
          child: Stack(
            children: [
              Image.memory(
                imageBytes,
                key: const ValueKey('annotation_image'), // Consistent key for layout stability
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
              // Custom painter for annotations - only show when not drawing or when using eraser
              Positioned.fill(
                child: CustomPaint(
                  painter: AnnotationPainter(
                    annotations: _isCurrentlyDrawing && _currentDrawingTool != 'eraser' 
                        ? [] // Hide existing annotations while drawing for smooth experience
                        : _userAnnotations,
                    currentStroke: _currentStroke,
                    strokeColor: _getToolColor(_currentDrawingTool),
                    strokeWidth: _strokeWidth,
                    isEraser: _currentDrawingTool == 'eraser',
                    polygonPoints: _currentDrawingTool == 'room' && _selectedRoomDrawingTool == 'polygon' 
                        ? _currentRoomPolygonPoints 
                        : (_currentDrawingTool == 'mamad' || _currentDrawingTool == 'stairway') && _selectedDrawingTool == 'polygon'
                            ? _currentPolygonPoints
                            : [],
                    isDrawingRoom: _isDrawingRoom,
                  ),
                ),
              ),
              // Image mode indicator
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isCreatingWithBackend
                        ? Colors.purple.withOpacity(0.9)
                        : _isCurrentlyDrawing 
                            ? Colors.green.withOpacity(0.9)
                            : Colors.blue.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isCreatingWithBackend) ...[
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Creating Smart Room...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else ...[
                        Icon(
                          _isCurrentlyDrawing ? Icons.edit : Icons.auto_awesome,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isCurrentlyDrawing ? 'Drawing Mode' : 'AI Detection View',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Offset _adjustCoordinatesForImage(Offset localPosition, BoxConstraints constraints) {
    // Since we're using BoxFit.contain, the image might be letterboxed or pillarboxed
    // We need to calculate the actual image bounds within the container
    
    final containerWidth = constraints.maxWidth;
    final containerHeight = constraints.maxHeight;
    
    // Store the container dimensions
    _imageWidth = containerWidth;
    _imageHeight = containerHeight;
    
    // For BoxFit.contain, the image is scaled to fit within the container while maintaining aspect ratio
    // We need to calculate where the actual image is positioned within the widget bounds
    
    // Since both original and YOLO images should have the same dimensions,
    // we can assume they will be scaled and positioned identically
    
    // Calculate the scale factor and offset for BoxFit.contain
    // This ensures touch coordinates map correctly to image coordinates
    
    // For now, we'll use the raw coordinates but ensure consistency
    // The key insight is that both images must use the exact same coordinate system
    
    return localPosition;
  }

  void _handleEraserTouch(Offset position) {
    const double eraserRadius = 20.0; // Adjust this value to change eraser sensitivity
    
    final annotationsToRemove = <Map<String, dynamic>>[];
    
    for (final annotation in _userAnnotations) {
      final points = annotation['points'] as List<dynamic>;
      
      // Check if any point in the annotation is within eraser radius
      for (final pointData in points) {
        final point = pointData as Map<String, dynamic>;
        final annotationPoint = Offset(point['x'] as double, point['y'] as double);
        final distance = (position - annotationPoint).distance;
        
        if (distance <= eraserRadius) {
          annotationsToRemove.add(annotation);
          break; // Found one point within radius, remove entire annotation
        }
      }
    }
    
    if (annotationsToRemove.isNotEmpty) {
      setState(() {
        for (final annotation in annotationsToRemove) {
          _userAnnotations.remove(annotation);
        }
        _hasUnsavedAnnotations = _userAnnotations.isNotEmpty;
      });
      
      // Debug: Print updated counts after erasing
      print('🗑️ Erased ${annotationsToRemove.length} annotation(s)');
      print('   Updated counts: ${_getCombinedElementCounts()}');
    }
  }

  void _saveAnnotations() async {
    if (_userAnnotations.isEmpty) return;
    
    try {
      // Convert annotations to the format expected by the backend
      final annotationsData = {
        'annotations': _userAnnotations,
        'image_dimensions': {
          'width': _imageWidth ?? 0,
          'height': _imageHeight ?? 0,
        },
        'display_dimensions': {
          'width': _displayWidth ?? 0,
          'height': _displayHeight ?? 0,
        },
      };
      
      // Call the service to save annotations
      await EnhancedFloorPlanService.saveAnnotations(
        _userAnnotations, 
        {
          'width': (_imageWidth ?? 0).toInt(),
          'height': (_imageHeight ?? 0).toInt(),
        }
      );
      
      setState(() {
        _hasUnsavedAnnotations = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Annotations saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save annotations: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _undoLastAnnotation() {
    if (_userAnnotations.isNotEmpty) {
      setState(() {
        _userAnnotations.removeLast();
        _hasUnsavedAnnotations = _userAnnotations.isNotEmpty;
      });
    }
  }

  void _startDrawing(Offset position) {
    setState(() {
      _currentStroke = [position];
      // _isCurrentlyDrawing is already set in onPanStart
    });
  }

  void _continueDrawing(Offset position) {
    setState(() {
      _currentStroke.add(position);
    });
  }

  void _startEnhancedDrawing(Offset position) {
    if (_selectedDrawingTool == 'rectangle') {
      setState(() {
        _isDrawingRoom = true;
        _currentStroke = [position]; // Store start position for rectangle
      });
    } else if (_selectedDrawingTool == 'polygon') {
      setState(() {
        _isDrawingRoom = true;
        _currentPolygonPoints.add(position);
      });
    }
  }

  void _continueEnhancedDrawing(Offset position) {
    if (_selectedDrawingTool == 'rectangle') {
      // For rectangle drawing, track the current position for preview (similar to room drawing)
      setState(() {
        if (_currentStroke.length == 1) {
          // Show preview of rectangle being drawn
          _currentStroke = _generateEnhancedRectanglePreview(_currentStroke[0], position);
        }
      });
    } else if (_selectedDrawingTool == 'polygon') {
      // For polygon drawing, show preview line to current position (similar to room drawing)
      setState(() {
        if (_currentPolygonPoints.isNotEmpty) {
          _currentStroke = [..._currentPolygonPoints, position];
        }
      });
    }
  }

  void _finishEnhancedDrawing(String tool) {
    if (_selectedDrawingTool == 'rectangle') {
      _finishEnhancedRectangle(tool);
    } else if (_selectedDrawingTool == 'polygon') {
      // For polygon, don't finish on pan end - only finish when user clicks "Finish" button
      // Just add the current point to the polygon
      // This method should not be called for polygon mode on pan end
      return;
    }
  }

  void _finishEnhancedRectangle(String tool) {
    if (_currentStroke.length >= 4) { // Rectangle should have at least 4 points
      // Create enhanced annotation (similar to room but for MAMAD/Stairway)
      final center = _calculateShapeCenter(_currentStroke);
      final annotation = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'tool': tool,
        'color': _currentDrawingColor.value,
        'strokeWidth': _strokeWidth,
        'points': _currentStroke.map((point) => {'x': point.dx, 'y': point.dy}).toList(),
        'timestamp': DateTime.now().toIso8601String(),
        'drawingMode': 'rectangle',
        // Add room-like data for MAMAD (since MAMAD is essentially a room)
        if (tool == 'mamad') 'roomData': {
          'shape': 'rectangle',
          'area': _calculateShapeArea(_currentStroke),
          'center': {'x': center.dx, 'y': center.dy},
          'defaultName': 'MAMAD ${_getUserAnnotationCount('mamad') + 1}',
          'description': 'Protected room (MAMAD)',
          'isUserDrawn': true,
          'roomType': 'MAMAD',
        },
      };
      
      setState(() {
        _userAnnotations.add(annotation);
        _currentStroke = [];
        _hasUnsavedAnnotations = true;
        _isDrawingRoom = false;
      });
      
      print('🎨 Enhanced $tool rectangle completed with area ${tool == 'mamad' ? (annotation['roomData'] as Map)['area'] : 'N/A'}');
    }
  }

  List<Offset> _generateEnhancedRectanglePreview(Offset start, Offset current) {
    // Generate rectangle preview (same logic as room drawing)
    return [
      start,
      Offset(current.dx, start.dy), // Top right
      current, // Bottom right
      Offset(start.dx, current.dy), // Bottom left
      start, // Close the shape
    ];
  }

  void _endDrawing() {
    if (_currentStroke.isNotEmpty) {
      final annotation = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'tool': _currentDrawingTool,
        'color': _currentDrawingColor.value,
        'strokeWidth': _strokeWidth,
        'points': _currentStroke.map((point) => {'x': point.dx, 'y': point.dy}).toList(),
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Debug: Print first and last points to check coordinate consistency
      if (_currentStroke.length > 1) {
        print('🎨 Drawing completed:');
        print('   First point: ${_currentStroke.first}');
        print('   Last point: ${_currentStroke.last}');
        print('   Total points: ${_currentStroke.length}');
        print('   Container size: $_displayWidth x $_displayHeight');
        print('   Tool: ${_currentDrawingTool}');
        print('   Updated counts: ${_getCombinedElementCounts()}');
      }
      
      setState(() {
        _userAnnotations.add(annotation);
        _currentStroke = [];
        _hasUnsavedAnnotations = true;
        // Don't set _isCurrentlyDrawing here - it's handled by _finishDrawingAndProcess
      });
    }
  }

  void _finishDrawingAndProcess() async {
    setState(() {
      _isCurrentlyDrawing = false;
      _isProcessingAnnotation = true;
    });
    
    // Process the drawing (save annotation if it exists)
    if (_currentDrawingTool == 'eraser') {
      setState(() {
        _currentStroke = [];
      });
    } else if (_currentDrawingTool == 'room') {
      // Room drawing is handled in _finishRoomDrawing
      setState(() {
        _isDrawingRoom = false;
        _roomCorners = [];
        _currentStroke = [];
      });
    } else {
      _endDrawing();
    }
    
    // Simulate processing time (you can adjust this or make it depend on actual processing)
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Switch back to YOLO view with updated annotations
    setState(() {
      _isProcessingAnnotation = false;
      _showOriginalImage = false;
    });
  }

  Color _getToolColor(String tool) {
    switch (tool) {
      case 'wall': return Colors.lightGreen;
      case 'window': return Colors.green;
      case 'door': return Colors.orange;
      case 'column': return Colors.red;
      case 'stairway': return Colors.purple;
      case 'mamad': return const Color(0xFFFF1493); // Bright pink/flashy
      case 'room': return Colors.grey.shade400;
      case 'eraser': return Colors.grey;
      default: return Colors.grey;
    }
  }

  IconData _getToolIcon(String tool) {
    switch (tool) {
      case 'wall': return Icons.line_style;
      case 'window': return Icons.window;
      case 'door': return Icons.door_front_door;
      case 'column': return Icons.view_column;
      case 'stairway': return Icons.stairs;
      case 'mamad': return Icons.security;
      case 'room': return Icons.crop_free;
      case 'eraser': return Icons.delete_forever;
      default: return Icons.edit;
    }
  }

  // Helper methods for counting user annotations
  int _getUserAnnotationCount(String elementType) {
    return _userAnnotations.where((annotation) => 
      annotation['tool'] == elementType
    ).length;
  }
  
  Map<String, int> _getCombinedElementCounts() {
    return {
      'rooms': _result.detectedRooms.length + _getUserAnnotationCount('room') + _getUserAnnotationCount('mamad'), // Include MAMAD as rooms
      'doors': _result.totalDoors + _getUserAnnotationCount('door'),
      'windows': _result.totalWindows + _getUserAnnotationCount('window'),
      'walls': _result.totalWalls + _getUserAnnotationCount('wall'),
      'stairs': _result.totalStairs + _getUserAnnotationCount('stairway'), // Now includes user-drawn stairs
      'columns': _getUserAnnotationCount('column'), // User-only for now
      'mamad': _getUserAnnotationCount('mamad'), // User-only for now
    };
  }
  
  String _getAnnotationSummary() {
    final userWalls = _getUserAnnotationCount('wall');
    final userDoors = _getUserAnnotationCount('door');
    final userWindows = _getUserAnnotationCount('window');
    final userColumns = _getUserAnnotationCount('column');
    final userStairways = _getUserAnnotationCount('stairway');
    final userMamad = _getUserAnnotationCount('mamad');
    final userRooms = _getUserAnnotationCount('room');
    
    final totalUserAnnotations = userWalls + userDoors + userWindows + userColumns + userStairways + userMamad + userRooms;
    
    if (totalUserAnnotations == 0) {
      return _result.analysisSummary;
    }
    
    final userSummary = <String>[];
    if (userWalls > 0) userSummary.add('$userWalls user-drawn wall${userWalls > 1 ? 's' : ''}');
    if (userDoors > 0) userSummary.add('$userDoors user-drawn door${userDoors > 1 ? 's' : ''}');
    if (userWindows > 0) userSummary.add('$userWindows user-drawn window${userWindows > 1 ? 's' : ''}');
    if (userColumns > 0) userSummary.add('$userColumns user-drawn column${userColumns > 1 ? 's' : ''}');
    if (userStairways > 0) userSummary.add('$userStairways user-drawn stairway${userStairways > 1 ? 's' : ''}');
    if (userMamad > 0) userSummary.add('$userMamad user-drawn MAMAD room${userMamad > 1 ? 's' : ''}'); // MAMAD as rooms
    if (userRooms > 0) userSummary.add('$userRooms user-drawn room${userRooms > 1 ? 's' : ''}');
    
    return '${_result.analysisSummary}\n\nUser Additions: ${userSummary.join(', ')}.';
  }

  Widget _buildRoomToolButton() {
    final isSelected = _currentDrawingTool == 'room';
    final color = Colors.blue.shade600; // More professional blue color
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentDrawingTool = 'room';
          _currentDrawingColor = color;
          _showRoomTypeSelector = isSelected ? !_showRoomTypeSelector : true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.meeting_room,
              size: 16,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              'Room',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
            if (isSelected && _showRoomTypeSelector) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.settings,
                size: 12,
                color: isSelected ? Colors.white : color,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoomDrawingToolButton(String tool, IconData icon, String label) {
    final isSelected = _selectedRoomDrawingTool == tool;
    final color = Colors.blue.shade600;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRoomDrawingTool = tool;
          // Reset polygon points when switching tools
          if (tool != 'polygon') {
            _currentRoomPolygonPoints.clear();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShapeButton(String shape, IconData icon) {
    final isSelected = _roomShape == shape;
    final color = Colors.grey.shade600;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _roomShape = shape;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: color,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 12,
          color: isSelected ? Colors.white : color,
        ),
      ),
    );
  }

  void _startRoomDrawing(Offset position) {
    if (_selectedRoomDrawingTool == 'rectangle') {
      setState(() {
        _isDrawingRoom = true;
        _roomCorners = [position];
      });
    } else if (_selectedRoomDrawingTool == 'polygon') {
      setState(() {
        _isDrawingRoom = true;
        _currentRoomPolygonPoints.add(position);
      });
    }
  }

  void _continueRoomDrawing(Offset position) {
    if (_selectedRoomDrawingTool == 'rectangle') {
      // For rectangle drawing, track the current position for preview
      setState(() {
        if (_roomCorners.length == 1) {
          // Show preview of rectangle being drawn
          _currentStroke = _generateShapePreview(_roomCorners[0], position);
        }
      });
    } else if (_selectedRoomDrawingTool == 'polygon') {
      // For polygon drawing, show preview line to current position
      setState(() {
        if (_currentRoomPolygonPoints.isNotEmpty) {
          _currentStroke = [..._currentRoomPolygonPoints, position];
        }
      });
    }
  }

  void _finishRoomDrawing(Offset position) {
    if (_selectedRoomDrawingTool == 'rectangle') {
      _finishRectangleRoom(position);
    } else if (_selectedRoomDrawingTool == 'polygon') {
      // For polygon, each tap adds a point - finish is handled separately
      setState(() {
        _currentRoomPolygonPoints.add(position);
      });
    }
  }

  void _finishRectangleRoom(Offset position) {
    if (_roomCorners.isEmpty) return;
    
    final startPoint = _roomCorners[0];
    
    // Create rectangle from two opposite corners
    final shapePoints = [
      startPoint,
      Offset(position.dx, startPoint.dy), // Top right
      position, // Bottom right
      Offset(startPoint.dx, position.dy), // Bottom left
      startPoint, // Close the shape
    ];
    
    _createRoomWithBackend(shapePoints, 'rectangle');
  }

  void _finishPolygonRoom() {
    if (_currentRoomPolygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Polygon needs at least 3 points')),
      );
      return;
    }
    
    // Close the polygon
    final polygonPoints = [..._currentRoomPolygonPoints, _currentRoomPolygonPoints.first];
    
    _createRoomWithBackend(polygonPoints.cast<Offset>(), 'polygon');
  }

  void _finishPolygonDrawing(String tool) {
    if (_currentPolygonPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Polygon needs at least 3 points')),
      );
      return;
    }
    
    // Close the polygon and create annotation
    final polygonPoints = [..._currentPolygonPoints, _currentPolygonPoints.first];
    final center = _calculateShapeCenter(polygonPoints);
    
    final annotation = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'tool': tool,
      'color': _currentDrawingColor.value,
      'strokeWidth': _strokeWidth,
      'points': polygonPoints.map((point) => {'x': point.dx, 'y': point.dy}).toList(),
      'timestamp': DateTime.now().toIso8601String(),
      'drawingMode': 'polygon',
      // Add room-like data for MAMAD (since MAMAD is essentially a room)
      if (tool == 'mamad') 'roomData': {
        'shape': 'polygon',
        'area': _calculateShapeArea(polygonPoints),
        'center': {'x': center.dx, 'y': center.dy},
        'defaultName': 'MAMAD ${_getUserAnnotationCount('mamad') + 1}',
        'description': 'Protected room (MAMAD)',
        'isUserDrawn': true,
        'roomType': 'MAMAD',
      },
    };
    
    setState(() {
      _userAnnotations.add(annotation);
      _currentPolygonPoints.clear();
      _currentStroke = [];
      _isDrawingRoom = false;
      _hasUnsavedAnnotations = true;
    });
    
    print('🎨 Enhanced $tool polygon completed with ${polygonPoints.length} points and area ${tool == 'mamad' ? (annotation['roomData'] as Map)['area'] : 'N/A'}');
  }

  Future<void> _createRoomWithBackend(List<Offset> shapePoints, String drawingTool) async {
    setState(() {
      _isCreatingRoomWithBackend = true;
    });

    try {
      // Prepare room data for backend (convert Offset objects to serializable maps)
      final existingRooms = _userAnnotations
          .where((a) => a['tool'] == 'room')
          .map((room) => {
            'id': room['id'],
            'tool': room['tool'],
            'timestamp': room['timestamp'],
            // Sanitize roomData to remove Offset objects
            'roomData': _sanitizeRoomData(room['roomData']),
            // Convert points from Offset objects to maps
            'points': (room['points'] as List<dynamic>)
                .map((point) => {
                  'x': (point as Map<String, dynamic>)['x'],
                  'y': (point as Map<String, dynamic>)['y'],
                })
                .toList(),
          })
          .toList();

      final roomData = {
        'drawing_tool': drawingTool,
        'room_type': _selectedRoomType,
        'room_name': '$_selectedRoomType ${_getUserAnnotationCount('room') + 1}',
        'existing_rooms': existingRooms,
      };

      if (drawingTool == 'rectangle' && shapePoints.length >= 4) {
        roomData['top_left'] = {
          'x': shapePoints[0].dx.toInt(),
          'y': shapePoints[0].dy.toInt(),
        };
        roomData['bottom_right'] = {
          'x': shapePoints[2].dx.toInt(),
          'y': shapePoints[2].dy.toInt(),
        };
      } else if (drawingTool == 'polygon') {
        roomData['points'] = shapePoints.map((point) => {
          'x': point.dx.toInt(),
          'y': point.dy.toInt(),
        }).toList();
      }

      // Debug: Print room data being sent
      print('🔍 Sending room data to backend:');
      print('   Drawing tool: ${roomData['drawing_tool']}');
      print('   Room type: ${roomData['room_type']}');
      print('   Room name: ${roomData['room_name']}');
      print('   Existing rooms count: ${(roomData['existing_rooms'] as List).length}');
      
      // Call backend API
      final requestBody = {
        'room_data': roomData,
        // Note: In a real app, you'd send the image as multipart/form-data
        // For now, we'll handle this in the backend with stored image references
      };
      
      print('🌐 Making HTTP request to backend...');
      
      // Try to encode JSON first to catch encoding errors
      String jsonBody;
      try {
        jsonBody = json.encode(requestBody);
        print('✅ JSON encoding successful');
      } catch (e) {
        print('❌ JSON encoding failed: $e');
        throw Exception('Failed to encode request data: $e');
      }
      
      final response = await http.post(
        Uri.parse('http://localhost:8000/api/create-room-annotation'),
        headers: {'Content-Type': 'application/json'},
        body: jsonBody,
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          final roomAnnotation = responseData['room_annotation'];
          
          // Convert backend room to local annotation format
          final localAnnotation = {
            'id': roomAnnotation['id'],
            'tool': 'room',
            'color': _currentDrawingColor.value,
            'strokeWidth': _strokeWidth,
            'points': (roomAnnotation['boundary']['points'] as List)
                .map((point) => {'x': point['x'].toDouble(), 'y': point['y'].toDouble()})
                .toList(),
            'timestamp': DateTime.now().toIso8601String(),
            'roomData': {
              'shape': drawingTool,
              'area': roomAnnotation['area_pixels'],
              'center': roomAnnotation['coordinates']['centroid'] ?? roomAnnotation['coordinates']['center'],
              'defaultName': roomAnnotation['name'],
              'description': '',
              'isUserDrawn': true,
              'backendCreated': true, // Mark as created by backend
            },
          };

          setState(() {
            _userAnnotations.add(localAnnotation);
            _roomCorners = [];
            _currentRoomPolygonPoints = [];
            _currentStroke = [];
            _isDrawingRoom = false;
            _hasUnsavedAnnotations = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${roomAnnotation['name']} created successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          print('🏠 Smart room created: ${roomAnnotation['name']} (${roomAnnotation['area_pixels']} px²)');
        } else {
          throw Exception(responseData['error'] ?? 'Unknown error');
        }
      } else {
        throw Exception('Backend error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error creating room with backend: $e');
      
      // Fallback to local creation
      _createRoomLocally(shapePoints, drawingTool);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Created room locally (backend unavailable)'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      setState(() {
        _isCreatingRoomWithBackend = false;
      });
    }
  }

  void _createRoomLocally(List<Offset> shapePoints, String drawingTool) {
    // Fallback to local room creation (similar to original method)
    final center = _calculateShapeCenter(shapePoints);
    final roomAnnotation = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'tool': 'room',
      'color': _currentDrawingColor.value,
      'strokeWidth': _strokeWidth,
      'points': shapePoints.map((point) => {'x': point.dx, 'y': point.dy}).toList(),
      'timestamp': DateTime.now().toIso8601String(),
      'roomData': {
        'shape': drawingTool,
        'area': _calculateShapeArea(shapePoints),
        'center': {'x': center.dx, 'y': center.dy}, // Convert Offset to map
        'defaultName': '$_selectedRoomType ${_getUserAnnotationCount('room') + 1}',
        'description': '',
        'isUserDrawn': true,
        'roomType': _selectedRoomType,
      },
    };
    
    setState(() {
      _userAnnotations.add(roomAnnotation);
      _roomCorners = [];
      _currentRoomPolygonPoints = [];
      _currentStroke = [];
      _isDrawingRoom = false;
      _hasUnsavedAnnotations = true;
    });
    
    print('🏠 Local room created: ${_selectedRoomType} with area ${(roomAnnotation['roomData'] as Map)['area']}');
  }

  List<Offset> _generateShapePreview(Offset start, Offset current) {
    if (_roomShape == 'rectangle') {
      return [
        start,
        Offset(current.dx, start.dy),
        current,
        Offset(start.dx, current.dy),
        start,
      ];
    } else {
      // Triangle preview
      final distance = (current - start).distance;
      final point1 = start;
      final point2 = Offset(
        start.dx + distance * 0.866,
        start.dy + distance * 0.5,
      );
      final point3 = Offset(
        start.dx + distance * 0.866,
        start.dy - distance * 0.5,
      );
      return [point1, point2, point3, point1];
    }
  }

  double _calculateShapeArea(List<Offset> points) {
    if (points.length < 3) return 0.0;
    
    // Use shoelace formula for polygon area
    double area = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      area += points[i].dx * points[i + 1].dy;
      area -= points[i + 1].dx * points[i].dy;
    }
    return (area / 2.0).abs();
  }

  // Helper method to sanitize roomData for JSON encoding
  Map<String, dynamic> _sanitizeRoomData(dynamic roomData) {
    if (roomData == null || roomData is! Map<String, dynamic>) {
      return {};
    }
    
    final sanitized = <String, dynamic>{};
    final original = roomData as Map<String, dynamic>;
    
    for (final entry in original.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is Offset) {
        // Convert Offset to serializable map
        sanitized[key] = {'x': value.dx, 'y': value.dy};
      } else if (value is Map<String, dynamic>) {
        // Recursively sanitize nested maps
        sanitized[key] = _sanitizeRoomData(value);
      } else if (value is List) {
        // Handle lists (though we shouldn't have Offset objects in lists here)
        sanitized[key] = value.map((item) {
          if (item is Offset) {
            return {'x': item.dx, 'y': item.dy};
          } else if (item is Map<String, dynamic>) {
            return _sanitizeRoomData(item);
          } else {
            return item;
          }
        }).toList();
      } else {
        // Keep primitive values as-is
        sanitized[key] = value;
      }
    }
    
    return sanitized;
  }

  Offset _calculateShapeCenter(List<Offset> points) {
    if (points.isEmpty) return Offset.zero;
    
    double x = 0, y = 0;
    for (final point in points) {
      x += point.dx;
      y += point.dy;
    }
    return Offset(x / points.length, y / points.length);
  }

  List<Map<String, dynamic>> _getUserDrawnRooms() {
    return _userAnnotations
        .where((annotation) => annotation['tool'] == 'room' || annotation['tool'] == 'mamad') // Include MAMAD as rooms
        .where((annotation) => annotation['roomData'] != null) // Filter out null roomData
        .map((annotation) => {
          'id': annotation['id'] ?? 'unknown',
          'defaultName': _getRoomDataValue(annotation['roomData'], 'defaultName', 'User Room ${_getUserAnnotationCount(annotation['tool']) + 1}'),
          'confidence': 1.0, // User-drawn rooms have 100% confidence
          'detectionMethod': 'user_drawn',
          'doors': <Map<String, dynamic>>[], // Empty for now
          'windows': <Map<String, dynamic>>[], // Empty for now
          'walls': <Map<String, dynamic>>[], // Empty for now
          'estimatedDimensions': <String, double>{},
          'boundaries': <String, dynamic>{},
          'description': _getRoomDataValue(annotation['roomData'], 'description', annotation['tool'] == 'mamad' ? 'Protected room (MAMAD)' : 'User-drawn room'),
          'roomData': annotation['roomData'],
          'isUserDrawn': true,
        })
        .toList();
  }

  List<Map<String, dynamic>> _getAllRooms() {
    final aiRooms = _result.detectedRooms.map((room) => {
      'id': room.roomId ?? 'unknown',
      'defaultName': room.defaultName ?? 'Unknown Room',
      'confidence': room.confidence ?? 0.0,
      'detectionMethod': room.detectionMethod ?? 'unknown',
      'doors': room.doors ?? [],
      'windows': room.windows ?? [],
      'walls': room.walls ?? [],
      'estimatedDimensions': room.estimatedDimensions ?? <String, double>{},
      'boundaries': room.boundaries ?? <String, dynamic>{},
      'description': room.description ?? 'No description available',
      'isUserDrawn': false,
    }).toList();
    
    final userRooms = _getUserDrawnRooms();
    
    return [...aiRooms, ...userRooms];
  }

  // Toggle edit mode for user rooms
  void _toggleUserRoomEdit(String roomId) {
    setState(() {
      if (_isEditingUserRoom && _editingUserRoomId == roomId) {
        // Save changes
        _saveUserRoomChanges(roomId);
        _isEditingUserRoom = false;
        _editingUserRoomId = null;
      } else {
        // Enter edit mode
        _isEditingUserRoom = true;
        _editingUserRoomId = roomId;
        _initializeUserRoomControllers(roomId);
      }
    });
  }

  // Initialize controllers for user room editing
  void _initializeUserRoomControllers(String roomId) {
    // Find the annotation for this room
    final annotation = _userAnnotations.firstWhere(
      (annotation) => annotation['id'] == roomId,
      orElse: () => <String, dynamic>{},
    );
    
    if (annotation.isNotEmpty && annotation['roomData'] != null) {
      final roomData = annotation['roomData'] as Map<String, dynamic>;
      final currentName = roomData['defaultName']?.toString() ?? 'User Room';
      final currentDesc = roomData['description']?.toString() ?? '';
      
      _userRoomNameControllers[roomId] = TextEditingController(text: currentName);
      _userRoomDescControllers[roomId] = TextEditingController(text: currentDesc);
    }
  }

  // Save user room changes
  void _saveUserRoomChanges(String roomId) {
    final nameController = _userRoomNameControllers[roomId];
    final descController = _userRoomDescControllers[roomId];
    
    if (nameController != null || descController != null) {
      // Find and update the annotation
      for (int i = 0; i < _userAnnotations.length; i++) {
        if (_userAnnotations[i]['id'] == roomId) {
          final roomData = _userAnnotations[i]['roomData'] as Map<String, dynamic>? ?? {};
          
          if (nameController != null) {
            roomData['defaultName'] = nameController.text.trim().isNotEmpty 
                ? nameController.text.trim() 
                : 'User Room';
          }
          
          if (descController != null) {
            roomData['description'] = descController.text.trim();
          }
          
          _userAnnotations[i]['roomData'] = roomData;
          _hasUnsavedAnnotations = true;
          break;
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room details updated!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Build user room name field
  Widget _buildUserRoomNameField(Map<String, dynamic> room) {
    final roomId = room['id'] as String;
    final isEditing = _isEditingUserRoom && _editingUserRoomId == roomId;
    
    if (isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Room Name:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.green[800],
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _userRoomNameControllers[roomId],
            decoration: InputDecoration(
              hintText: 'Enter room name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.green.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.green.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.green),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      );
    } else {
      return _buildUserRoomDetail(
        'Room Name', 
        room['defaultName'] as String? ?? 'User Room', 
        Icons.home_outlined,
      );
    }
  }

  // Build user room description field
  Widget _buildUserRoomDescriptionField(Map<String, dynamic> room) {
    final roomId = room['id'] as String;
    final isEditing = _isEditingUserRoom && _editingUserRoomId == roomId;
    final roomData = room['roomData'] as Map<String, dynamic>? ?? {};
    final currentDescription = roomData['description']?.toString() ?? '';
    
    if (isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Description:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.green[800],
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _userRoomDescControllers[roomId],
            decoration: InputDecoration(
              hintText: 'Add a description for this room...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.green.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.green.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.green),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(fontSize: 14),
            maxLines: 3,
            minLines: 2,
          ),
        ],
      );
    } else {
      // Show description or "Add description" button
      if (currentDescription.isNotEmpty) {
        return _buildUserRoomDetail(
          'Description', 
          currentDescription, 
          Icons.description_outlined,
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.add_comment_outlined, size: 14, color: Colors.green[600]),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _toggleUserRoomEdit(roomId),
                child: Text(
                  'Add description',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[600],
                    decoration: TextDecoration.underline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  // Helper method to safely get values from roomData
  String _getRoomDataValue(dynamic roomData, String key, String defaultValue) {
    if (roomData == null) return defaultValue;
    if (roomData is! Map<String, dynamic>) return defaultValue;
    return roomData[key]?.toString() ?? defaultValue;
  }

  // Helper method to build user room details safely
  List<Widget> _buildUserRoomDetails(dynamic roomData) {
    if (roomData == null || roomData is! Map<String, dynamic>) {
      return [
        _buildUserRoomDetail('Shape', 'Unknown', Icons.crop_free),
        _buildUserRoomDetail('Estimated Area', 'Unknown', Icons.area_chart),
      ];
    }

    final roomDataMap = roomData as Map<String, dynamic>;
    final widgets = <Widget>[];
    
    // Shape
    final shape = roomDataMap['shape']?.toString() ?? 'rectangle';
    widgets.add(_buildUserRoomDetail('Shape', shape, Icons.crop_free));
    
    // Area
    final area = roomDataMap['area'];
    if (area != null && area is num) {
      widgets.add(_buildUserRoomDetail('Estimated Area', '${area.toStringAsFixed(1)} px²', Icons.area_chart));
    } else {
      widgets.add(_buildUserRoomDetail('Estimated Area', 'Unknown', Icons.area_chart));
    }
    
    // Center position
    final center = roomDataMap['center'];
    if (center != null) {
      String centerText;
      if (center is Offset) {
        centerText = '(${center.dx.toStringAsFixed(0)}, ${center.dy.toStringAsFixed(0)})';
      } else if (center is Map<String, dynamic>) {
        final x = center['x']?.toDouble() ?? 0.0;
        final y = center['y']?.toDouble() ?? 0.0;
        centerText = '(${x.toStringAsFixed(0)}, ${y.toStringAsFixed(0)})';
      } else {
        centerText = center.toString();
      }
      widgets.add(_buildUserRoomDetail('Center Position', centerText, Icons.center_focus_strong));
    }
    
    return widgets;
  }

  Widget _buildUserRoomDetail(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.green[600]),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.green[800]),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Floating control methods
  Widget _buildFloatingEnhancedControls() {
    final color = _currentDrawingTool == 'stairway' ? Colors.purple : const Color(0xFFFF1493);
    
    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _currentDrawingTool == 'stairway' ? Icons.stairs : Icons.security,
                  color: color,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_currentDrawingTool == 'stairway' ? 'Stairway' : 'MAMAD'} Drawing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showDrawingControls = false;
                    });
                  },
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Drawing tool selector
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDrawingModeButton('rectangle', Icons.rectangle_outlined, 'Rectangle'),
                const SizedBox(width: 8),
                _buildDrawingModeButton('polygon', Icons.pentagon_outlined, 'Polygon'),
              ],
            ),
            const SizedBox(height: 8),
            // Finish polygon button (only for polygon tool)
            if (_selectedDrawingTool == 'polygon' && _currentPolygonPoints.isNotEmpty) ...[
              ElevatedButton(
                onPressed: () => _finishPolygonDrawing(_currentDrawingTool),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(80, 32),
                ),
                child: const Text(
                  'Finish Polygon',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingRoomControls() {
    final color = Colors.blue.shade600;
    
    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.meeting_room, color: color, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Room Drawing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showRoomTypeSelector = false;
                    });
                  },
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Room type selector
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home_outlined, size: 14, color: color),
                const SizedBox(width: 4),
                DropdownButton<String>(
                  value: _selectedRoomType,
                  onChanged: (value) {
                    setState(() {
                      _selectedRoomType = value!;
                    });
                  },
                  style: TextStyle(fontSize: 12, color: color),
                  underline: Container(),
                  items: _availableRoomTypes.map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type, style: const TextStyle(fontSize: 12)),
                  )).toList(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Drawing tool selector
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRoomDrawingToolButton('rectangle', Icons.rectangle_outlined, 'Rectangle'),
                const SizedBox(width: 8),
                _buildRoomDrawingToolButton('polygon', Icons.pentagon_outlined, 'Polygon'),
              ],
            ),
            const SizedBox(height: 8),
            // Finish polygon button (only for polygon tool)
            if (_selectedRoomDrawingTool == 'polygon' && _currentRoomPolygonPoints.isNotEmpty) ...[
              ElevatedButton(
                onPressed: _finishPolygonRoom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(80, 32),
                ),
                child: const Text(
                  'Finish Polygon',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===== HOUSE BOUNDARY METHODS =====
  
  void _clearHouseBoundary() {
    setState(() {
      _houseBoundaryPoints.clear();
      _hasHouseBoundary = false;
      _isDrawingHouseBoundary = false;
      _isEditingHouseBoundary = false;
    });
  }

  void _finishHouseBoundary() {
    if (_houseBoundaryPoints.length >= 3) {
      setState(() {
        _hasHouseBoundary = true;
        _isDrawingHouseBoundary = false;
        _isEditingHouseBoundary = false;
      });
      
      // Calculate boundary information
      final area = _calculatePolygonArea(_houseBoundaryPoints);
      final perimeter = _calculatePolygonPerimeter(_houseBoundaryPoints);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'House boundary completed! Area: ${area.toStringAsFixed(1)} px², Perimeter: ${perimeter.toStringAsFixed(1)} px',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _editHouseBoundary() {
    setState(() {
      _isDrawingHouseBoundary = true;
      _isEditingHouseBoundary = true;
    });
  }

  Widget _buildHouseBoundaryImageWidget(String base64Image) {
    Uint8List imageBytes = _decodeBase64Image(base64Image);
    if (imageBytes.isEmpty) {
      return Container(
        height: 200,
        color: Colors.grey[300],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text('Failed to load image', style: TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            if (!_hasHouseBoundary || _isDrawingHouseBoundary) {
              final RenderBox renderBox = context.findRenderObject() as RenderBox;
              final localPosition = renderBox.globalToLocal(details.globalPosition);
              final adjustedPosition = _adjustCoordinatesForImage(localPosition, constraints);
              
              setState(() {
                if (!_isDrawingHouseBoundary) {
                  _isDrawingHouseBoundary = true;
                  _houseBoundaryPoints.clear();
                }
                _houseBoundaryPoints.add(adjustedPosition);
              });
            }
          },
          child: Stack(
            children: [
              Image.memory(
                imageBytes,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
              // Custom painter for house boundary
              Positioned.fill(
                child: CustomPaint(
                  painter: HouseBoundaryPainter(
                    boundaryPoints: _houseBoundaryPoints,
                    isDrawing: _isDrawingHouseBoundary,
                    hasCompletedBoundary: _hasHouseBoundary,
                  ),
                ),
              ),
              // Status indicator
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _hasHouseBoundary
                        ? Colors.green.withOpacity(0.9)
                        : _isDrawingHouseBoundary
                            ? Colors.orange.withOpacity(0.9)
                            : Colors.blue.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hasHouseBoundary
                            ? Icons.check_circle
                            : _isDrawingHouseBoundary
                                ? Icons.edit
                                : Icons.home_outlined,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _hasHouseBoundary
                            ? 'Boundary Complete'
                            : _isDrawingHouseBoundary
                                ? 'Drawing Boundary'
                                : 'Original Image',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Calculate polygon area using the shoelace formula
  double _calculatePolygonArea(List<Offset> points) {
    if (points.length < 3) return 0.0;
    
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      int j = (i + 1) % points.length;
      area += points[i].dx * points[j].dy;
      area -= points[j].dx * points[i].dy;
    }
    return (area / 2.0).abs();
  }

  // Calculate polygon perimeter
  double _calculatePolygonPerimeter(List<Offset> points) {
    if (points.length < 2) return 0.0;
    
    double perimeter = 0.0;
    for (int i = 0; i < points.length; i++) {
      int j = (i + 1) % points.length;
      perimeter += (points[i] - points[j]).distance;
    }
    return perimeter;
  }

  // Build material selection widget with multiple choice and percentage input
  Widget _buildMaterialSelection() {
    final totalPercentage = _selectedHouseMaterials.values.fold(0.0, (a, b) => a + b);
    
    return Column(
      children: [
        // Progress indicator for total percentage - compact
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // Reduced padding
          decoration: BoxDecoration(
            color: totalPercentage == 100 
                ? Colors.green.withOpacity(0.1) 
                : totalPercentage > 100 
                    ? Colors.red.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6), // Smaller radius
            border: Border.all(
              color: totalPercentage == 100 
                  ? Colors.green
                  : totalPercentage > 100 
                      ? Colors.red
                      : Colors.orange,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                totalPercentage == 100 ? Icons.check_circle : Icons.pie_chart,
                size: 14, // Smaller icon
                color: totalPercentage == 100 
                    ? Colors.green[700]
                    : totalPercentage > 100 
                        ? Colors.red[700]
                        : Colors.orange[700],
              ),
              const SizedBox(width: 6), // Reduced spacing
              Text(
                'Total: ${totalPercentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 11, // Smaller text
                  fontWeight: FontWeight.bold,
                  color: totalPercentage == 100 
                      ? Colors.green[800]
                      : totalPercentage > 100 
                          ? Colors.red[800]
                          : Colors.orange[800],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: LinearProgressIndicator(
                  value: (totalPercentage / 100).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation(
                    totalPercentage == 100 
                        ? Colors.green
                        : totalPercentage > 100 
                            ? Colors.red
                            : Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                totalPercentage == 100 
                    ? 'Complete'
                    : totalPercentage > 100 
                        ? 'Over 100%'
                        : '${(100 - totalPercentage).toStringAsFixed(0)}% left', // Shorter text
                style: TextStyle(
                  fontSize: 9, // Smaller text
                  color: totalPercentage == 100 
                      ? Colors.green[700]
                      : totalPercentage > 100 
                          ? Colors.red[700]
                          : Colors.orange[700],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8), // Reduced spacing
        
        // Material selection list with percentage inputs - compact version
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180), // Reduced height
          child: ListView.builder(
            shrinkWrap: true,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _israeliHouseMaterials.length,
            itemBuilder: (context, index) {
              final material = _israeliHouseMaterials[index];
              final materialName = material['name'] as String;
              final isSelected = _selectedHouseMaterials.containsKey(materialName);
              
              // Initialize controller if not exists
              if (!_percentageControllers.containsKey(materialName)) {
                _percentageControllers[materialName] = TextEditingController();
              }
              
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 1), // Reduced margin
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(6), // Smaller radius
                  border: Border.all(
                    color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // Reduced padding
                  child: Row(
                    children: [
                      // Checkbox - smaller
                      GestureDetector(
                        onTap: () => _toggleMaterial(materialName),
                        child: Container(
                          width: 16, // Smaller checkbox
                          height: 16,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue : Colors.transparent,
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.grey,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: isSelected
                              ? Icon(Icons.check, size: 12, color: Colors.white)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6), // Reduced spacing
                      
                      // Material icon - smaller
                      Icon(
                        material['icon'] as IconData,
                        color: isSelected ? Colors.blue[700] : Colors.grey[600],
                        size: 14, // Smaller icon
                      ),
                      const SizedBox(width: 6),
                      
                      // Material info - single line
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _toggleMaterial(materialName),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 10, // Smaller text
                                color: isSelected ? Colors.blue[800] : Colors.grey[800],
                              ),
                              children: [
                                TextSpan(
                                  text: material['name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text: ' (${material['hebrew']})',
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: isSelected ? Colors.blue[600] : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      
                      // Percentage input - smaller
                      if (isSelected) ...[
                        Container(
                          width: 50, // Smaller width
                          height: 28, // Smaller height
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: TextField(
                            controller: _percentageControllers[materialName],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10), // Smaller text
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 10),
                              suffix: Text('%', style: TextStyle(fontSize: 8, color: Colors.grey[600])),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                            ),
                            onChanged: (value) => _updatePercentage(materialName, value),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(width: 50), // Smaller placeholder space
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        // Selected materials summary - compact
        if (_selectedHouseMaterials.isNotEmpty) ...[
          const SizedBox(height: 8), // Reduced spacing
          Container(
            padding: const EdgeInsets.all(8), // Reduced padding
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6), // Smaller radius
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.summarize, size: 14, color: Colors.blue[700]), // Smaller icon
                    const SizedBox(width: 6), // Reduced spacing
                    Text(
                      'Selected Materials (${_selectedHouseMaterials.length})', // Shorter title
                      style: TextStyle(
                        fontSize: 11, // Smaller text
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6), // Reduced spacing
                ..._selectedHouseMaterials.entries.map((entry) {
                  final material = _israeliHouseMaterials.firstWhere(
                    (m) => m['name'] == entry.key,
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1), // Reduced spacing
                    child: Row(
                      children: [
                        Icon(material['icon'] as IconData, size: 10, color: Colors.blue[600]), // Smaller icon
                        const SizedBox(width: 4), // Reduced spacing
                        Expanded(
                          child: Text(
                            '${entry.key} (${material['hebrew']})',
                            style: TextStyle(fontSize: 9, color: Colors.blue[700]), // Smaller text
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), // Reduced padding
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6), // Smaller radius
                          ),
                          child: Text(
                            '${entry.value.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 9, // Smaller text
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Toggle material selection
  void _toggleMaterial(String materialName) {
    setState(() {
      if (_selectedHouseMaterials.containsKey(materialName)) {
        _selectedHouseMaterials.remove(materialName);
        _percentageControllers[materialName]?.clear();
      } else {
        _selectedHouseMaterials[materialName] = 0.0;
      }
    });
  }

  // Update percentage for a material
  void _updatePercentage(String materialName, String value) {
    final percentage = double.tryParse(value) ?? 0.0;
    setState(() {
      _selectedHouseMaterials[materialName] = percentage.clamp(0.0, 100.0);
    });
  }

  // Add new method for wall thickness analysis section
  Widget _buildWallThicknessAnalysisSection(Map<String, dynamic> room) {
    final roomId = room['roomId']?.toString() ?? room['id']?.toString() ?? '';
    final wallThicknessData = _wallThicknessResults[roomId];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.architecture, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Text(
              'Wall Thickness Analysis',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Wall thickness analysis card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.camera_alt, color: Colors.deepPurple[600], size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Measure Wall Thickness',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (wallThicknessData != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                            const SizedBox(width: 4),
                            Text(
                              'Analyzed',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                
                const Text(
                  'Take a photo of a door or window frame to measure wall thickness using AI depth analysis.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _analyzeWallThickness(roomId, ImageSource.camera),
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Camera', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _analyzeWallThickness(roomId, ImageSource.gallery),
                        icon: const Icon(Icons.photo_library, size: 16),
                        label: const Text('Browse', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepPurple,
                          side: BorderSide(color: Colors.deepPurple),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _manualWallThicknessInput(roomId),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Manual', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: BorderSide(color: Colors.orange),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Show results if available
                if (wallThicknessData != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.analytics, color: Colors.green[700], size: 16),
                            const SizedBox(width: 8),
                            const Text(
                              'Analysis Results',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // Wall thickness result
                        Row(
                          children: [
                            const Text('Wall Thickness: ', style: TextStyle(fontSize: 12)),
                            Text(
                              '${wallThicknessData['wall_thickness_cm']} cm',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                            if (wallThicknessData['calibration_method'] == 'manual_input') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.orange, width: 0.5),
                                ),
                                child: Text(
                                  'Manual',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        
                        // Confidence level
                        Row(
                          children: [
                            const Text('Confidence: ', style: TextStyle(fontSize: 12)),
                            Text(
                              '${(wallThicknessData['confidence'] * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _getConfidenceColor(wallThicknessData['confidence']),
                              ),
                            ),
                          ],
                        ),
                        
                        // Measurement points
                        Row(
                          children: [
                            const Text('Measurement Points: ', style: TextStyle(fontSize: 12)),
                            Text(
                              '${wallThicknessData['measurement_points']}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        
                        // Show depth visualization if available
                        if (wallThicknessData['depth_visualization'] != null) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _showDepthVisualization(wallThicknessData['depth_visualization']),
                            child: Container(
                              height: 100,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(wallThicknessData['depth_visualization'].split(',')[1]),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap to view full depth visualization',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Add these methods to the class
  Map<String, dynamic> _wallThicknessResults = {};
  bool _isAnalyzingWallThickness = false;
  
  // Add new variable for house-level wall thickness
  Map<String, dynamic> _houseWallThicknessResults = {};
  bool _isAnalyzingHouseWallThickness = false;

  Future<void> _analyzeWallThickness(String roomId, ImageSource source) async {
    print('🔍 [FLUTTER DEBUG] Starting wall thickness analysis for room: $roomId');
    
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    
    if (image == null) {
      print('🔍 [FLUTTER DEBUG] No image selected, returning');
      return;
    }
    
    print('🔍 [FLUTTER DEBUG] Image selected: ${image.path}, size: ${await image.length()} bytes');
    
    setState(() {
      _isAnalyzingWallThickness = true;
    });
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Analyzing wall thickness...'),
              const SizedBox(height: 8),
              Text(
                'Using AI depth analysis to measure wall thickness from door/window frame',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
      
      print('🔍 [FLUTTER DEBUG] Preparing HTTP request to: ${API_BASE_URL}/api/analyze-wall-thickness');
      
      // Prepare the request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${API_BASE_URL}/api/analyze-wall-thickness'),
      );
      
      // Add the image file
      final bytes = await image.readAsBytes();
      print('🔍 [FLUTTER DEBUG] Image bytes read: ${bytes.length} bytes');
      print('🔍 [FLUTTER DEBUG] Image path: ${image.path}');
      print('🔍 [FLUTTER DEBUG] Image name: ${image.name}');
      
      // Determine content type by examining file magic bytes (more reliable for web)
      String contentType = _detectImageType(bytes);
      String filename = 'wall_frame.jpg';
      
      // Try to get filename from image name if available
      if (image.name != null && image.name!.isNotEmpty) {
        filename = image.name!;
      }
      
      print('🔍 [FLUTTER DEBUG] Detected content type: $contentType');
      print('🔍 [FLUTTER DEBUG] Using filename: $filename');
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(contentType),
        ),
      );
      
      // Add room context
      request.fields['room_id'] = roomId;
      print('🔍 [FLUTTER DEBUG] Request fields: ${request.fields}');
      print('🔍 [FLUTTER DEBUG] Request files: ${request.files.length} file(s)');
      
      // Send request
      print('🔍 [FLUTTER DEBUG] Sending HTTP request...');
      final streamedResponse = await request.send();
      print('🔍 [FLUTTER DEBUG] Response received with status: ${streamedResponse.statusCode}');
      
      final response = await http.Response.fromStream(streamedResponse);
      print('🔍 [FLUTTER DEBUG] Response body length: ${response.body.length} characters');
      print('🔍 [FLUTTER DEBUG] Response body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');
      
      // Close loading dialog
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (response.statusCode == 200) {
        print('🔍 [FLUTTER DEBUG] Success response - parsing JSON...');
        final responseData = json.decode(response.body);
        print('🔍 [FLUTTER DEBUG] Parsed response data: ${responseData.keys.toList()}');
        
        if (responseData['success'] == true) {
          print('🔍 [FLUTTER DEBUG] Analysis successful - thickness: ${responseData['wall_thickness_cm']} cm');
          setState(() {
            _wallThicknessResults[roomId] = responseData;
          });
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Wall thickness analyzed: ${responseData['wall_thickness_cm']} cm',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          print('🔍 [FLUTTER DEBUG] Analysis failed - response success: false');
          throw Exception(responseData['error'] ?? 'Analysis failed');
        }
      } else {
        print('🔍 [FLUTTER DEBUG] HTTP error - status: ${response.statusCode}, body: ${response.body}');
        throw Exception('Server error: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      print('🔍 [FLUTTER DEBUG] Exception caught: $e');
      print('🔍 [FLUTTER DEBUG] Exception type: ${e.runtimeType}');
      
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wall thickness analysis failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      print('🔍 [FLUTTER DEBUG] Analysis completed, setting state to not analyzing');
      setState(() {
        _isAnalyzingWallThickness = false;
      });
    }
  }

  String _detectImageType(Uint8List bytes) {
    // Check magic bytes to determine image type
    if (bytes.length < 4) return 'image/jpeg'; // Default fallback
    
    // PNG: 89 50 4E 47
    if (bytes.length >= 4 && 
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'image/png';
    }
    
    // JPEG: FF D8 FF
    if (bytes.length >= 3 && 
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    
    // GIF: 47 49 46 38
    if (bytes.length >= 4 && 
        bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
      return 'image/gif';
    }
    
    // WebP: 52 49 46 46 (RIFF) ... 57 45 42 50 (WEBP)
    if (bytes.length >= 12 && 
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
    
    // Default to JPEG if we can't detect
    return 'image/jpeg';
  }

  void _showDepthVisualization(String base64Image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Depth Visualization'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.memory(
                  base64Decode(base64Image.split(',')[1]),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manualWallThicknessInput(String roomId) async {
    final TextEditingController thicknessController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Wall Thickness'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the wall thickness for this room in centimeters:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: thicknessController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Wall Thickness',
                suffixText: 'cm',
                hintText: 'e.g., 20.5',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.orange[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Typical interior walls: 10-15cm\nExterior walls: 15-30cm',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final thicknessText = thicknessController.text.trim();
              if (thicknessText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a wall thickness value'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              
              final thickness = double.tryParse(thicknessText);
              if (thickness == null || thickness <= 0 || thickness > 100) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid thickness between 0 and 100 cm'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              // Create manual input result data
              final manualResult = {
                'success': true,
                'wall_thickness_cm': thickness,
                'confidence': 1.0, // Manual input has 100% confidence
                'measurement_points': 1,
                'calibration_method': 'manual_input',
                'quality': {
                  'measurement_points': 1,
                  'input_method': 'manual',
                },
                'depth_visualization': null,
              };
              
              setState(() {
                _wallThicknessResults[roomId] = manualResult;
              });
              
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Manual wall thickness saved: ${thickness.toStringAsFixed(1)} cm'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualHouseWallThicknessInput() async {
    final TextEditingController thicknessController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual House Wall Thickness'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the thickness of your house\'s outer perimeter walls in centimeters:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: thicknessController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Outer Wall Thickness',
                suffixText: 'cm',
                hintText: 'e.g., 25.0',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.deepPurple[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Typical house exterior walls:\n• Concrete blocks: 20-25cm\n• Brick walls: 15-20cm\n• Stone walls: 25-35cm',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.deepPurple[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final thicknessText = thicknessController.text.trim();
              if (thicknessText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a wall thickness value'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              
              final thickness = double.tryParse(thicknessText);
              if (thickness == null || thickness <= 0 || thickness > 100) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid thickness between 0 and 100 cm'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              // Create manual input result data
              final manualResult = {
                'success': true,
                'wall_thickness_cm': thickness,
                'confidence': 1.0, // Manual input has 100% confidence
                'measurement_points': 1,
                'calibration_method': 'manual_input',
                'quality': {
                  'measurement_points': 1,
                  'input_method': 'manual',
                },
                'depth_visualization': null,
              };
              
              setState(() {
                _houseWallThicknessResults['house_perimeter'] = manualResult;
              });
              
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Manual house wall thickness saved: ${thickness.toStringAsFixed(1)} cm'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeHouseWallThickness(ImageSource source) async {
    print('🔍 [FLUTTER DEBUG] Starting house wall thickness analysis');
    
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    
    if (image == null) {
      print('🔍 [FLUTTER DEBUG] No image selected, returning');
      return;
    }
    
    print('🔍 [FLUTTER DEBUG] Image selected: ${image.path}, size: ${await image.length()} bytes');
    
    setState(() {
      _isAnalyzingHouseWallThickness = true;
    });
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Analyzing house wall thickness...'),
              const SizedBox(height: 8),
              Text(
                'Using AI depth analysis to measure outer perimeter wall thickness',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
      
      print('🔍 [FLUTTER DEBUG] Preparing HTTP request to: ${API_BASE_URL}/api/analyze-wall-thickness');
      
      // Prepare the request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${API_BASE_URL}/api/analyze-wall-thickness'),
      );
      
      // Add the image file
      final bytes = await image.readAsBytes();
      print('🔍 [FLUTTER DEBUG] Image bytes read: ${bytes.length} bytes');
      
      String contentType = _detectImageType(bytes);
      String filename = 'house_wall_frame.jpg';
      
      if (image.name != null && image.name!.isNotEmpty) {
        filename = image.name!;
      }
      
      print('🔍 [FLUTTER DEBUG] Detected content type: $contentType');
      print('🔍 [FLUTTER DEBUG] Using filename: $filename');
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(contentType),
        ),
      );
      
      // Add context for house wall analysis
      request.fields['room_id'] = 'house_perimeter';
      request.fields['analysis_type'] = 'house_wall';
      print('🔍 [FLUTTER DEBUG] Request fields: ${request.fields}');
      
      // Send request
      print('🔍 [FLUTTER DEBUG] Sending HTTP request...');
      final streamedResponse = await request.send();
      print('🔍 [FLUTTER DEBUG] Response received with status: ${streamedResponse.statusCode}');
      
      final response = await http.Response.fromStream(streamedResponse);
      print('🔍 [FLUTTER DEBUG] Response body length: ${response.body.length} characters');
      
      // Close loading dialog
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (response.statusCode == 200) {
        print('🔍 [FLUTTER DEBUG] Success response - parsing JSON...');
        final responseData = json.decode(response.body);
        print('🔍 [FLUTTER DEBUG] Parsed response data: ${responseData.keys.toList()}');
        
        if (responseData['success'] == true) {
          print('🔍 [FLUTTER DEBUG] House wall analysis successful - thickness: ${responseData['wall_thickness_cm']} cm');
          setState(() {
            _houseWallThicknessResults['house_perimeter'] = responseData;
          });
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'House wall thickness measured: ${responseData['wall_thickness_cm']} cm',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          print('🔍 [FLUTTER DEBUG] House wall analysis failed - response success: false');
          throw Exception(responseData['error'] ?? 'Analysis failed');
        }
      } else {
        print('🔍 [FLUTTER DEBUG] HTTP error - status: ${response.statusCode}, body: ${response.body}');
        throw Exception('Server error: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      print('🔍 [FLUTTER DEBUG] Exception caught: $e');
      
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('House wall thickness analysis failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      print('🔍 [FLUTTER DEBUG] House wall analysis completed, setting state to not analyzing');
      setState(() {
        _isAnalyzingHouseWallThickness = false;
      });
    }
  }

  Widget _buildHouseWallThicknessSection() {
    final wallThicknessData = _houseWallThicknessResults['house_perimeter'];
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.camera_enhance, color: Colors.deepPurple[600], size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Measure Outer Wall Thickness',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (wallThicknessData != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text(
                          'Measured',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            
            const Text(
              'Take a photo of an exterior door frame or window frame to measure the thickness of your house\'s outer walls.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            
            const SizedBox(height: 12),
            
                         // Action buttons
             Row(
               children: [
                 Expanded(
                   child: ElevatedButton.icon(
                     onPressed: _isAnalyzingHouseWallThickness 
                         ? null 
                         : () => _analyzeHouseWallThickness(ImageSource.camera),
                     icon: _isAnalyzingHouseWallThickness 
                         ? SizedBox(
                             width: 14,
                             height: 14,
                             child: CircularProgressIndicator(
                               strokeWidth: 2,
                               valueColor: AlwaysStoppedAnimation(Colors.white),
                             ),
                           )
                         : const Icon(Icons.camera_alt, size: 16),
                     label: Text(
                       _isAnalyzingHouseWallThickness ? 'Analyzing...' : 'Camera',
                       style: const TextStyle(fontSize: 12),
                     ),
                     style: ElevatedButton.styleFrom(
                       backgroundColor: Colors.deepPurple,
                       foregroundColor: Colors.white,
                       shape: RoundedRectangleBorder(
                         borderRadius: BorderRadius.circular(8),
                       ),
                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                     ),
                   ),
                 ),
                 const SizedBox(width: 6),
                 Expanded(
                   child: OutlinedButton.icon(
                     onPressed: _isAnalyzingHouseWallThickness 
                         ? null 
                         : () => _analyzeHouseWallThickness(ImageSource.gallery),
                     icon: const Icon(Icons.photo_library, size: 16),
                     label: const Text('Browse', style: TextStyle(fontSize: 12)),
                     style: OutlinedButton.styleFrom(
                       foregroundColor: Colors.deepPurple,
                       side: BorderSide(color: Colors.deepPurple),
                       shape: RoundedRectangleBorder(
                         borderRadius: BorderRadius.circular(8),
                       ),
                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                     ),
                   ),
                 ),
                 const SizedBox(width: 6),
                 Expanded(
                   child: OutlinedButton.icon(
                     onPressed: _isAnalyzingHouseWallThickness 
                         ? null 
                         : () => _manualHouseWallThicknessInput(),
                     icon: const Icon(Icons.edit, size: 16),
                     label: const Text('Manual', style: TextStyle(fontSize: 12)),
                     style: OutlinedButton.styleFrom(
                       foregroundColor: Colors.orange,
                       side: BorderSide(color: Colors.orange),
                       shape: RoundedRectangleBorder(
                         borderRadius: BorderRadius.circular(8),
                       ),
                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                     ),
                   ),
                 ),
               ],
             ),
            
            // Show results if available
            if (wallThicknessData != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, color: Colors.green[700], size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'House Wall Analysis Results',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Wall thickness result
                    Row(
                      children: [
                        const Text('Outer Wall Thickness: ', style: TextStyle(fontSize: 12)),
                        Text(
                          '${wallThicknessData['wall_thickness_cm']} cm',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                        if (wallThicknessData['calibration_method'] == 'manual_input') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange, width: 0.5),
                            ),
                            child: Text(
                              'Manual',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.orange[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    
                    // Confidence level
                    Row(
                      children: [
                        const Text('Confidence: ', style: TextStyle(fontSize: 12)),
                        Text(
                          '${(wallThicknessData['confidence'] * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _getConfidenceColor(wallThicknessData['confidence']),
                          ),
                        ),
                      ],
                    ),
                    
                    // Calibration method
                    Row(
                      children: [
                        const Text('Method: ', style: TextStyle(fontSize: 12)),
                        Text(
                          '${wallThicknessData['calibration_method']?.toString().replaceAll('_', ' ') ?? 'Unknown'}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    
                    // Show depth visualization if available
                    if (wallThicknessData['depth_visualization'] != null) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _showDepthVisualization(wallThicknessData['depth_visualization']),
                        child: Container(
                          height: 100,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(wallThicknessData['depth_visualization'].split(',')[1]),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap to view full depth visualization',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    
                    // Additional tip for house walls
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_outline, size: 14, color: Colors.blue[600]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'This measurement represents the typical thickness of your house\'s outer perimeter walls.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Custom painter for drawing house boundary
class HouseBoundaryPainter extends CustomPainter {
  final List<Offset> boundaryPoints;
  final bool isDrawing;
  final bool hasCompletedBoundary;

  HouseBoundaryPainter({
    required this.boundaryPoints,
    required this.isDrawing,
    required this.hasCompletedBoundary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (boundaryPoints.isEmpty) return;

    final paint = Paint()
      ..color = hasCompletedBoundary ? Colors.green : Colors.orange
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = (hasCompletedBoundary ? Colors.green : Colors.orange).withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final pointPaint = Paint()
      ..color = hasCompletedBoundary ? Colors.green : Colors.orange
      ..style = PaintingStyle.fill;

    // Draw lines between points
    if (boundaryPoints.length > 1) {
      final path = Path();
      path.moveTo(boundaryPoints.first.dx, boundaryPoints.first.dy);
      
      for (int i = 1; i < boundaryPoints.length; i++) {
        path.lineTo(boundaryPoints[i].dx, boundaryPoints[i].dy);
      }
      
      // Close the path if boundary is complete
      if (hasCompletedBoundary) {
        path.close();
        canvas.drawPath(path, fillPaint);
      }
      
      canvas.drawPath(path, paint);
    }

    // Draw points as circles
    for (int i = 0; i < boundaryPoints.length; i++) {
      canvas.drawCircle(boundaryPoints[i], 6.0, pointPaint);
      
      // Draw point number
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          boundaryPoints[i].dx - textPainter.width / 2,
          boundaryPoints[i].dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

/// Custom painter for drawing annotations on images
class AnnotationPainter extends CustomPainter {
  final List<Map<String, dynamic>> annotations;
  final List<Offset> currentStroke;
  final Color strokeColor;
  final double strokeWidth;
  final bool isEraser;
  final List<Offset> polygonPoints;
  final bool isDrawingRoom;

  AnnotationPainter({
    required this.annotations,
    required this.currentStroke,
    required this.strokeColor,
    required this.strokeWidth,
    required this.isEraser,
    this.polygonPoints = const [],
    this.isDrawingRoom = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Debug: Print canvas size for coordinate debugging
    if (annotations.isNotEmpty) {
      print('🎨 AnnotationPainter canvas size: ${size.width} x ${size.height}');
      print('   Rendering ${annotations.length} annotations');
    }
    
    // Draw existing annotations
    for (final annotation in annotations) {
      final points = annotation['points'] as List<dynamic>;
      final color = Color(annotation['color'] as int);
      final width = annotation['strokeWidth'] as double;
      
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (points.length > 1) {
        final path = Path();
        final firstPoint = points.first as Map<String, dynamic>;
        final firstX = firstPoint['x'] as double;
        final firstY = firstPoint['y'] as double;
        
        // Debug: Print first point coordinates
        if (annotations.indexOf(annotation) == 0) {
          print('   First annotation starts at: ($firstX, $firstY)');
        }
        
        path.moveTo(firstX, firstY);

        for (int i = 1; i < points.length; i++) {
          final point = points[i] as Map<String, dynamic>;
          path.lineTo(
            point['x'] as double,
            point['y'] as double,
          );
        }

        canvas.drawPath(path, paint);
      }
    }

    // Draw current stroke (only if not eraser)
    if (!isEraser && currentStroke.length > 1) {
      final paint = Paint()
        ..color = strokeColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(currentStroke.first.dx, currentStroke.first.dy);

      for (int i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }

      canvas.drawPath(path, paint);
    }
    
    // Draw eraser cursor if eraser tool is selected and there's a current stroke point
    if (isEraser && currentStroke.isNotEmpty) {
      final eraserPosition = currentStroke.last;
      
      // Draw eraser circle outline
      final eraserPaint = Paint()
        ..color = Colors.red.withOpacity(0.5)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      
      canvas.drawCircle(eraserPosition, 20.0, eraserPaint);
      
      // Draw eraser center dot
      final centerPaint = Paint()
        ..color = Colors.red.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(eraserPosition, 3.0, centerPaint);
    }
    
    // Draw polygon points for room drawing
    if (isDrawingRoom && polygonPoints.isNotEmpty) {
      final pointPaint = Paint()
        ..color = Colors.blue.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      
      final linePaint = Paint()
        ..color = Colors.blue.withOpacity(0.6)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      
      // Draw lines between points
      if (polygonPoints.length > 1) {
        final path = Path();
        path.moveTo(polygonPoints.first.dx, polygonPoints.first.dy);
        
        for (int i = 1; i < polygonPoints.length; i++) {
          path.lineTo(polygonPoints[i].dx, polygonPoints[i].dy);
        }
        
        canvas.drawPath(path, linePaint);
      }
      
      // Draw points as circles
      for (int i = 0; i < polygonPoints.length; i++) {
        canvas.drawCircle(polygonPoints[i], 6.0, pointPaint);
        
        // Draw point number
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            polygonPoints[i].dx - textPainter.width / 2,
            polygonPoints[i].dy - textPainter.height / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
} 