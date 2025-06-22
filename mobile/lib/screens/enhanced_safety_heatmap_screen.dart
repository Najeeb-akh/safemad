import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import '../services/structured_safety_service.dart';

class EnhancedSafetyHeatmapScreen extends StatefulWidget {
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> architecturalElements;
  final String annotationId;
  final String? floorPlanImagePath;
  final Map<String, dynamic>? rawDetectionResult;
  final String? analysisId; // New parameter for structured data

  const EnhancedSafetyHeatmapScreen({
    Key? key,
    required this.rooms,
    required this.architecturalElements,
    required this.annotationId,
    this.floorPlanImagePath,
    this.rawDetectionResult,
    this.analysisId, // Optional for backward compatibility
  }) : super(key: key);

  @override
  _EnhancedSafetyHeatmapScreenState createState() => _EnhancedSafetyHeatmapScreenState();
}

class _EnhancedSafetyHeatmapScreenState extends State<EnhancedSafetyHeatmapScreen> {
  // Core data structures
  Map<String, HouseBoundaryData> _houseBoundaryData = {};
  Map<String, ExternalWallData> _externalWallData = {};
  Map<String, EnhancedRoomData> _enhancedRoomData = {};
  Map<String, EnhancedWindowData> _enhancedWindowData = {};
  Map<String, EnhancedDoorData> _enhancedDoorData = {};
  
  // UI state and image handling
  bool _isLoading = false;
  bool _showHeatmap = false;
  String _selectedHeatmapType = 'safety';
  ui.Image? _floorPlanImage;
  Uint8List? _imageBytes;
  
  // Heatmap data
  Map<String, dynamic>? _heatmapData;
  List<Map<String, dynamic>>? _gridPoints;
  
  // Constants
  static const int GRID_RESOLUTION = 20;
  static const double PIXEL_TO_METER_RATIO = 0.1;

  @override
  void initState() {
    super.initState();
    _extractDataFromDetectionResults();
    _loadFloorPlanImage();
    _generateHeatmapAutomatically();
  }

  // Helper method to decode base64 image
  Uint8List _decodeBase64Image(String base64String) {
    try {
      // Remove data URL prefix if present (e.g., "data:image/png;base64,")
      String cleanBase64 = base64String;
      if (base64String.startsWith('data:')) {
        final commaIndex = base64String.indexOf(',');
        if (commaIndex != -1) {
          cleanBase64 = base64String.substring(commaIndex + 1);
        }
      }
      
      // Remove any whitespace or newlines
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');
      
      return base64Decode(cleanBase64);
    } catch (e) {
      print('❌ Error decoding base64 image: $e');
      print('   Base64 string length: ${base64String.length}');
      print('   First 50 chars: ${base64String.substring(0, math.min(50, base64String.length))}');
      return Uint8List(0);
    }
  }

  // Load and decode the floor plan image
  void _loadFloorPlanImage() async {
    if (widget.floorPlanImagePath != null) {
      try {
        print('🖼️ Loading floor plan image...');
        print('   Image data length: ${widget.floorPlanImagePath!.length}');
        print('   Image data starts with: ${widget.floorPlanImagePath!.substring(0, math.min(100, widget.floorPlanImagePath!.length))}');
        
        // Decode base64 image
        _imageBytes = _decodeBase64Image(widget.floorPlanImagePath!);
        
        if (_imageBytes!.isNotEmpty) {
          // Convert to ui.Image for painting
          final codec = await ui.instantiateImageCodec(_imageBytes!);
          final frame = await codec.getNextFrame();
          setState(() {
            _floorPlanImage = frame.image;
          });
          
          print('✅ Floor plan image loaded: ${_floorPlanImage!.width}x${_floorPlanImage!.height}');
        } else {
          print('⚠️ Empty image data after decoding');
        }
      } catch (e) {
        print('❌ Error loading floor plan image: $e');
        print('   Trying to load image without ui.Image conversion...');
        
        // Fallback: try to decode just for display
        try {
          _imageBytes = _decodeBase64Image(widget.floorPlanImagePath!);
          if (_imageBytes!.isNotEmpty) {
            setState(() {
              // Don't set _floorPlanImage, just use _imageBytes for Image.memory
            });
            print('✅ Image bytes loaded as fallback: ${_imageBytes!.length} bytes');
          }
        } catch (fallbackError) {
          print('❌ Fallback image loading also failed: $fallbackError');
        }
      }
    } else {
      print('⚠️ No floor plan image path provided');
    }
  }

  List<Map<String, double>> _convertToBoundariesList(dynamic boundaries) {
    if (boundaries == null) return [];
    
    if (boundaries is List) {
      return boundaries.map<Map<String, double>>((item) {
        if (item is Map<String, dynamic>) {
          return item.map((key, value) => MapEntry(key, (value as num?)?.toDouble() ?? 0.0));
        }
        return <String, double>{};
      }).toList();
    } else if (boundaries is Map<String, dynamic>) {
      // Single boundary object - convert to list with one item
      return [boundaries.map((key, value) => MapEntry(key, (value as num?)?.toDouble() ?? 0.0))];
    }
    
    return [];
  }

