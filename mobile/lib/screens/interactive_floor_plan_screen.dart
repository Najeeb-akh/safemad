import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'room_safety_assessment_screen.dart';
import 'enhanced_safety_heatmap_screen.dart';

class InteractiveFloorPlanScreen extends StatefulWidget {
  final File? imageFile;
  final Uint8List? webImage;
  
  const InteractiveFloorPlanScreen({
    Key? key,
    this.imageFile,
    this.webImage,
  }) : super(key: key);

  @override
  _InteractiveFloorPlanScreenState createState() => _InteractiveFloorPlanScreenState();
}

class _InteractiveFloorPlanScreenState extends State<InteractiveFloorPlanScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  List<Room> _rooms = [];
  bool _isDrawing = false;
  Room? _currentRoom;
  DrawingTool _selectedTool = DrawingTool.rectangle;
  String _selectedRoomType = 'Living Room';
  ui.Image? _floorPlanImage;
  Size _imageSize = Size.zero;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  Rect? _imageBounds;

  final List<String> _roomTypes = [
    'Living Room', 'Bedroom', 'Kitchen', 'Bathroom', 'Dining Room',
    'Office', 'Laundry', 'Storage', 'Garage', 'Hallway', 'Mamad', 'Staircases','Balcony','Other'
  ];

  final List<Color> _roomColors = [
    Colors.red.withOpacity(0.3),
    Colors.blue.withOpacity(0.3),
    Colors.green.withOpacity(0.3),
    Colors.orange.withOpacity(0.3),
    Colors.purple.withOpacity(0.3),
    Colors.teal.withOpacity(0.3),
    Colors.pink.withOpacity(0.3),
    Colors.brown.withOpacity(0.3),
    Colors.cyan.withOpacity(0.3),
    Colors.lime.withOpacity(0.3),
    Colors.amber.withOpacity(0.3),
  ];

  @override
  void initState() {
    super.initState();
    _loadFloorPlanImage();
  }

  Future<void> _loadFloorPlanImage() async {
    try {
      Uint8List? imageBytes;
      if (kIsWeb && widget.webImage != null) {
        imageBytes = widget.webImage!;
      } else if (widget.imageFile != null) {
        imageBytes = await widget.imageFile!.readAsBytes();
      }

      if (imageBytes != null) {
        final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        setState(() {
          _floorPlanImage = frameInfo.image;
          _imageSize = Size(
            frameInfo.image.width.toDouble(),
            frameInfo.image.height.toDouble()
          );
        });
      }
    } catch (e) {
      print('Error loading image: $e');
    }
  }

  Offset _transformToImageCoordinates(Offset canvasPosition) {
    if (_imageBounds == null || _imageSize == Size.zero) {
      return canvasPosition;
    }

    // Check if the tap is within the image bounds
    if (!_imageBounds!.contains(canvasPosition)) {
      return Offset(-1, -1); // Invalid position
    }

    // Transform from canvas coordinates to image coordinates
    final relativeX = (canvasPosition.dx - _imageBounds!.left) / _imageBounds!.width;
    final relativeY = (canvasPosition.dy - _imageBounds!.top) / _imageBounds!.height;

    return Offset(
      relativeX * _imageSize.width,
      relativeY * _imageSize.height,
    );
  }

  void _startDrawing(Offset localPosition) {
    final imagePosition = _transformToImageCoordinates(localPosition);
    
    // Debug print for web compatibility
    if (kIsWeb) {
      print('Canvas tap: $localPosition, Image bounds: $_imageBounds, Image pos: $imagePosition');
    }
    
    // Ignore taps outside the image
    if (imagePosition.dx < 0 || imagePosition.dy < 0) {
      if (kIsWeb) {
        print('Tap outside image bounds');
      }
      return;
    }

    if (_selectedTool == DrawingTool.rectangle) {
      setState(() {
        _isDrawing = true;
        _currentRoom = Room(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '$_selectedRoomType ${_rooms.length + 1}',
          type: _selectedRoomType,
          color: _roomColors[_rooms.length % _roomColors.length],
          boundary: RoomBoundary.rectangle(
            topLeft: imagePosition,
            bottomRight: imagePosition,
          ),
        );
      });
    } else if (_selectedTool == DrawingTool.polygon) {
      if (_currentRoom == null) {
        setState(() {
          _currentRoom = Room(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: '$_selectedRoomType ${_rooms.length + 1}',
            type: _selectedRoomType,
            color: _roomColors[_rooms.length % _roomColors.length],
            boundary: RoomBoundary.polygon([imagePosition]),
          );
        });
      } else {
        setState(() {
          _currentRoom!.boundary.points.add(imagePosition);
        });
      }
    }
  }

  void _updateDrawing(Offset localPosition) {
    if (_isDrawing && _currentRoom != null && _selectedTool == DrawingTool.rectangle) {
      final imagePosition = _transformToImageCoordinates(localPosition);
      
      // Only update if position is valid
      if (imagePosition.dx >= 0 && imagePosition.dy >= 0) {
        setState(() {
          _currentRoom!.boundary.bottomRight = imagePosition;
        });
      }
    }
  }

  void _endDrawing() {
    if (_selectedTool == DrawingTool.rectangle && _currentRoom != null) {
      setState(() {
        _isDrawing = false;
        _rooms.add(_currentRoom!);
        _currentRoom = null;
      });
    }
  }

  void _finishPolygon() {
    if (_currentRoom != null && _selectedTool == DrawingTool.polygon) {
      setState(() {
        _rooms.add(_currentRoom!);
        _currentRoom = null;
      });
    }
  }

  void _deleteRoom(String roomId) {
    setState(() {
      _rooms.removeWhere((room) => room.id == roomId);
    });
  }

  void _editRoom(Room room) {
    showDialog(
      context: context,
      builder: (context) => _RoomEditDialog(
        room: room,
        onSave: (updatedRoom) {
          setState(() {
            final index = _rooms.indexWhere((r) => r.id == room.id);
            if (index != -1) {
              _rooms[index] = updatedRoom;
            }
          });
        },
        roomTypes: _roomTypes,
      ),
    );
  }

  void _goToNextStep() {
    // For now, just show the room data - you can replace this with navigation to next screen
    _showRoomDataSummary();
  }

  void _showRoomDataSummary() {
    final roomData = _rooms.map((room) => room.toJson(_imageSize)).toList();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Room Data Summary'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: roomData.length,
            itemBuilder: (context, index) {
              final room = roomData[index];
              return Card(
                margin: const EdgeInsets.all(4),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${room['name']} (${room['type']})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('ID: ${room['id']}'),
                      Text('Position: ${room['placement']['position_description']}'),
                      Text('Size: ${room['size']['area_description']} (${room['size']['area_pixels'].toInt()} px²)'),
                      Text('Dimensions: ${room['size']['width_pixels'].toInt()} x ${room['size']['height_pixels'].toInt()} px'),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _proceedToSafetyAssessment();
            },
            child: const Text('Save & Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSafetyAssessmentOptions() async {
    // Show loading indicator for saving
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Saving floor plan...'),
          ],
        ),
      ),
    );

    final annotations = {
      'rooms': _rooms.map((room) => room.toJson(_imageSize)).toList(),
      'imageSize': {
        'width': _imageSize.width,
        'height': _imageSize.height,
      },
    };

    String annotationId = 'local_${DateTime.now().millisecondsSinceEpoch}'; // Fallback ID

    try {
      print('Attempting to save annotations to backend...');
      
      // Send to backend
      final response = await http.post(
        Uri.parse('http://localhost:8000/api/save-floor-plan-annotations'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(annotations),
      ).timeout(const Duration(seconds: 10));

      print('Backend response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        annotationId = responseData['annotation_id'];
        print('Successfully saved with ID: $annotationId');
      } else {
        print('Backend error: ${response.statusCode} - ${response.body}');
        throw Exception('Backend returned status ${response.statusCode}');
      }
    } catch (e) {
      print('Error saving to backend: $e');
      
      // Close loading dialog first
      Navigator.of(context).pop();
      
      // Show error but continue with local ID
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Backend Unavailable'),
          content: Text(
            'Could not save to server: $e\n\n'
            'Would you like to continue with offline mode?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue Offline'),
            ),
          ],
        ),
      );

      if (shouldContinue != true) {
        return; // User chose to cancel
      }
    }

    // Close loading dialog if still open
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // Show assessment type selection
    final roomData = _rooms.map((room) => room.toJson(_imageSize)).toList();
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
                  _navigateToEnhancedHeatmap(roomData, annotationId);
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
                  _navigateToTraditionalAssessment(roomData, annotationId);
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
  
  void _navigateToEnhancedHeatmap(List<Map<String, dynamic>> rooms, String annotationId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => EnhancedSafetyHeatmapScreen(
          rooms: rooms,
          architecturalElements: [], // Will be configured in the screen
          annotationId: annotationId,
        ),
      ),
    );
  }

  void _navigateToTraditionalAssessment(List<Map<String, dynamic>> rooms, String annotationId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => RoomSafetyAssessmentScreen(
          rooms: rooms,
          annotationId: annotationId,
        ),
      ),
    );
  }

  Future<void> _proceedToSafetyAssessment() async {
    // This method is kept for backward compatibility
    await _showSafetyAssessmentOptions();
  }

  Future<void> _saveAnnotations() async {
    final annotations = {
      'rooms': _rooms.map((room) => room.toJson(_imageSize)).toList(),
      'imageSize': {
        'width': _imageSize.width,
        'height': _imageSize.height,
      },
    };

    try {
      // Send to backend
      final response = await http.post(
        Uri.parse('http://localhost:8000/api/save-floor-plan-annotations'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(annotations),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Floor plan saved successfully!')),
        );
        // Here you could navigate to the next screen instead of popping
        Navigator.of(context).pop();
      } else {
        throw Exception('Failed to save annotations');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving floor plan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotate Floor Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _rooms.isNotEmpty ? _saveAnnotations : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Toolbar
              Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey[100],
                child: Row(
                  children: [
                    DropdownButton<String>(
                      value: _selectedRoomType,
                      onChanged: (value) {
                        setState(() {
                          _selectedRoomType = value!;
                        });
                      },
                      items: _roomTypes.map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      )).toList(),
                    ),
                    const SizedBox(width: 16),
                    ToggleButtons(
                      isSelected: [
                        _selectedTool == DrawingTool.rectangle,
                        _selectedTool == DrawingTool.polygon,
                      ],
                      onPressed: (index) {
                        setState(() {
                          _selectedTool = index == 0 ? DrawingTool.rectangle : DrawingTool.polygon;
                          _currentRoom = null;
                        });
                      },
                      children: const [
                        Icon(Icons.crop_square),
                        Icon(Icons.pentagon_outlined),
                      ],
                    ),
                    const SizedBox(width: 16),
                    if (_selectedTool == DrawingTool.polygon && _currentRoom != null)
                      ElevatedButton(
                        onPressed: _finishPolygon,
                        child: const Text('Finish'),
                      ),
                  ],
                ),
              ),
                                   // Canvas
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      key: _canvasKey,
                      onTapDown: (details) => _startDrawing(details.localPosition),
                      onPanUpdate: (details) => _updateDrawing(details.localPosition),
                      onPanEnd: (details) => _endDrawing(),
                      // Add support for web pointer events
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: CustomPaint(
                          painter: FloorPlanPainter(
                            floorPlanImage: _floorPlanImage,
                            rooms: _rooms,
                            currentRoom: _currentRoom,
                            imageSize: _imageSize,
                            onImageBoundsChanged: (bounds) {
                              _imageBounds = bounds;
                            },
                          ),
                          size: Size(constraints.maxWidth, constraints.maxHeight),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Room List
              Container(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    return Container(
                      width: 150,
                      margin: const EdgeInsets.all(4),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    color: room.color,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      room.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              Text(room.type),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 16),
                                    onPressed: () => _editRoom(room),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 16),
                                    onPressed: () => _deleteRoom(room.id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // Next Step Button (Bottom Left)
          if (_rooms.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              child: FloatingActionButton.extended(
                onPressed: _goToNextStep,
                heroTag: 'nextStepFAB',
                backgroundColor: Colors.green,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next Step'),
              ),
            ),
        ],
      ),
    );
  }
}