  void _extractDataFromDetectionResults() {
    print('🔍 Extracting data from detection results...');
    print('   Rooms: ${widget.rooms.length}');
    print('   Architectural Elements: ${widget.architecturalElements.length}');
    print('   Has raw detection result: ${widget.rawDetectionResult != null}');
    
    // Debug: Print architectural elements
    for (var element in widget.architecturalElements) {
      print('   Element: ${element['type']} at (${element['x']}, ${element['y']}) - confidence: ${element['confidence']}');
    }
    
    // Examine raw detection result for additional data
    if (widget.rawDetectionResult != null) {
      print('📊 Raw Detection Result Analysis:');
      widget.rawDetectionResult!.forEach((key, value) {
        if (value is List) {
          print('   $key: List with ${value.length} items');
          if (key.toLowerCase().contains('room') || 
              key.toLowerCase().contains('stair') || 
              key.toLowerCase().contains('mamad') ||
              key.toLowerCase().contains('boundary') ||
              key.toLowerCase().contains('annotation')) {
            print('     🔍 Examining $key in detail...');
            for (int i = 0; i < value.length && i < 3; i++) {
              print('       Item $i: ${value[i]}');
            }
          }
        } else if (value is Map) {
          print('   $key: Map with keys: ${value.keys.toList()}');
          if (key.toLowerCase().contains('room') || 
              key.toLowerCase().contains('stair') || 
              key.toLowerCase().contains('mamad') ||
              key.toLowerCase().contains('boundary') ||
              key.toLowerCase().contains('annotation')) {
            print('     🔍 Map contents: $value');
          }
        }
      });
    }
    
    // Extract house boundaries from room boundaries
    _extractHouseBoundaries();
    
    // Extract external walls from architectural elements and room walls
    _extractExternalWalls();
    
    // Extract additional rooms from raw data
    _extractAdditionalRoomsFromRawData();
    
    // Initialize enhanced room data from detected rooms
    for (var room in widget.rooms) {
      final roomId = room['id']?.toString() ?? 'room_${widget.rooms.indexOf(room)}';
      
      // Debug: Print room information
      print('   Room: $roomId - ${room['name']} - doors: ${room['doors']}, windows: ${room['windows']}, walls: ${room['walls']}');
      
      _enhancedRoomData[roomId] = EnhancedRoomData(
        roomId: roomId,
        roomName: room['name']?.toString() ?? 'Room ${widget.rooms.indexOf(room) + 1}',
        roomType: room['type']?.toString() ?? 'room',
        boundaries: _convertToBoundariesList(room['boundaries']),
        area: _calculateAreaFromBoundaries(room['boundaries']) ?? 20.0, // Default 20m²
        // Set intelligent defaults based on room type
        internalWallThicknessCm: _getDefaultWallThickness(room['type']?.toString()),
        isMamad: _isMamadRoom(room['name']?.toString(), room['type']?.toString()),
        hasAirFiltration: _isMamadRoom(room['name']?.toString(), room['type']?.toString()),
        hasBlastDoor: _isMamadRoom(room['name']?.toString(), room['type']?.toString()),
        hasCommunicationSystem: _isMamadRoom(room['name']?.toString(), room['type']?.toString()),
        hasEmergencySupplies: false, // User would need to confirm this
      );
    }
    
    // Extract staircase data
    _extractStaircaseData();
    
    // Extract window data from architectural elements
    _extractWindowData();
    
    // Extract door data from architectural elements
    _extractDoorData();
    
    print('   Extracted enhanced room data: ${_enhancedRoomData.length} rooms');
    print('   Extracted window data: ${_enhancedWindowData.length} windows');
    print('   Extracted door data: ${_enhancedDoorData.length} doors');
    print('   Extracted external walls: ${_externalWallData.length} walls');
  }

  void _extractHouseBoundaries() {
    // Create house boundary from all room boundaries combined
    List<Map<String, double>> allBoundaryPoints = [];
    
    for (var room in widget.rooms) {
      final boundaries = _convertToBoundariesList(room['boundaries']);
      allBoundaryPoints.addAll(boundaries);
    }
    
    // Also check raw data for house boundary information
    if (widget.rawDetectionResult != null) {
      widget.rawDetectionResult!.forEach((key, value) {
        if (key.toLowerCase().contains('boundary') || 
            key.toLowerCase().contains('perimeter') ||
            key.toLowerCase().contains('outline')) {
          print('🏠 Found house boundary data in key: $key');
          if (value is List) {
            for (var boundaryData in value) {
              if (boundaryData is Map<String, dynamic>) {
                final boundaryPoints = _convertToBoundariesList(boundaryData);
                allBoundaryPoints.addAll(boundaryPoints);
              }
            }
          } else if (value is Map<String, dynamic>) {
            final boundaryPoints = _convertToBoundariesList(value);
            allBoundaryPoints.addAll(boundaryPoints);
          }
        }
        
        // Look for exterior perimeter specifically
        if (key.toLowerCase().contains('exterior') && value is Map<String, dynamic>) {
          if (value.containsKey('perimeter') || value.containsKey('boundary')) {
            print('🏠 Found exterior perimeter data');
            final perimeterData = value['perimeter'] ?? value['boundary'];
            final boundaryPoints = _convertToBoundariesList(perimeterData);
            allBoundaryPoints.addAll(boundaryPoints);
          }
        }
      });
    }
    
    if (allBoundaryPoints.isNotEmpty) {
      _houseBoundaryData['main'] = HouseBoundaryData(
        exteriorPerimeter: allBoundaryPoints,
      );
      print('✅ House boundary extracted with ${allBoundaryPoints.length} points');
    } else {
      print('⚠️ No house boundary data found');
    }
  }

  void _extractExternalWalls() {
    // Extract wall data from architectural elements first
    int wallIndex = 0;
    
    // Process walls from main architectural elements
    final walls = widget.architecturalElements.where((e) => e['type'] == 'wall').toList();
    for (var wall in walls) {
      final wallId = 'arch_wall_${wallIndex++}';
      
      // Extract actual positioning data
      final center = {
        'x': wall['x']?.toDouble() ?? wall['center']?['x']?.toDouble() ?? 0.0,
        'y': wall['y']?.toDouble() ?? wall['center']?['y']?.toDouble() ?? 0.0,
      };
      
      // Calculate wall segment based on bbox or dimensions
      final width = wall['width']?.toDouble() ?? wall['dimensions']?['width']?.toDouble() ?? 50.0;
      final height = wall['height']?.toDouble() ?? wall['dimensions']?['height']?.toDouble() ?? 10.0;
      
      Map<String, double> segmentStart, segmentEnd;
      
      // Determine wall orientation and endpoints based on dimensions
      if (width > height) {
        // Horizontal wall
        segmentStart = {'x': center['x']! - width/2, 'y': center['y']!};
        segmentEnd = {'x': center['x']! + width/2, 'y': center['y']!};
      } else {
        // Vertical wall
        segmentStart = {'x': center['x']!, 'y': center['y']! - height/2};
        segmentEnd = {'x': center['x']!, 'y': center['y']! + height/2};
      }
      
      _externalWallData[wallId] = ExternalWallData(
        wallId: wallId,
        orientation: _determineWallOrientation(wall),
        material: wall['material']?.toString() ?? 'concrete_block',
        thicknessCm: wall['thickness']?.toDouble() ?? 20.0,
        segmentStart: Map<String, double>.from(segmentStart),
        segmentEnd: Map<String, double>.from(segmentEnd),
        center: Map<String, double>.from(center),
      );
      
      print('   Wall $wallId: ${segmentStart['x']},${segmentStart['y']} -> ${segmentEnd['x']},${segmentEnd['y']}');
    }
    
    // Look for external walls in raw data
    if (widget.rawDetectionResult != null) {
      widget.rawDetectionResult!.forEach((key, value) {
        if ((key.toLowerCase().contains('wall') && 
             key.toLowerCase().contains('external')) ||
            key.toLowerCase().contains('exterior_wall') ||
            key.toLowerCase().contains('outer_wall')) {
          print('🧱 Found external wall data in key: $key');
          if (value is List) {
            for (var wallData in value) {
              if (wallData is Map<String, dynamic>) {
                final wallId = 'external_wall_${wallIndex++}';
                
                final center = {
                  'x': wallData['x']?.toDouble() ?? wallData['center']?['x']?.toDouble() ?? 0.0,
                  'y': wallData['y']?.toDouble() ?? wallData['center']?['y']?.toDouble() ?? 0.0,
                };
                
                final segmentStart = wallData['segment_start'] != null
                    ? (wallData['segment_start'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()))
                    : {'x': center['x']! - 25.0, 'y': center['y']!};
                final segmentEnd = wallData['segment_end'] != null
                    ? (wallData['segment_end'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()))
                    : {'x': center['x']! + 25.0, 'y': center['y']!};
                
                _externalWallData[wallId] = ExternalWallData(
                  wallId: wallId,
                  orientation: _determineWallOrientation(wallData),
                  material: wallData['material']?.toString() ?? 'concrete_block',
                  thicknessCm: wallData['thickness']?.toDouble() ?? 25.0,
                  segmentStart: Map<String, double>.from(segmentStart),
                  segmentEnd: Map<String, double>.from(segmentEnd),
                  center: Map<String, double>.from(center),
                );
              }
            }
          }
        }
      });
    }
    
    // Extract wall data from room architectural elements
    for (var room in widget.rooms) {
      final roomWalls = room['walls'] ?? [];
      if (roomWalls is List) {
        for (var wall in roomWalls) {
          final wallId = 'room_wall_${wallIndex++}';
          
          final center = {
            'x': wall['x']?.toDouble() ?? wall['center']?['x']?.toDouble() ?? 0.0,
            'y': wall['y']?.toDouble() ?? wall['center']?['y']?.toDouble() ?? 0.0,
          };
          
          final width = wall['width']?.toDouble() ?? wall['dimensions']?['width']?.toDouble() ?? 40.0;
          final height = wall['height']?.toDouble() ?? wall['dimensions']?['height']?.toDouble() ?? 10.0;
          
          Map<String, double> segmentStart, segmentEnd;
          if (width > height) {
            segmentStart = {'x': center['x']! - width/2, 'y': center['y']!};
            segmentEnd = {'x': center['x']! + width/2, 'y': center['y']!};
          } else {
            segmentStart = {'x': center['x']!, 'y': center['y']! - height/2};
            segmentEnd = {'x': center['x']!, 'y': center['y']! + height/2};
          }
          
          _externalWallData[wallId] = ExternalWallData(
            wallId: wallId,
            orientation: _determineWallOrientation(wall),
            material: 'concrete_block',
            thicknessCm: 20.0,
            segmentStart: Map<String, double>.from(segmentStart),
            segmentEnd: Map<String, double>.from(segmentEnd),
            center: Map<String, double>.from(center),
          );
        }
      } else if (roomWalls is int) {
        // If walls is just a count, create walls around room boundaries
        final roomBoundaries = _convertToBoundariesList(room['boundaries']);
        if (roomBoundaries.length >= 3) {
          // Create walls along room perimeter
          for (int i = 0; i < roomBoundaries.length; i++) {
            final wallId = 'room_${room['id']}_wall_$i';
            final currentPoint = roomBoundaries[i];
            final nextPoint = roomBoundaries[(i + 1) % roomBoundaries.length];
            
            _externalWallData[wallId] = ExternalWallData(
              wallId: wallId,
              orientation: _determineOrientationFromPoints(currentPoint, nextPoint),
              material: 'concrete_block',
              thicknessCm: 20.0,
              segmentStart: Map<String, double>.from(currentPoint),
              segmentEnd: Map<String, double>.from(nextPoint),
              center: {
                'x': (currentPoint['x']! + nextPoint['x']!) / 2,
                'y': (currentPoint['y']! + nextPoint['y']!) / 2,
              },
            );
          }
        } else {
          // Fallback to generic positioned walls
          for (int i = 0; i < roomWalls; i++) {
            final wallId = 'room_${room['id']}_wall_$i';
            final angle = (i * 2 * math.pi) / roomWalls;
            final radius = 50.0;
            final centerX = 200.0 + i * 100.0;
            final centerY = 200.0;
            
            final segmentStart = {
              'x': centerX + radius * math.cos(angle),
              'y': centerY + radius * math.sin(angle),
            };
            final segmentEnd = {
              'x': centerX + radius * math.cos(angle + math.pi/2),
              'y': centerY + radius * math.sin(angle + math.pi/2),
            };
            
            _externalWallData[wallId] = ExternalWallData(
              wallId: wallId,
              orientation: ['north', 'south', 'east', 'west'][i % 4],
              material: 'concrete_block',
              thicknessCm: 20.0,
              segmentStart: Map<String, double>.from(segmentStart),
              segmentEnd: Map<String, double>.from(segmentEnd),
              center: {'x': centerX, 'y': centerY},
            );
          }
        }
      }
    }
    
    // If no walls detected, create default external walls based on house boundaries
    if (_externalWallData.isEmpty) {
      print('⚠️ No walls detected, creating default external walls');
      final houseBoundary = _houseBoundaryData['main'];
      if (houseBoundary != null && houseBoundary.exteriorPerimeter.isNotEmpty) {
        // Create walls along house perimeter
        final perimeter = houseBoundary.exteriorPerimeter;
        for (int i = 0; i < perimeter.length; i++) {
          final wallId = 'perimeter_wall_$i';
          final currentPoint = perimeter[i];
          final nextPoint = perimeter[(i + 1) % perimeter.length];
          
          _externalWallData[wallId] = ExternalWallData(
            wallId: wallId,
            orientation: _determineOrientationFromPoints(currentPoint, nextPoint),
            material: 'concrete_block',
            thicknessCm: 25.0,
            segmentStart: Map<String, double>.from(currentPoint),
            segmentEnd: Map<String, double>.from(nextPoint),
            center: {
              'x': (currentPoint['x']! + nextPoint['x']!) / 2,
              'y': (currentPoint['y']! + nextPoint['y']!) / 2,
            },
          );
        }
      } else {
        // Ultimate fallback - create default positioned walls
        final orientations = ['north', 'south', 'east', 'west'];
        final positions = [
          {'start': {'x': 0.0, 'y': 0.0}, 'end': {'x': 400.0, 'y': 0.0}}, // North
          {'start': {'x': 0.0, 'y': 400.0}, 'end': {'x': 400.0, 'y': 400.0}}, // South
          {'start': {'x': 0.0, 'y': 0.0}, 'end': {'x': 0.0, 'y': 400.0}}, // West
          {'start': {'x': 400.0, 'y': 0.0}, 'end': {'x': 400.0, 'y': 400.0}}, // East
        ];
        
        for (int i = 0; i < orientations.length; i++) {
          final wallId = 'default_wall_${orientations[i]}';
          final start = positions[i]['start'] as Map<String, double>;
          final end = positions[i]['end'] as Map<String, double>;
          
          _externalWallData[wallId] = ExternalWallData(
            wallId: wallId,
            orientation: orientations[i],
            material: 'concrete_block',
            thicknessCm: 25.0,
            segmentStart: Map<String, double>.from(start),
            segmentEnd: Map<String, double>.from(end),
            center: {
              'x': (start['x']! + end['x']!) / 2,
              'y': (start['y']! + end['y']!) / 2,
            },
          );
        }
      }
    }
    
    print('✅ External walls extracted: ${_externalWallData.length} walls');
  }