class FloorPlanPainter extends CustomPainter {
  final ui.Image? floorPlanImage;
  final List<Room> rooms;
  final Room? currentRoom;
  final Size imageSize;
  final Function(Rect)? onImageBoundsChanged;

  FloorPlanPainter({
    this.floorPlanImage,
    required this.rooms,
    this.currentRoom,
    required this.imageSize,
    this.onImageBoundsChanged,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background with light gray
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.grey[100]!,
    );
    
    // Draw floor plan image with proper aspect ratio
    if (floorPlanImage != null) {
      final paint = Paint();
      
      // Calculate aspect ratios
      final imageAspectRatio = imageSize.width / imageSize.height;
      final canvasAspectRatio = size.width / size.height;
      
      late Rect dst;
      
      if (imageAspectRatio > canvasAspectRatio) {
        // Image is wider than canvas - fit to width
        final scaledHeight = size.width / imageAspectRatio;
        final offsetY = (size.height - scaledHeight) / 2;
        dst = Rect.fromLTWH(0, offsetY, size.width, scaledHeight);
      } else {
        // Image is taller than canvas - fit to height
        final scaledWidth = size.height * imageAspectRatio;
        final offsetX = (size.width - scaledWidth) / 2;
        dst = Rect.fromLTWH(offsetX, 0, scaledWidth, size.height);
      }
      
      final src = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
      canvas.drawImageRect(floorPlanImage!, src, dst, paint);
      
      // Draw border around image for visual feedback
      canvas.drawRect(
        dst,
        Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      
      // Store the actual image bounds for coordinate transformation
      _imageBounds = dst;
      
      // Notify parent about image bounds
      if (onImageBoundsChanged != null) {
        onImageBoundsChanged!(dst);
      }
    }

    // Draw rooms
    for (final room in rooms) {
      _drawRoom(canvas, room, size);
    }

    // Draw current room being drawn
    if (currentRoom != null) {
      _drawRoom(canvas, currentRoom!, size);
    }
  }

  Rect? _imageBounds;
  
  Rect? get imageBounds => _imageBounds;

  void _drawRoom(Canvas canvas, Room room, Size canvasSize) {
    final paint = Paint()
      ..color = room.color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = room.color.withOpacity(1.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (room.boundary.type == BoundaryType.rectangle) {
      final rect = Rect.fromPoints(
        _scalePoint(room.boundary.topLeft!, canvasSize),
        _scalePoint(room.boundary.bottomRight!, canvasSize),
      );
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
    } else if (room.boundary.type == BoundaryType.polygon) {
      final path = Path();
      final scaledPoints = room.boundary.points
          .map((p) => _scalePoint(p, canvasSize))
          .toList();
      
      if (scaledPoints.isNotEmpty) {
        path.moveTo(scaledPoints.first.dx, scaledPoints.first.dy);
        for (int i = 1; i < scaledPoints.length; i++) {
          path.lineTo(scaledPoints[i].dx, scaledPoints[i].dy);
        }
        path.close();
        canvas.drawPath(path, paint);
        canvas.drawPath(path, borderPaint);
      }
    }
  }

  Offset _scalePoint(Offset point, Size canvasSize) {
    if (_imageBounds == null) {
      return point;
    }
    
    // Transform point from image coordinates to canvas coordinates
    final scaleX = _imageBounds!.width / imageSize.width;
    final scaleY = _imageBounds!.height / imageSize.height;
    
    return Offset(
      _imageBounds!.left + (point.dx * scaleX),
      _imageBounds!.top + (point.dy * scaleY),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _RoomEditDialog extends StatefulWidget {
  final Room room;
  final Function(Room) onSave;
  final List<String> roomTypes;

  const _RoomEditDialog({
    required this.room,
    required this.onSave,
    required this.roomTypes,
  });

  @override
  _RoomEditDialogState createState() => _RoomEditDialogState();
}

class _RoomEditDialogState extends State<_RoomEditDialog> {
  late TextEditingController _nameController;
  late String _selectedType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.room.name);
    _selectedType = widget.room.type;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Room'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Room Name'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedType,
            decoration: const InputDecoration(labelText: 'Room Type'),
            items: widget.roomTypes.map((type) => DropdownMenuItem(
              value: type,
              child: Text(type),
            )).toList(),
            onChanged: (value) {
              setState(() {
                _selectedType = value!;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final updatedRoom = Room(
              id: widget.room.id,
              name: _nameController.text,
              type: _selectedType,
              color: widget.room.color,
              boundary: widget.room.boundary,
            );
            widget.onSave(updatedRoom);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

enum DrawingTool { rectangle, polygon }

enum BoundaryType { rectangle, polygon }

class Room {
  final String id;
  final String name;
  final String type;
  final Color color;
  final RoomBoundary boundary;

  Room({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    required this.boundary,
  });

  Map<String, dynamic> toJson(Size planDimensions) {
    final placement = _calculatePlacement(planDimensions);
    final size = _calculateSize();
    
    return {
      'id': id,
      'name': name,
      'type': type,
      'color': color.value,
      'boundary': boundary.toJson(),
      'placement': placement,
      'size': size,
    };
  }

  Map<String, dynamic> _calculatePlacement(Size planDimensions) {
    if (boundary.type == BoundaryType.rectangle) {
      final centerX = (boundary.topLeft!.dx + boundary.bottomRight!.dx) / 2;
      final centerY = (boundary.topLeft!.dy + boundary.bottomRight!.dy) / 2;
      
      return {
        'center_x': centerX,
        'center_y': centerY,
        'relative_x': centerX / planDimensions.width,
        'relative_y': centerY / planDimensions.height,
        'position_description': _getPositionDescription(
          centerX / planDimensions.width, 
          centerY / planDimensions.height
        ),
      };
    } else if (boundary.type == BoundaryType.polygon && boundary.points.isNotEmpty) {
      // Calculate centroid of polygon
      double centerX = 0, centerY = 0;
      for (final point in boundary.points) {
        centerX += point.dx;
        centerY += point.dy;
      }
      centerX /= boundary.points.length;
      centerY /= boundary.points.length;
      
      return {
        'center_x': centerX,
        'center_y': centerY,
        'relative_x': centerX / planDimensions.width,
        'relative_y': centerY / planDimensions.height,
        'position_description': _getPositionDescription(
          centerX / planDimensions.width, 
          centerY / planDimensions.height
        ),
      };
    }
    
    return {
      'center_x': 0.0,
      'center_y': 0.0,
      'relative_x': 0.0,
      'relative_y': 0.0,
      'position_description': 'Unknown',
    };
  }

  Map<String, dynamic> _calculateSize() {
    double area = 0.0;
    double width = 0.0;
    double height = 0.0;
    
    if (boundary.type == BoundaryType.rectangle) {
      width = (boundary.bottomRight!.dx - boundary.topLeft!.dx).abs();
      height = (boundary.bottomRight!.dy - boundary.topLeft!.dy).abs();
      area = width * height;
    } else if (boundary.type == BoundaryType.polygon && boundary.points.length >= 3) {
      // Calculate polygon area using shoelace formula
      double sum = 0;
      for (int i = 0; i < boundary.points.length; i++) {
        int j = (i + 1) % boundary.points.length;
        sum += boundary.points[i].dx * boundary.points[j].dy;
        sum -= boundary.points[j].dx * boundary.points[i].dy;
      }
      area = sum.abs() / 2;
      
      // Calculate bounding box for width/height approximation
      double minX = boundary.points.first.dx;
      double maxX = boundary.points.first.dx;
      double minY = boundary.points.first.dy;
      double maxY = boundary.points.first.dy;
      
      for (final point in boundary.points) {
        minX = math.min(minX, point.dx);
        maxX = math.max(maxX, point.dx);
        minY = math.min(minY, point.dy);
        maxY = math.max(maxY, point.dy);
      }
      
      width = maxX - minX;
      height = maxY - minY;
    }
    
    return {
      'area_pixels': area,
      'width_pixels': width,
      'height_pixels': height,
      'area_description': _getAreaDescription(area),
    };
  }

  String _getPositionDescription(double relativeX, double relativeY) {
    String horizontal, vertical;
    
    if (relativeX < 0.33) {
      horizontal = 'Left';
    } else if (relativeX > 0.66) {
      horizontal = 'Right';
    } else {
      horizontal = 'Center';
    }
    
    if (relativeY < 0.33) {
      vertical = 'Top';
    } else if (relativeY > 0.66) {
      vertical = 'Bottom';
    } else {
      vertical = 'Middle';
    }
    
    if (horizontal == 'Center' && vertical == 'Middle') {
      return 'Center of plan';
    }
    
    return '$vertical $horizontal';
  }

  String _getAreaDescription(double area) {
    if (area < 5000) {
      return 'Small';
    } else if (area < 15000) {
      return 'Medium';
    } else if (area < 30000) {
      return 'Large';
    } else {
      return 'Very Large';
    }
  }
}

class RoomBoundary {
  final BoundaryType type;
  final List<Offset> points;
  Offset? topLeft;
  Offset? bottomRight;

  RoomBoundary.rectangle({
    required this.topLeft,
    required this.bottomRight,
  }) : type = BoundaryType.rectangle, points = [];

  RoomBoundary.polygon(this.points) : type = BoundaryType.polygon;

  Map<String, dynamic> toJson() {
    if (type == BoundaryType.rectangle) {
      return {
        'type': 'rectangle',
        'topLeft': {'x': topLeft!.dx, 'y': topLeft!.dy},
        'bottomRight': {'x': bottomRight!.dx, 'y': bottomRight!.dy},
      };
    } else {
      return {
        'type': 'polygon',
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      };
    }
  }
} 