  String _determineOrientationFromPoints(Map<String, double> start, Map<String, double> end) {
    final dx = end['x']! - start['x']!;
    final dy = end['y']! - start['y']!;
    
    if (dx.abs() > dy.abs()) {
      return dx > 0 ? 'east' : 'west';
    } else {
      return dy > 0 ? 'south' : 'north';
    }
  }

  void _extractAdditionalRoomsFromRawData() {
    if (widget.rawDetectionResult == null) return;
    
    // Look for additional room-related data in raw results
    widget.rawDetectionResult!.forEach((key, value) {
      if (key.toLowerCase().contains('room') && value is List) {
        print('🏠 Found additional room data in key: $key');
        for (var roomData in value) {
          if (roomData is Map<String, dynamic>) {
            final roomId = roomData['id']?.toString() ?? 'additional_room_${DateTime.now().millisecondsSinceEpoch}';
            
            // Check if this room is already processed
            if (!_enhancedRoomData.containsKey(roomId)) {
              print('   Adding additional room: $roomId');
              _enhancedRoomData[roomId] = EnhancedRoomData(
                roomId: roomId,
                roomName: roomData['name']?.toString() ?? 'Additional Room',
                roomType: roomData['type']?.toString() ?? 'room',
                boundaries: _convertToBoundariesList(roomData['boundaries']),
                area: _calculateAreaFromBoundaries(roomData['boundaries']) ?? 15.0,
                internalWallThicknessCm: _getDefaultWallThickness(roomData['type']?.toString()),
                isMamad: _isMamadRoom(roomData['name']?.toString(), roomData['type']?.toString()),
                hasAirFiltration: _isMamadRoom(roomData['name']?.toString(), roomData['type']?.toString()),
                hasBlastDoor: _isMamadRoom(roomData['name']?.toString(), roomData['type']?.toString()),
                hasCommunicationSystem: _isMamadRoom(roomData['name']?.toString(), roomData['type']?.toString()),
                hasEmergencySupplies: false,
              );
            }
          }
        }
      }
      
      // Look for user annotations
      if (key.toLowerCase().contains('annotation') && value is List) {
        print('📝 Found annotation data in key: $key');
        for (var annotation in value) {
          if (annotation is Map<String, dynamic> && annotation['type']?.toString().toLowerCase() == 'room') {
            final roomId = 'annotated_room_${DateTime.now().millisecondsSinceEpoch}';
            print('   Adding annotated room: $roomId');
            _enhancedRoomData[roomId] = EnhancedRoomData(
              roomId: roomId,
              roomName: annotation['label']?.toString() ?? 'Annotated Room',
              roomType: annotation['room_type']?.toString() ?? 'room',
              boundaries: _convertToBoundariesList(annotation['boundaries']),
              area: annotation['area']?.toDouble() ?? 12.0,
              internalWallThicknessCm: _getDefaultWallThickness(annotation['room_type']?.toString()),
              isMamad: _isMamadRoom(annotation['label']?.toString(), annotation['room_type']?.toString()),
              hasAirFiltration: _isMamadRoom(annotation['label']?.toString(), annotation['room_type']?.toString()),
              hasBlastDoor: _isMamadRoom(annotation['label']?.toString(), annotation['room_type']?.toString()),
              hasCommunicationSystem: _isMamadRoom(annotation['label']?.toString(), annotation['room_type']?.toString()),
              hasEmergencySupplies: false,
            );
          }
        }
      }
    });
  }

  void _extractStaircaseData() {
    // Extract staircases from architectural elements
    final staircases = widget.architecturalElements.where((e) => 
        e['type']?.toString().toLowerCase().contains('stair') == true).toList();
    
    for (var staircase in staircases) {
      final staircaseId = 'staircase_${staircases.indexOf(staircase)}';
      print('   Found staircase: $staircaseId');
      
      // Treat staircase as a special room type for safety assessment
      _enhancedRoomData[staircaseId] = EnhancedRoomData(
        roomId: staircaseId,
        roomName: 'Staircase ${staircases.indexOf(staircase) + 1}',
        roomType: 'staircase',
        boundaries: [],
        area: staircase['area']?.toDouble() ?? 8.0, // Default staircase area
        internalWallThicknessCm: 15.0, // Staircases often have thicker walls
        isMamad: false, // Staircases are not safe rooms
        hasAirFiltration: false,
        hasBlastDoor: false,
        hasCommunicationSystem: false,
        hasEmergencySupplies: false,
      );
    }
    
    // Also check raw data for staircases
    if (widget.rawDetectionResult != null) {
      widget.rawDetectionResult!.forEach((key, value) {
        if (key.toLowerCase().contains('stair') && value is List) {
          print('🪜 Found staircase data in key: $key');
          for (var staircaseData in value) {
            if (staircaseData is Map<String, dynamic>) {
              final staircaseId = 'raw_staircase_${DateTime.now().millisecondsSinceEpoch}';
              print('   Adding staircase from raw data: $staircaseId');
              _enhancedRoomData[staircaseId] = EnhancedRoomData(
                roomId: staircaseId,
                roomName: staircaseData['name']?.toString() ?? 'Staircase',
                roomType: 'staircase',
                boundaries: _convertToBoundariesList(staircaseData['boundaries']),
                area: staircaseData['area']?.toDouble() ?? 8.0,
                internalWallThicknessCm: 15.0,
                isMamad: false,
                hasAirFiltration: false,
                hasBlastDoor: false,
                hasCommunicationSystem: false,
                hasEmergencySupplies: false,
              );
            }
          }
        }
      });
    }
  }

  void _extractWindowData() {
    int windowIndex = 0;
    
    // Extract windows from main architectural elements
    final windows = widget.architecturalElements.where((e) => e['type'] == 'window').toList();
    
    for (var window in windows) {
      final windowId = 'arch_window_${windowIndex++}';
      _enhancedWindowData[windowId] = EnhancedWindowData(
        windowId: windowId,
        position: {
          'x': window['x']?.toDouble() ?? window['center']?['x']?.toDouble() ?? 0.0,
          'y': window['y']?.toDouble() ?? window['center']?['y']?.toDouble() ?? 0.0,
        },
        roomId: window['room_id']?.toString() ?? '',
        sizeCategory: _determineWindowSize(window),
        glassType: 'standard', // Default
        isExternal: true, // Assume external by default
      );
    }
    
    // Also extract windows from room data
    for (var room in widget.rooms) {
      final roomId = room['id']?.toString() ?? 'room_${widget.rooms.indexOf(room)}';
      final roomWindows = room['windows'] ?? [];
      
      if (roomWindows is List) {
        for (var window in roomWindows) {
          final windowId = 'room_${roomId}_window_${windowIndex++}';
          _enhancedWindowData[windowId] = EnhancedWindowData(
            windowId: windowId,
            position: {
              'x': window['x']?.toDouble() ?? window['center']?['x']?.toDouble() ?? 0.0,
              'y': window['y']?.toDouble() ?? window['center']?['y']?.toDouble() ?? 0.0,
            },
            roomId: roomId,
            sizeCategory: _determineWindowSize(window),
            glassType: 'standard',
            isExternal: true,
          );
        }
      } else if (roomWindows is int) {
        // If windows is just a count, create generic windows
        for (int i = 0; i < roomWindows; i++) {
          final windowId = 'room_${roomId}_window_$i';
          _enhancedWindowData[windowId] = EnhancedWindowData(
            windowId: windowId,
            position: {
              'x': 100.0 + (i * 50.0), // Distribute horizontally
              'y': 100.0,
            },
            roomId: roomId,
            sizeCategory: 'medium',
            glassType: 'standard',
            isExternal: true,
          );
        }
      }
    }
  }

  void _extractDoorData() {
    int doorIndex = 0;
    
    // Extract doors from main architectural elements
    final doors = widget.architecturalElements.where((e) => e['type'] == 'door').toList();
    
    for (var door in doors) {
      final doorId = 'arch_door_${doorIndex++}';
      _enhancedDoorData[doorId] = EnhancedDoorData(
        doorId: doorId,
        position: {
          'x': door['x']?.toDouble() ?? door['center']?['x']?.toDouble() ?? 0.0,
          'y': door['y']?.toDouble() ?? door['center']?['y']?.toDouble() ?? 0.0,
        },
        roomId: door['room_id']?.toString() ?? '',
        doorType: 'standard', // Default
        isExternal: _isDoorExternal(door),
        leadsToExit: _isDoorExternal(door), // External doors typically lead to exits
      );
    }
    
    // Also extract doors from room data
    for (var room in widget.rooms) {
      final roomId = room['id']?.toString() ?? 'room_${widget.rooms.indexOf(room)}';
      final roomDoors = room['doors'] ?? [];
      
      if (roomDoors is List) {
        for (var door in roomDoors) {
          final doorId = 'room_${roomId}_door_${doorIndex++}';
          _enhancedDoorData[doorId] = EnhancedDoorData(
            doorId: doorId,
            position: {
              'x': door['x']?.toDouble() ?? door['center']?['x']?.toDouble() ?? 0.0,
              'y': door['y']?.toDouble() ?? door['center']?['y']?.toDouble() ?? 0.0,
            },
            roomId: roomId,
            doorType: 'standard',
            isExternal: _isDoorExternal(door),
            leadsToExit: _isDoorExternal(door),
          );
        }
      } else if (roomDoors is int) {
        // If doors is just a count, create generic doors
        for (int i = 0; i < roomDoors; i++) {
          final doorId = 'room_${roomId}_door_$i';
          _enhancedDoorData[doorId] = EnhancedDoorData(
            doorId: doorId,
            position: {
              'x': 50.0 + (i * 30.0), // Distribute
              'y': 50.0,
            },
            roomId: roomId,
            doorType: 'standard',
            isExternal: i == 0, // First door is external
            leadsToExit: i == 0,
          );
        }
      }
    }
  }

  // Helper methods for intelligent defaults
  double _getDefaultWallThickness(String? roomType) {
    switch (roomType?.toLowerCase()) {
      case 'mamad':
      case 'safe room':
      case 'saferoom':
        return 20.0; // Thicker walls for safe rooms
      case 'bathroom':
      case 'kitchen':
        return 12.0; // Slightly thicker for wet areas
      case 'staircase':
      case 'stairs':
        return 15.0; // Moderate thickness for structural areas
      default:
        return 10.0; // Standard interior walls
    }
  }

  bool _isMamadRoom(String? roomName, String? roomType) {
    final name = roomName?.toLowerCase() ?? '';
    final type = roomType?.toLowerCase() ?? '';
    
    // Enhanced mamad detection
    return name.contains('mamad') || 
           name.contains('safe') || 
           name.contains('shelter') ||
           name.contains('protected') ||
           name.contains('secure') ||
           type.contains('mamad') || 
           type.contains('safe') ||
           type.contains('shelter') ||
           type.contains('protected') ||
           type.contains('secure') ||
           // Hebrew variations
           name.contains('ממ״ד') ||
           name.contains('ממד') ||
           name.contains('מקלט') ||
           type.contains('ממ״ד') ||
           type.contains('ממד') ||
           type.contains('מקלט');
  }

  String _determineWallOrientation(dynamic wall) {
    // Simple heuristic based on position or dimensions
    // This could be enhanced with more sophisticated analysis
    final x = wall['center']?['x']?.toDouble() ?? 0.0;
    final y = wall['center']?['y']?.toDouble() ?? 0.0;
    
    // Very basic orientation determination
    if (y < 100) return 'north';
    if (y > 300) return 'south';
    if (x < 100) return 'west';
    return 'east';
  }

  String _determineWindowSize(dynamic window) {
    final area = window['area']?.toDouble() ?? 0.0;
    final width = window['dimensions']?['width']?.toDouble() ?? 0.0;
    final height = window['dimensions']?['height']?.toDouble() ?? 0.0;
    
    if (area > 0) {
      if (area > 2.0) return 'large';
      if (area > 1.0) return 'medium';
      return 'small';
    }
    
    // Fallback to dimensions
    if (width * height > 2.0) return 'large';
    if (width * height > 1.0) return 'medium';
    return 'small';
  }

  bool _isDoorExternal(dynamic door) {
    // Simple heuristic - could be enhanced
    final position = door['relative_position']?.toString().toLowerCase() ?? '';
    return position.contains('exterior') || 
           position.contains('external') || 
           position.contains('outside');
  }

  double? _calculateAreaFromBoundaries(dynamic boundaries) {
    final boundariesList = _convertToBoundariesList(boundaries);
    if (boundariesList.length < 3) return null;
    
    // Simple area calculation using shoelace formula
    double area = 0.0;
    for (int i = 0; i < boundariesList.length; i++) {
      final j = (i + 1) % boundariesList.length;
      final xi = boundariesList[i]['x'] ?? 0.0;
      final yi = boundariesList[i]['y'] ?? 0.0;
      final xj = boundariesList[j]['x'] ?? 0.0;
      final yj = boundariesList[j]['y'] ?? 0.0;
      area += xi * yj - xj * yi;
    }
    
    // Convert from pixels to square meters (rough approximation)
    return (area.abs() / 2.0) * PIXEL_TO_METER_RATIO * PIXEL_TO_METER_RATIO;
  }

  void _generateHeatmapAutomatically() {
    // Automatically generate heatmap without user interaction
    _generateHeatmap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhanced Safety Assessment'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        actions: [
          if (_showHeatmap)
            PopupMenuButton<String>(
              onSelected: (value) {
                setState(() {
                  _selectedHeatmapType = value;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'safety', child: Text('Safety Score')),
                const PopupMenuItem(value: 'evacuation', child: Text('Evacuation Time')),
                const PopupMenuItem(value: 'protection', child: Text('Blast Protection')),
              ],
              child: const Icon(Icons.layers),
            ),
          IconButton(
            onPressed: _showDataSummary,
            icon: const Icon(Icons.info_outline),
            tooltip: 'View Data Summary',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating safety heatmap...'),
            ],
          ),
            )
          : _showHeatmap
              ? _buildHeatmapView()
              : _buildDataSummaryView(),
      floatingActionButton: !_isLoading && !_showHeatmap
          ? FloatingActionButton.extended(
              onPressed: _generateHeatmap,
              icon: const Icon(Icons.analytics),
              label: const Text('Generate Heatmap'),
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildDataSummaryView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
            'Detected Data Summary',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        
          // Room data summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                  Row(
                    children: [
                      Icon(Icons.home, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      const Text('Rooms', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
              ),
                  const SizedBox(height: 12),
                  Text('Total Rooms: ${_enhancedRoomData.length}'),
                  Text('Mamad Rooms: ${_enhancedRoomData.values.where((r) => r.isMamad).length}'),
                  const SizedBox(height: 8),
                  ..._enhancedRoomData.values.map((room) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
          children: [
                        Icon(
                          room.isMamad ? Icons.security : Icons.room,
                          size: 16,
                          color: room.isMamad ? Colors.green : Colors.grey,
            ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${room.roomName} (${room.area.toStringAsFixed(1)} m²)')),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),
        ),
          
        const SizedBox(height: 16),
        
          // Windows and doors summary
          Row(
            children: [
              Expanded(
                child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                        Row(
                          children: [
                            Icon(Icons.window, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            const Text('Windows', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                ),
                        const SizedBox(height: 8),
                        Text('Total: ${_enhancedWindowData.length}'),
                        Text('External: ${_enhancedWindowData.values.where((w) => w.isExternal).length}'),
              ],
            ),
          ),
        ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                        Row(
                          children: [
                            Icon(Icons.door_front_door, color: Colors.brown[700]),
                            const SizedBox(width: 8),
                            const Text('Doors', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                  ),
                    const SizedBox(height: 8),
                        Text('Total: ${_enhancedDoorData.length}'),
                        Text('External: ${_enhancedDoorData.values.where((d) => d.isExternal).length}'),
                  ],
                    ),
              ),
            ),
              ),
      ],
          ),
          
        const SizedBox(height: 16),
        
          // External walls summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.foundation, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      const Text('External Walls', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Total Segments: ${_externalWallData.length}'),
                  Text('Default Material: Concrete Block'),
                  Text('Default Thickness: 20 cm'),
                ],
              ),
            ),
        ),
          
        const SizedBox(height: 16),
        
          // Safety features summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.security, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      const Text('Safety Features', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Air Filtration Systems: ${_enhancedRoomData.values.where((r) => r.hasAirFiltration).length}'),
                  Text('Blast-Resistant Doors: ${_enhancedRoomData.values.where((r) => r.hasBlastDoor).length}'),
                  Text('Communication Systems: ${_enhancedRoomData.values.where((r) => r.hasCommunicationSystem).length}'),
                ],
              ),
            ),
                  ),
                  
          const SizedBox(height: 100), // Space for floating action button
        ],
            ),
          );
  }

  void _showDataSummary() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Data Summary'),
        content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rooms: ${_enhancedRoomData.length}'),
                Text('Windows: ${_enhancedWindowData.length}'),
                Text('Doors: ${_enhancedDoorData.length}'),
                Text('External Walls: ${_externalWallData.length}'),
                Text('Mamad Rooms: ${_enhancedRoomData.values.where((r) => r.isMamad).length}'),
              const SizedBox(height: 16),
              const Text('Note: Data was automatically extracted from your floor plan detection results.'),
              ],
            ),
          ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
        ),
    );
  }

  Widget _buildHeatmapView() {
    if (_heatmapData == null) return const Center(child: CircularProgressIndicator());
    
    return Column(
      children: [
        // Heatmap legend
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem('Very Safe', Colors.green),
              _buildLegendItem('Safe', Colors.lightGreen),
              _buildLegendItem('Moderate', Colors.yellow),
              _buildLegendItem('Risk', Colors.orange),
              _buildLegendItem('High Risk', Colors.red),
            ],
          ),
        ),
        
        // Heatmap visualization
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _floorPlanImage != null
                  ? CustomPaint(
                      painter: HeatmapPainter(
                        _heatmapData!, 
                        _selectedHeatmapType,
                        _floorPlanImage!,
                      ),
              child: Container(),
                    )
                  : _imageBytes != null
                      ? Stack(
                          children: [
                            // Background image
                            Image.memory(
                              _imageBytes!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                            // Heatmap overlay
                            CustomPaint(
                              painter: HeatmapPainter(
                                _heatmapData!, 
                                _selectedHeatmapType,
                                null,
                              ),
                              child: Container(),
                            ),
                          ],
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text('Floor plan image not available'),
                              ],
                            ),
                          ),
                        ),
            ),
          ),
        ),
        
        // Statistics
        Container(
          padding: const EdgeInsets.all(16),
          child: _buildStatistics(),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.grey),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildStatistics() {
    final stats = _heatmapData!['statistics'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Safety Statistics', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Average Safety Score: ${stats['average_safety_score']?.toStringAsFixed(1) ?? 'N/A'}'),
            Text('Safe Points: ${stats['safe_points_count'] ?? 0}'),
            Text('Risk Points: ${stats['risk_points_count'] ?? 0}'),
            Text('Coverage Area: ${stats['coverage_area_m2']?.toStringAsFixed(1) ?? 'N/A'} m²'),
          ],
        ),
      ),
    );
  }

  void _generateHeatmap() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔄 Generating heatmap...');
      Map<String, dynamic> result;
      
      // Try to use structured approach first if analysisId is available
      if (widget.analysisId != null) {
        try {
          print('   Using structured data approach with analysis_id: ${widget.analysisId}');
          result = await StructuredSafetyService.generateStructuredHeatmap(widget.analysisId!);
          print('✅ Successfully generated heatmap using structured data');
          
          // Log migration information
          if (result.containsKey('_migration_info')) {
            print('✅ Used structured data approach');
            print('   Migration info: ${result['_migration_info']}');
          }
        } catch (structuredError) {
          print('⚠️ Structured approach failed, falling back to compatibility mode: $structuredError');
          
          // Fallback to compatibility mode
          final requestData = {
            'house_boundaries': _houseBoundaryData['main']?.toJson() ?? {},
            'rooms': _enhancedRoomData.values.map((r) => r.toJson()).toList(),
            'external_walls': _externalWallData.values.map((w) => w.toJson()).toList(),
            'windows': _enhancedWindowData.values.map((w) => w.toJson()).toList(),
            'doors': _enhancedDoorData.values.map((d) => d.toJson()).toList(),
            'safety_assessments': _enhancedRoomData.values.map((r) => r.toSafetyAssessment()).toList(),
            'staircases': [],
            'analysis_id': widget.analysisId, // Pass analysis_id for structured approach
          };
          
          result = await StructuredSafetyService.generateExplosiveRiskHeatmapCompatibility(
            heatmapData: requestData,
            analysisId: widget.analysisId,
          );
        }
      } else {
        print('   No analysis_id available, using compatibility mode');
        
        // Use compatibility mode without analysis_id
        final requestData = {
          'house_boundaries': _houseBoundaryData['main']?.toJson() ?? {},
          'rooms': _enhancedRoomData.values.map((r) => r.toJson()).toList(),
          'external_walls': _externalWallData.values.map((w) => w.toJson()).toList(),
          'windows': _enhancedWindowData.values.map((w) => w.toJson()).toList(),
          'doors': _enhancedDoorData.values.map((d) => d.toJson()).toList(),
          'safety_assessments': _enhancedRoomData.values.map((r) => r.toSafetyAssessment()).toList(),
          'staircases': [],
        };
        
        result = await StructuredSafetyService.generateExplosiveRiskHeatmapCompatibility(
          heatmapData: requestData,
        );
      }

      setState(() {
        _heatmapData = result['heatmap_data'];
        _gridPoints = List<Map<String, dynamic>>.from(result['heatmap_data']['grid_points']);
        _showHeatmap = true;
        _isLoading = false;
      });
      
      // Log migration information if available
      if (result.containsKey('_migration_info')) {
        print('✅ Used structured data approach');
        print('   Migration info: ${result['_migration_info']}');
      } else if (result.containsKey('_fallback_used')) {
        print('⚠️ Used fallback method');
      }
      
    } catch (e) {
      print('❌ Heatmap generation failed: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating heatmap: $e')),
      );
    }
  }
}

// Data classes
class HouseBoundaryData {
  List<Map<String, double>> exteriorPerimeter;
  
  HouseBoundaryData({required this.exteriorPerimeter});
  
  Map<String, dynamic> toJson() => {
    'exterior_perimeter': exteriorPerimeter,
  };
}

class ExternalWallData {
  String wallId;
  String orientation;
  String material;
  double thicknessCm;
  Map<String, double> segmentStart;
  Map<String, double> segmentEnd;
  Map<String, double>? center;
  
  ExternalWallData({
    required this.wallId,
    required this.orientation,
    this.material = 'concrete_block',
    this.thicknessCm = 20.0,
    Map<String, double>? segmentStart,
    Map<String, double>? segmentEnd,
    this.center,
  }) : segmentStart = segmentStart ?? {'x': 0.0, 'y': 0.0},
       segmentEnd = segmentEnd ?? {'x': 100.0, 'y': 0.0};
  
  Map<String, dynamic> toJson() => {
    'wall_id': wallId,
    'orientation': orientation,
    'material': material,
    'thickness_cm': thicknessCm,
    'segment_start': segmentStart,
    'segment_end': segmentEnd,
    'center': center ?? {
      'x': (segmentStart['x']! + segmentEnd['x']!) / 2,
      'y': (segmentStart['y']! + segmentEnd['y']!) / 2,
    },
  };
}

class EnhancedRoomData {
  String roomId;
  String roomName;
  String roomType;
  List<Map<String, double>> boundaries;
  double area;
  double internalWallThicknessCm;
  bool isMamad;
  bool hasAirFiltration;
  bool hasBlastDoor;
  bool hasCommunicationSystem;
  bool hasEmergencySupplies;
  
  EnhancedRoomData({
    required this.roomId,
    required this.roomName,
    required this.roomType,
    required this.boundaries,
    required this.area,
    this.internalWallThicknessCm = 10.0,
    this.isMamad = false,
    this.hasAirFiltration = false,
    this.hasBlastDoor = false,
    this.hasCommunicationSystem = false,
    this.hasEmergencySupplies = false,
  });
  
  Map<String, dynamic> toJson() => {
    'id': roomId,
    'name': roomName,
    'type': roomType,
    'boundaries': boundaries,
    'area_m2': area,
    'internal_wall_thickness_cm': internalWallThicknessCm,
    'is_mamad': isMamad,
    'has_air_filtration': hasAirFiltration,
    'has_blast_door': hasBlastDoor,
    'has_communication_system': hasCommunicationSystem,
    'has_emergency_supplies': hasEmergencySupplies,
  };
  
  Map<String, dynamic> toSafetyAssessment() => {
    'room_id': roomId,
    'responses': {
      'wall_thickness': '${internalWallThicknessCm.round()}cm',
      'air_filtration': hasAirFiltration ? 'yes' : 'no',
      'communication_device': hasCommunicationSystem ? 'yes' : 'no',
      'emergency_supplies': hasEmergencySupplies ? 'yes' : 'no',
    },
  };
}

class EnhancedWindowData {
  String windowId;
  Map<String, double> position;
  String roomId;
  String sizeCategory;
  String glassType;
  bool isExternal;
  
  EnhancedWindowData({
    required this.windowId,
    required this.position,
    required this.roomId,
    this.sizeCategory = 'medium',
    this.glassType = 'standard',
    this.isExternal = true,
  });
  
  Map<String, dynamic> toJson() => {
    'window_id': windowId,
    'position': position,
    'room_id': roomId,
    'size_category': sizeCategory,
    'glass_type': glassType,
    'is_external': isExternal,
  };
}

class EnhancedDoorData {
  String doorId;
  Map<String, double> position;
  String roomId;
  String doorType;
  bool isExternal;
  bool leadsToExit;
  
  EnhancedDoorData({
    required this.doorId,
    required this.position,
    required this.roomId,
    this.doorType = 'standard',
    this.isExternal = false,
    this.leadsToExit = false,
  });
  
  Map<String, dynamic> toJson() => {
    'door_id': doorId,
    'position': position,
    'room_id': roomId,
    'door_type': doorType,
    'is_external': isExternal,
    'leads_to_exit': leadsToExit,
  };
}

// Custom painters

class HeatmapPainter extends CustomPainter {
  final Map<String, dynamic> heatmapData;
  final String heatmapType;
  final ui.Image? floorPlanImage;
  
  HeatmapPainter(this.heatmapData, this.heatmapType, this.floorPlanImage);
  
  @override
  void paint(Canvas canvas, Size size) {
    // Draw the floor plan image as background if available
    if (floorPlanImage != null) {
      final imageRect = Rect.fromLTWH(0, 0, floorPlanImage!.width.toDouble(), floorPlanImage!.height.toDouble());
      final canvasRect = Rect.fromLTWH(0, 0, size.width, size.height);
      
      // Calculate the scaling and positioning to fit the image in the canvas
      final scale = math.min(size.width / floorPlanImage!.width, size.height / floorPlanImage!.height);
      final scaledWidth = floorPlanImage!.width * scale;
      final scaledHeight = floorPlanImage!.height * scale;
      final offsetX = (size.width - scaledWidth) / 2;
      final offsetY = (size.height - scaledHeight) / 2;
      
      final destRect = Rect.fromLTWH(offsetX, offsetY, scaledWidth, scaledHeight);
      
      canvas.drawImageRect(floorPlanImage!, imageRect, destRect, Paint());
    }
    
    // Draw the heatmap grid
    final gridPoints = heatmapData['grid_points'] as List<dynamic>;
    final gridResolution = 20.0;
    
    // Calculate scaling factors based on canvas size and image size
    double scaleX = size.width / 600.0; // Assume default width
    double scaleY = size.height / 600.0; // Assume default height
    
    if (floorPlanImage != null) {
      scaleX = size.width / floorPlanImage!.width;
      scaleY = size.height / floorPlanImage!.height;
      final scale = math.min(scaleX, scaleY);
      scaleX = scaleY = scale;
    }
    
    for (final point in gridPoints) {
      final x = (point['x'] as num).toDouble() * scaleX;
      final y = (point['y'] as num).toDouble() * scaleY;
      final score = (point['safety_score'] as num).toDouble();
      
      // Map score to color with transparency for overlay effect
      Color color = _getColorForScore(score).withOpacity(0.6);
      
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      
      // Draw scaled grid cell
      canvas.drawRect(
        Rect.fromLTWH(x, y, gridResolution * scaleX, gridResolution * scaleY),
        paint,
      );
    }
  }
  
  Color _getColorForScore(double score) {
    if (score >= 80) return Colors.green.withOpacity(0.7);
    if (score >= 65) return Colors.lightGreen.withOpacity(0.7);
    if (score >= 45) return Colors.yellow.withOpacity(0.7);
    if (score >= 25) return Colors.orange.withOpacity(0.7);
    return Colors.red.withOpacity(0.7);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
} 