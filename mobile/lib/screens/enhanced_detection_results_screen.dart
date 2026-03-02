import 'package:flutter/material.dart';import 'dart:convert';
import 'dart:typed_data';
import '../services/enhanced_floor_plan_service.dart';
import '../utils/risk_assessment_utils.dart';
import 'room_safety_assessment_screen.dart';
import 'enhanced_safety_heatmap_screen.dart';
import 'risk_assessment_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:auto_size_text/auto_size_text.dart';

// Add this constant
const String API_BASE_URL = 'http://127.0.0.1:8000'; // or your actual backend URL

/// Explosive Risk Calculator for Safety Assessment
class ExplosiveRiskCalculator {
  final List<DetectedRoom> rooms;
  final List<ArchitecturalElement> elements;
  final List<Map<String, dynamic>> userAnnotations;
  final Map<String, int> imageDimensions;
  
  // Risk parameters (adjustable based on explosive type)
  final double baseExplosiveRadius = 50.0; // pixels in image coordinates
  final double maxRiskDistance = 150.0; // maximum distance for risk calculation
  
  // Attenuation factors
  final Map<String, double> wallAttenuation = {
    'Wall': 0.3,      // 70% reduction
    'Column': 0.4,    // 60% reduction
    'Door': 0.8,      // 20% reduction (open/closed average)
    'Window': 0.7,    // 30% reduction
    'wall': 0.3,
    'door': 0.8,
    'window': 0.7,
    'column': 0.4,
    'stairway': 0.6,
  };
  
  // Room type risk modifiers
  final Map<String, double> roomRiskModifiers = {
    'MAMAD': 0.05,          // Protected space - 95% reduction (extremely safe)
    'mamad': 0.05,
    'Safe Room': 0.05,      // Any designated safe room
    'safe room': 0.05,
    'Corridor': 1.2,        // Higher risk due to channeling
    'corridor': 1.2,
    'Central Hallway': 1.3, // Highest risk - multiple access points
    'hallway': 1.3,
    'Private Room': 0.9,    // Slightly lower risk
    'Enclosed Space': 0.8,  // Lower risk if isolated
    'Kitchen': 1.1,         // Higher risk due to gas/fire hazards
    'kitchen': 1.1,
    'Living Room': 1.0,
    'living room': 1.0,
    'Bedroom': 0.8,
    'bedroom': 0.8,
    'Bathroom': 0.7,
    'bathroom': 0.7,
  };

  ExplosiveRiskCalculator({
    required this.rooms,
    required this.elements,
    required this.userAnnotations,
    required this.imageDimensions,
  });

  // Convert image coordinates to real-world meters (approximate)
  double imageToMeters(double pixels) {
    // Assuming average room size from your data (~4m x 4m = ~80x80 pixels)
    return pixels * 0.05; // rough conversion factor
  }

  // Calculate distance between two points
  double calculateDistance(double x1, double y1, double x2, double y2) {
    return math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
  }

  // Check if point is inside any MAMAD rectangle
  bool isPointInsideMAMAD(double x, double y) {
    final List<Map<String, dynamic>> mamadLocations = getMAMADLocations();
    
    if (mamadLocations.isEmpty) {
      return false;
    }
    
    for (Map<String, dynamic> mamad in mamadLocations) {
      final double minX = mamad['minX'] ?? (mamad['centerX'] ?? 0.0) - 25;
      final double maxX = mamad['maxX'] ?? (mamad['centerX'] ?? 0.0) + 25;
      final double minY = mamad['minY'] ?? (mamad['centerY'] ?? 0.0) - 25;
      final double maxY = mamad['maxY'] ?? (mamad['centerY'] ?? 0.0) + 25;
      
      if (x >= minX && x <= maxX && y >= minY && y <= maxY) {
        print('🔒 Point (${x.round()}, ${y.round()}) is INSIDE MAMAD bounds: (${minX.round()}, ${minY.round()}) to (${maxX.round()}, ${maxY.round()})');
        return true;
      }
    }
    
    return false;
  }

  // Check if point is inside a room
  DetectedRoom? getPointRoom(double x, double y) {
    for (DetectedRoom room in rooms) {
      final bounds = room.boundaries;
      if (bounds.containsKey('x') && bounds.containsKey('y') && 
          bounds.containsKey('width') && bounds.containsKey('height')) {
        final roomX = (bounds['x'] as num).toDouble();
        final roomY = (bounds['y'] as num).toDouble();
        final roomWidth = (bounds['width'] as num).toDouble();
        final roomHeight = (bounds['height'] as num).toDouble();
        
        if (x >= roomX && x <= roomX + roomWidth &&
            y >= roomY && y <= roomY + roomHeight) {
          return room;
        }
      }
    }
    return null;
  }

  // Get MAMAD locations and boundaries from user annotations
  List<Map<String, dynamic>> getMAMADLocations() {
    final mamadAnnotations = userAnnotations
        .where((annotation) => annotation['tool'] == 'mamad')
        .map((mamad) {
          Map<String, dynamic> mamadInfo = {};
          
          print('🔍 Processing MAMAD annotation: ${mamad.keys}');
          
          // First priority: use roomData if available
          if (mamad['roomData'] != null && mamad['roomData']['center'] != null) {
            final center = mamad['roomData']['center'];
            final bounds = mamad['roomData']['bounds'];
            
            mamadInfo['centerX'] = (center['x'] as num).toDouble();
            mamadInfo['centerY'] = (center['y'] as num).toDouble();
            
            print('🔒 MAMAD center from roomData: (${mamadInfo['centerX']}, ${mamadInfo['centerY']})');
            
            // Extract MAMAD rectangle boundaries
            if (bounds != null) {
              mamadInfo['minX'] = (bounds['minX'] as num?)?.toDouble() ?? mamadInfo['centerX']! - 25;
              mamadInfo['maxX'] = (bounds['maxX'] as num?)?.toDouble() ?? mamadInfo['centerX']! + 25;
              mamadInfo['minY'] = (bounds['minY'] as num?)?.toDouble() ?? mamadInfo['centerY']! - 25;
              mamadInfo['maxY'] = (bounds['maxY'] as num?)?.toDouble() ?? mamadInfo['centerY']! + 25;
              mamadInfo['width'] = mamadInfo['maxX']! - mamadInfo['minX']!;
              mamadInfo['height'] = mamadInfo['maxY']! - mamadInfo['minY']!;
            }
          }
          
          // Always calculate bounds from points (most reliable for drawn rectangles)
          if (mamad['points'] != null && (mamad['points'] as List).isNotEmpty) {
            final points = (mamad['points'] as List);
            final xCoords = points.map((p) => (p['x'] as num).toDouble()).toList();
            final yCoords = points.map((p) => (p['y'] as num).toDouble()).toList();
            
            print('🔒 MAMAD points: ${points.length} points, X range: ${xCoords.reduce(math.min)}-${xCoords.reduce(math.max)}, Y range: ${yCoords.reduce(math.min)}-${yCoords.reduce(math.max)}');
            
            // Calculate center from points
            mamadInfo['centerX'] = xCoords.reduce((a, b) => a + b) / xCoords.length;
            mamadInfo['centerY'] = yCoords.reduce((a, b) => a + b) / yCoords.length;
            
            // Calculate bounding box from points
            mamadInfo['minX'] = xCoords.reduce(math.min);
            mamadInfo['maxX'] = xCoords.reduce(math.max);
            mamadInfo['minY'] = yCoords.reduce(math.min);
            mamadInfo['maxY'] = yCoords.reduce(math.max);
            mamadInfo['width'] = mamadInfo['maxX']! - mamadInfo['minX']!;
            mamadInfo['height'] = mamadInfo['maxY']! - mamadInfo['minY']!;
            
            print('🔒 MAMAD calculated bounds: (${mamadInfo['minX']}, ${mamadInfo['minY']}) to (${mamadInfo['maxX']}, ${mamadInfo['maxY']})');
            print('🔒 MAMAD size: ${mamadInfo['width']} x ${mamadInfo['height']}');
          }
          
          // Default values if nothing found
          if (mamadInfo['centerX'] == null) {
            print('⚠️ No MAMAD data found, using defaults');
            mamadInfo['centerX'] = 0.0;
            mamadInfo['centerY'] = 0.0;
            mamadInfo['minX'] = -25.0;
            mamadInfo['maxX'] = 25.0;
            mamadInfo['minY'] = -25.0;
            mamadInfo['maxY'] = 25.0;
            mamadInfo['width'] = 50.0;
            mamadInfo['height'] = 50.0;
          }
          
          return mamadInfo;
        })
        .toList();
        
    //print('🔒 Total MAMAD locations found: ${mamadAnnotations.length}');
    return mamadAnnotations;
  }

  // Ray casting to check line of sight and calculate attenuation
  double calculatePathAttenuation(double fromX, double fromY, double toX, double toY) {
    double totalAttenuation = 1.0;
    const int steps = 20; // Ray casting resolution (optimized for performance)
    
    // Track which elements we've already hit to avoid double-counting
    Set<ArchitecturalElement> hitElements = {};
    
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double rayX = fromX + t * (toX - fromX);
      final double rayY = fromY + t * (toY - fromY);
      
      // Check intersection with architectural elements
      for (ArchitecturalElement element in elements) {
        if (hitElements.contains(element)) continue; // Skip already hit elements
        
        final bbox = element.bbox;
        final x1 = (bbox['x1'] ?? bbox['x'] ?? bbox['left'] ?? 0).toDouble();
        final y1 = (bbox['y1'] ?? bbox['y'] ?? bbox['top'] ?? 0).toDouble();
        final x2 = (bbox['x2'] ?? bbox['right'] ?? (x1 + (bbox['width'] ?? 0))).toDouble();
        final y2 = (bbox['y2'] ?? bbox['bottom'] ?? (y1 + (bbox['height'] ?? 0))).toDouble();
        
        // Ensure valid bounding box
        final minX = math.min(x1, x2);
        final maxX = math.max(x1, x2);
        final minY = math.min(y1, y2);
        final maxY = math.max(y1, y2);
        
        if (rayX >= minX && rayX <= maxX && rayY >= minY && rayY <= maxY) {
          final String elementType = element.type.toLowerCase();
          double attenuation = wallAttenuation[elementType] ?? 0.9; // Default slight attenuation
          
          // Special handling for different element types
          if (elementType.contains('wall')) {
            attenuation = 0.3; // Walls provide strong protection
          } else if (elementType.contains('door')) {
            attenuation = 0.8; // Doors provide some protection
          } else if (elementType.contains('window')) {
            attenuation = 0.7; // Windows provide less protection
          } else if (elementType.contains('column')) {
            attenuation = 0.4; // Columns provide good protection
          }
          
          totalAttenuation *= attenuation;
          hitElements.add(element);
          
          // If attenuation becomes very low, break early
          if (totalAttenuation < 0.1) break;
        }
      }
    }
    
    // Add distance-based attenuation (blast weakens over distance)
    final double distance = calculateDistance(fromX, fromY, toX, toY);
    final double distanceAttenuation = math.exp(-distance / maxRiskDistance);
    totalAttenuation *= distanceAttenuation;
    
    return math.max(totalAttenuation, 0.01); // Minimum attenuation to prevent division by zero
  }

  // Calculate blast pressure at distance with attenuation
  double calculateBlastPressure(double distance, double pathAttenuation, {double explosiveIntensity = 1.0}) {
    if (distance == 0) return explosiveIntensity; // At explosion point
    
    // Inverse square law with exponential decay
    final double pressureDecay = math.pow(baseExplosiveRadius / distance, 2).toDouble();
    final double distanceDecay = math.exp(-distance / maxRiskDistance);
    
    return explosiveIntensity * pressureDecay * distanceDecay * pathAttenuation;
  }

  // Calculate occupancy risk based on room type and accessibility
  double calculateOccupancyRisk(DetectedRoom? room) {
    if (room == null) return 0.5; // Unknown area
    
    final int doorCount = room.doors.length;
    
    // Higher occupancy risk for rooms with more access points
    double occupancyFactor = 0.3 + (doorCount * 0.2);
    
    // Room-specific modifiers
    final String roomName = room.defaultName?.toLowerCase() ?? '';
    if (roomName.contains('hallway') || roomName.contains('corridor')) {
      occupancyFactor *= 1.5; // Higher traffic areas
    }
    
    return math.min(occupancyFactor, 1.0);
  }

  // Main risk calculation function
  double calculateRiskScore(double targetX, double targetY, {List<ExplosionScenario>? explosionScenarios}) {
    // Default explosion scenarios if none provided
    explosionScenarios ??= generateDefaultExplosionScenarios();
    
    double totalRisk = 0;
    final DetectedRoom? targetRoom = getPointRoom(targetX, targetY);
    
    // Check if point is outside the house structure
    bool isOutsideHouse = _isPointOutsideHouse(targetX, targetY);
    
    for (ExplosionScenario scenario in explosionScenarios) {
      final double distance = calculateDistance(targetX, targetY, scenario.x, scenario.y);
      
      // Skip if beyond maximum risk distance
      if (distance > maxRiskDistance) continue;
      
      // Calculate path attenuation
      final double pathAttenuation = calculatePathAttenuation(scenario.x, scenario.y, targetX, targetY);
      
      // Calculate blast pressure
      final double blastPressure = calculateBlastPressure(distance, pathAttenuation, explosiveIntensity: scenario.intensity);
      
      // Apply room-specific modifiers
      double roomModifier = 1.0;
      if (targetRoom != null) {
        roomModifier = roomRiskModifiers[targetRoom.defaultName?.toLowerCase()] ?? 1.0;
      } else if (isOutsideHouse) {
        roomModifier = 0.2; // Much lower risk outside the house structure
      }
      
      // Calculate occupancy risk
      final double occupancyRisk = calculateOccupancyRisk(targetRoom);
      
      // Combine factors
      final double scenarioRisk = blastPressure * roomModifier * occupancyRisk * scenario.probability;
      totalRisk += scenarioRisk;
    }
    
    // Apply MAMAD protection - enhanced protection zones
    final List<Map<String, dynamic>> mamadLocations = getMAMADLocations();
    double mamadProtection = 1.0; // No protection by default
    
    if (mamadLocations.isNotEmpty) {
      for (Map<String, dynamic> mamad in mamadLocations) {
        final double centerX = mamad['centerX'] ?? 0.0;
        final double centerY = mamad['centerY'] ?? 0.0;
        final double minX = mamad['minX'] ?? centerX - 25;
        final double maxX = mamad['maxX'] ?? centerX + 25;
        final double minY = mamad['minY'] ?? centerY - 25;
        final double maxY = mamad['maxY'] ?? centerY + 25;
        
        // Check if point is inside MAMAD rectangle (safest area)
        if (targetX >= minX && targetX <= maxX && targetY >= minY && targetY <= maxY) {
          mamadProtection = 0.02; // 98% risk reduction inside MAMAD
          print('🔒 Point (${targetX.round()}, ${targetY.round()}) is INSIDE MAMAD - maximum protection applied');
          break;
        }
        
        // Check distance from MAMAD center for graduated protection zones
        final double mamadDistance = calculateDistance(targetX, targetY, centerX, centerY);
        
        // Zone 1: Immediate vicinity (reinforced concrete walls provide protection)
        if (mamadDistance < 50) {
          mamadProtection = math.min(mamadProtection, 0.15); // 85% risk reduction
        }
        // Zone 2: Near MAMAD (some structural protection benefit)
        else if (mamadDistance < 80) {
          mamadProtection = math.min(mamadProtection, 0.4); // 60% risk reduction
        }
        // Zone 3: MAMAD influence area (slight protection)
        else if (mamadDistance < 120) {
          mamadProtection = math.min(mamadProtection, 0.7); // 30% risk reduction
        }
      }
      
      // Debug log when MAMAD protection is applied
      if (mamadProtection < 1.0) {
        print('🔒 MAMAD protection applied to point (${targetX.round()}, ${targetY.round()}): ${((1.0 - mamadProtection) * 100).round()}% reduction');
      }
    }
    
    totalRisk *= mamadProtection;
    
    // Additional reduction for points clearly outside the house
    if (isOutsideHouse) {
      totalRisk *= 0.3; // 70% reduction for exterior points
    }
    
    // Normalize to 0-1 scale
    return math.min(totalRisk, 1.0);
  }

  // Helper method to determine if a point is outside the house structure
  bool _isPointOutsideHouse(double x, double y) {
    // If no rooms are detected, assume all points are inside
    if (rooms.isEmpty) return false;
    
    // Check if point is inside any room
    if (getPointRoom(x, y) != null) return false;
    
    // Check if point is near any architectural elements (walls, doors, windows)
    for (ArchitecturalElement element in elements) {
      final bbox = element.bbox;
      final elementX = (bbox['x'] ?? bbox['center_x'] ?? 0).toDouble();
      final elementY = (bbox['y'] ?? bbox['center_y'] ?? 0).toDouble();
      final elementWidth = (bbox['width'] ?? 50).toDouble();
      final elementHeight = (bbox['height'] ?? 50).toDouble();
      
      // Check if point is within expanded bounding box (near structural elements)
      if (x >= elementX - 20 && x <= elementX + elementWidth + 20 &&
          y >= elementY - 20 && y <= elementY + elementHeight + 20) {
        return false; // Point is near structure, consider it inside
      }
    }
    
    // If we have room boundaries, check if point is far from all rooms
    double minDistanceToRoom = double.infinity;
    for (DetectedRoom room in rooms) {
      final bounds = room.boundaries;
      if (bounds.containsKey('x') && bounds.containsKey('y')) {
        final roomX = (bounds['x'] as num).toDouble();
        final roomY = (bounds['y'] as num).toDouble();
        final roomWidth = (bounds['width'] as num? ?? 50).toDouble();
        final roomHeight = (bounds['height'] as num? ?? 50).toDouble();
        
        // Calculate distance to room center
        final roomCenterX = roomX + roomWidth / 2;
        final roomCenterY = roomY + roomHeight / 2;
        final distanceToRoom = calculateDistance(x, y, roomCenterX, roomCenterY);
        
        minDistanceToRoom = math.min(minDistanceToRoom, distanceToRoom);
      }
    }
    
    // If point is very far from any room, consider it outside
    return minDistanceToRoom > 100; // 100 pixels threshold
  }

  // Generate default explosion scenarios
  List<ExplosionScenario> generateDefaultExplosionScenarios() {
    final List<ExplosionScenario> scenarios = [];
    
    // High-risk scenarios at main access points (doors)
    final List<ArchitecturalElement> doors = elements.where((el) => 
        el.type.toLowerCase() == 'door' || el.type.toLowerCase().contains('door')).toList();
    
    if (doors.isNotEmpty) {
      for (ArchitecturalElement door in doors) {
        final double doorX = (door.center['x'] ?? door.bbox['x'] ?? 0).toDouble();
        final double doorY = (door.center['y'] ?? door.bbox['y'] ?? 0).toDouble();
        
        scenarios.add(ExplosionScenario(
          x: doorX,
          y: doorY,
          intensity: 1.0,
          probability: 0.4 / doors.length, // 40% total probability for door attacks
          description: 'Door breach at (${doorX.round()}, ${doorY.round()})',
        ));
      }
    } else {
      // Fallback: create scenarios at image borders if no doors detected
      final width = imageDimensions['width']?.toDouble() ?? 800;
      final height = imageDimensions['height']?.toDouble() ?? 600;
      
      scenarios.addAll([
        ExplosionScenario(x: width * 0.1, y: height * 0.5, intensity: 0.8, probability: 0.1, description: 'Left entry point'),
        ExplosionScenario(x: width * 0.9, y: height * 0.5, intensity: 0.8, probability: 0.1, description: 'Right entry point'),
        ExplosionScenario(x: width * 0.5, y: height * 0.1, intensity: 0.8, probability: 0.1, description: 'Top entry point'),
        ExplosionScenario(x: width * 0.5, y: height * 0.9, intensity: 0.8, probability: 0.1, description: 'Bottom entry point'),
      ]);
    }
    
    // Medium-risk scenarios at windows (external threats)
    final List<ArchitecturalElement> windows = elements.where((el) => 
        el.type.toLowerCase() == 'window' || el.type.toLowerCase().contains('window')).toList();
    
    if (windows.isNotEmpty) {
      for (ArchitecturalElement window in windows) {
        final double windowX = (window.center['x'] ?? window.bbox['x'] ?? 0).toDouble();
        final double windowY = (window.center['y'] ?? window.bbox['y'] ?? 0).toDouble();
        
        scenarios.add(ExplosionScenario(
          x: windowX,
          y: windowY,
          intensity: 0.7,
          probability: 0.3 / windows.length, // 30% total probability for window attacks
          description: 'Window breach at (${windowX.round()}, ${windowY.round()})',
        ));
      }
    }
    
    // High-risk scenarios in room centers (especially hallways/corridors)
    for (DetectedRoom room in rooms) {
      final bounds = room.boundaries;
      if (bounds.containsKey('x') && bounds.containsKey('y') && 
          bounds.containsKey('width') && bounds.containsKey('height')) {
        final double centerX = (bounds['x'] as num).toDouble() + (bounds['width'] as num).toDouble() / 2;
        final double centerY = (bounds['y'] as num).toDouble() + (bounds['height'] as num).toDouble() / 2;
        
        double intensity = 0.5; // Base intensity for room centers
        double probability = 0.3 / rooms.length; // 30% total probability
        
        // Higher intensity for high-traffic areas
        final roomName = room.defaultName?.toLowerCase() ?? '';
        if (roomName.contains('hallway') || roomName.contains('corridor') || 
            roomName.contains('entrance') || roomName.contains('lobby')) {
          intensity = 0.9;
          probability *= 2; // Double probability for high-traffic areas
        }
        
        scenarios.add(ExplosionScenario(
          x: centerX,
          y: centerY,
          intensity: intensity,
          probability: probability,
          description: 'Interior threat in ${room.defaultName ?? 'unknown room'}',
        ));
      }
    }
    
    return scenarios;
  }

  // Generate risk heatmap for entire floor plan
  List<List<RiskPoint>> generateRiskHeatmap({int gridSize = 10}) {
    final List<List<RiskPoint>> heatmap = [];
    final int width = imageDimensions['width'] ?? 800;
    final int height = imageDimensions['height'] ?? 600;
    
    for (int y = 0; y < height; y += gridSize) {
      final List<RiskPoint> row = [];
      for (int x = 0; x < width; x += gridSize) {
        final double risk = calculateRiskScore(x.toDouble(), y.toDouble());
        row.add(RiskPoint(
          x: x.toDouble(),
          y: y.toDouble(),
          risk: risk,
          riskLevel: getRiskLevel(risk),
        ));
      }
      heatmap.add(row);
    }
    
    return heatmap;
  }

  // Categorize risk levels
  String getRiskLevel(double riskScore, {double? x, double? y}) {
    // Special handling for MAMAD areas - always safest
    if (x != null && y != null && isPointInsideMAMAD(x, y)) {
      return 'MINIMAL'; // MAMAD is always the safest area
    }
    
    if (riskScore >= 0.8) return 'CRITICAL';
    if (riskScore >= 0.6) return 'HIGH';
    if (riskScore >= 0.4) return 'MEDIUM';
    if (riskScore >= 0.2) return 'LOW';
    return 'MINIMAL';
  }

  // Get evacuation recommendations for a point
  String getEvacuationRecommendations(double x, double y) {
    final DetectedRoom? room = getPointRoom(x, y);
    final List<Map<String, dynamic>> mamadLocations = getMAMADLocations();
    
    if (room == null) return "Move to nearest identified safe room";
    
    // Find nearest MAMAD
    Map<String, dynamic>? nearestMAMAD;
    double minDistance = double.infinity;
    
    for (Map<String, dynamic> mamad in mamadLocations) {
      final double centerX = mamad['centerX'] ?? 0.0;
      final double centerY = mamad['centerY'] ?? 0.0;
      final double distance = calculateDistance(x, y, centerX, centerY);
      if (distance < minDistance) {
        minDistance = distance;
        nearestMAMAD = mamad;
      }
    }
    
    if (nearestMAMAD != null && minDistance < 100) {
      final double centerX = nearestMAMAD['centerX'] ?? 0.0;
      final double centerY = nearestMAMAD['centerY'] ?? 0.0;
      return 'Evacuate to nearest MAMAD at (${centerX.round()}, ${centerY.round()}) - Distance: ${(imageToMeters(minDistance) * 100).round()}cm';
    }
    
    // Alternative: find exits
    final List<ArchitecturalElement> exits = room.doors;
    if (exits.length > 1) {
      return 'Multiple exits available - use furthest from potential threat source';
    } else if (exits.length == 1) {
      return 'Single exit available - assess situation before evacuation';
    } else {
      return 'No direct exits detected - seek alternative escape route';
    }
  }
}

class ExplosionScenario {
  final double x;
  final double y;
  final double intensity;
  final double probability;
  final String description;

  ExplosionScenario({
    required this.x,
    required this.y,
    required this.intensity,
    required this.probability,
    required this.description,
  });
}

class RiskPoint {
  final double x;
  final double y;
  final double risk;
  final String riskLevel;

  RiskPoint({
    required this.x,
    required this.y,
    required this.risk,
    required this.riskLevel,
  });
}

class RiskGridPoint {
  final double x;
  final double y;
  final double riskScore;
  final String riskLevel;
  final Color color;

  RiskGridPoint({
    required this.x,
    required this.y,
    required this.riskScore,
    required this.riskLevel,
    required this.color,
  });
}

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
  late ScrollController _vitalInfoScrollController;
  final GlobalKey _houseThicknessKey = GlobalKey();
  
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
  
  // Risk heatmap refresh state
  int _riskHeatmapRefreshKey = 0;
  
  // Performance optimization - cache heavy computations
  List<List<RiskGridPoint>>? _cachedRiskGrid;
  bool _isRiskGridGenerating = false;
  
  // Method to invalidate risk cache when annotations change
  void _invalidateRiskCache() {
    if (_cachedRiskGrid != null) {
      print('🔄 Risk cache invalidated due to annotation changes');
      _cachedRiskGrid = null;
    }
  }

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
    _tabController = TabController(length: 3, vsync: this);
    _vitalInfoScrollController = ScrollController();
    
    // Tab controller initialized - no special listeners needed
    
    // Show tutorial popup after a short delay when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _showTutorialPopup(context);
        }
      });
    });
    
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
    _vitalInfoScrollController.dispose();
    
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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0D47A1), // Deep blue
              const Color(0xFF1565C0), // Primary blue
              const Color(0xFF1976D2), // Lighter blue
            ],
          ),
        ),
        child: Stack(
          children: [
            // Main Content
            Column(
              children: [
                // Custom App Bar with glass effect
                _buildGlassAppBar(context),
                
                // Floating Circular Tabs
                _buildFloatingTabs(context),
                
                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildAnalysisView(),
                      _buildAnnotationView(),
                      _buildVitalInfoView(),
                    ],
                  ),
                ),
              ],
            ),
            
            // Always visible Next button at the bottom
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.blue[700]!.withOpacity(0.35),
                            Colors.blue[800]!.withOpacity(0.25),
                            Colors.white.withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.blue[800]!.withOpacity(0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue[700]!.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, -1),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _navigateToRiskAssessment,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[700]!.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.blue[800]!.withOpacity(0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward,
                                    size: 24,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Next: Risk Assessment',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      //bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildGlassAppBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              'Enhanced Detection Results',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _isEditingRoomInfo ? Icons.save : Icons.edit,
              color: Colors.white,
            ),
            onPressed: _toggleEditMode,
            tooltip: _isEditingRoomInfo ? 'Save Changes' : 'Edit Room Info',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: _showAnalysisInfo,
            tooltip: 'Analysis Information',
          ),
          // Next button to navigate to Risk Assessment
          Container(
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1976D2),
                  Color(0xFF1565C0),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _navigateToRiskAssessment,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Next',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingTabs(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFloatingTab(
            context,
            0,
            Icons.analytics,
            'Analysis',
          ),
          _buildFloatingTab(
            context,
            1,
            Icons.draw,
            'Annotate',
          ),
          _buildFloatingTab(
            context,
            2,
            Icons.home_outlined,
            'Vital Info',
            ),
          ],
        ),
    );
  }

  Widget _buildFloatingTab(BuildContext context, int index, IconData icon, String label) {
    final bool isSelected = _tabController.index == index;
    
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected 
            ? Colors.white.withOpacity(0.3)
            : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected 
              ? Colors.white.withOpacity(0.5)
              : Colors.white.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.white.withOpacity(0.2),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 0),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ] : [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
        children: [
            Icon(
              icon,
              color: Colors.white,
              size: isSelected ? 28 : 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: isSelected ? 14 : 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTutorialPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (BuildContext context) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 600),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: (0.8 + (0.2 * value)).clamp(0.8, 1.0),
              child: Transform.translate(
                offset: Offset(0, 50 * (1 - value)),
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 600, minWidth: 320),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 320, maxWidth: 600),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Stage badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1565C0),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'STAGE 2',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Icon container
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1565C0).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.analytics_outlined,
                                  color: Color(0xFF1565C0),
                                  size: 50,
                                ),
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Title
                              Text(
                                'Enhanced Detection Results',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              
                              const SizedBox(height: 12),
                              
                              // Description
                              Text(
                                'Review your floor plan analysis results and explore detailed safety assessments for each detected area.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              
                              const SizedBox(height: 28),
                              
                              // How it works section
                              Align(
                                alignment: Alignment.centerLeft,
                                child: AutoSizeText(
                                  'How it works:',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  minFontSize: 12,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              
                              const SizedBox(height: 18),
                              
                              // Steps
                              _buildNumberedStepInline(
                                1,
                                'Analysis Tab',
                                'View detected rooms, safety scores, and detailed risk assessments',
                              ),
                              
                              const SizedBox(height: 14),
                              
                              _buildNumberedStepInline(
                                2,
                                'Annotate Tab',
                                'Add custom annotations and mark MAMAD locations on your floor plan',
                              ),
                              
                              const SizedBox(height: 14),
                              
                              _buildNumberedStepInline(
                                3,
                                'Vital Info Tab',
                                'Access emergency contacts, evacuation routes, and critical safety data',
                              ),
                              
                              const SizedBox(height: 36),
                              
                              // Action Buttons
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Skip Tutorial Button
                                  Expanded(
                                    child: Container(
                                      height: 54,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(25),
                                        border: Border.all(
                                          color: const Color(0xFF1565C0),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(25),
                                          onTap: () => Navigator.of(context).pop(),
                                          child: Center(
                                            child: AutoSizeText(
                                              'Skip Tutorial',
                                              style: TextStyle(
                                                color: const Color(0xFF1565C0),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                              ),
                                              maxLines: 1,
                                              minFontSize: 12,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(width: 16),
                                  
                                  // Got it Button
                                  Expanded(
                                    child: Container(
                                      height: 54,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(25),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF1565C0), // Primary blue
                                            Color(0xFF1976D2), // Lighter blue
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF1565C0).withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(25),
                                          onTap: () => Navigator.of(context).pop(),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              AutoSizeText(
                                                'Got it!',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                minFontSize: 12,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.arrow_forward,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNumberedStepInline(int step, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AutoSizeText(
                title,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                maxLines: 1,
                minFontSize: 12,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              AutoSizeText(
                description,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  height: 1.3,
                ),
                maxLines: 2,
                minFontSize: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisView() {
    final isCompact = MediaQuery.of(context).size.width < 690;
    
    return Column(
      children: [
        _buildSummaryCard(),
        Expanded(
          child: Row(
            children: [
              // Left panel - Room list (narrower on small screens)
              Expanded(
                flex: isCompact ? 1 : 1,
                child: _buildRoomList(),
              ),
              // Right panel - Room details (wider on small screens)
              Expanded(
                flex: isCompact ? 3 : 2,
                child: _buildRoomDetails(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoomList() {
    final allRooms = _getAllRooms();
    final isCompact = MediaQuery.of(context).size.width < 450;
    
    return SizedBox(
      width: isCompact ? 60 : null,
      child: Container(
        margin: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.25),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (MediaQuery.of(context).size.width >= 690)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text(
                          'All Rooms (${allRooms.length})',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
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
                      final isCompact = MediaQuery.of(context).size.width < 450;
                      
                      if (isCompact) {
                        // Compact layout - just the circle
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedRoomIndex = index;
                              });
                            },
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              padding: const EdgeInsets.all(8.0),
                              child: Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: isSelected 
                                          ? (isUserDrawn ? Colors.green : Colors.blue)
                                          : Colors.grey.shade300,
                                      child: Text(
                                        (index + 1).toString(),
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    if (isUserDrawn)
                                      Positioned(
                                        top: -2,
                                        right: -2,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 1),
                                          ),
                                          child: Icon(
                                            Icons.edit,
                                            size: 10,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        // Full layout - ListTile with all details
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
                                    color: isUserDrawn ? Colors.green[800] : Colors.white,
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
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildSummaryCard() {
    final combinedCounts = _getCombinedElementCounts();
    
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // User annotations badge (if any)
                if (_userAnnotations.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Icon(Icons.edit, size: 14, color: Colors.green[300]),
                    const SizedBox(width: 6),
                        Text(
                          '${_userAnnotations.length} user additions',
                          style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[300],
                        fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
            const SizedBox(height: 16),
          ],
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
            Center(
              child: Text(
              _getAnnotationSummary(),
              style: Theme.of(context).textTheme.bodyMedium,
              ),
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
    );
    // );
  }

  Widget _buildEnhancedSummaryItem(String label, String value, IconData icon, int aiCount, int userCount) {
    return Expanded(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 28, color: Colors.white.withOpacity(0.9)),
              if (userCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13, 
              color: Colors.white.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
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

  Widget _buildRoomDetails() {
    final allRooms = _getAllRooms();
    
    if (allRooms.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(8.0),
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.25),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Text('No rooms detected', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final room = allRooms[_selectedRoomIndex];
    final isUserDrawn = room['isUserDrawn'] as bool;

    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.25),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                          Text(
                            room['defaultName'] as String,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: isUserDrawn ? Colors.green[800] : Colors.white,
                            ),
                          ),
                          Text(
                            'Detection Method: ${room['detectionMethod'] as String}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isUserDrawn ? Colors.green[600] : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text('${((room['confidence'] as double) * 100).toStringAsFixed(0)}%'),
                          backgroundColor: _getConfidenceColor(room['confidence'] as double).withOpacity(0.2),
                          labelStyle: TextStyle(color: _getConfidenceColor(room['confidence'] as double)),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _editRoomInfo('room_details'),
                          icon: Icon(Icons.edit, color: Colors.white70, size: 18),
                          tooltip: 'Edit Room Information',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                        _buildUserRoomNameField(room),
                        const SizedBox(height: 8),
                        _buildUserRoomDescriptionField(room),
                        const SizedBox(height: 8),
                        ..._buildUserRoomDetails(room['roomData']),
                      ],
                    ),
                  ),
                ] else ...[
                  Text(
                    room.containsKey('description') ? room['description'] as String : 'No description available',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ],
                const SizedBox(height: 16),
                if (!isUserDrawn) ...[
                  _buildArchitecturalElementsSection('Doors', (room['doors'] as List<dynamic>).cast<ArchitecturalElement>(), Icons.door_front_door, Colors.orange),
                  _buildArchitecturalElementsSection('Windows', (room['windows'] as List<dynamic>).cast<ArchitecturalElement>(), Icons.window, Colors.blue),
                  _buildArchitecturalElementsSection('Walls', (room['walls'] as List<dynamic>).cast<ArchitecturalElement>(), Icons.wallpaper, Colors.grey),
                  if ((room['estimatedDimensions'] as Map<String, dynamic>).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildDimensionsSection(room['estimatedDimensions'] as Map<String, double>),
                  ],
                  // const SizedBox(height: 16),
                  // _buildBoundariesSection(room['boundaries'] as Map<String, dynamic>),
                ] else ...[
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
                const SizedBox(height: 16),
                _buildWallThicknessAnalysisSection(room),
              ],
            ),
          ),
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
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AutoSizeText(
                        '$title (${elements.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        minFontSize: 12,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...elements.map((element) => _buildElementCard(element, color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildElementCard(ArchitecturalElement element, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 8, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: AutoSizeText(
                    element.type,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    minFontSize: 10,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AutoSizeText(
                  '${(element.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: _getConfidenceColor(element.confidence),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  minFontSize: 8,
                ),
              ],
            ),
            const SizedBox(height: 4),
            AutoSizeText(
              'Position: ${element.relativePosition}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              maxLines: 1,
              minFontSize: 8,
              overflow: TextOverflow.ellipsis,
            ),
            AutoSizeText(
              'Size: ${element.dimensions['width']} × ${element.dimensions['height']} px',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              maxLines: 1,
              minFontSize: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionsSection(Map<String, double> dimensions) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.straighten, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AutoSizeText(
                        'Estimated Dimensions',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        minFontSize: 12,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...dimensions.entries.map((entry) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: AutoSizeText(
                          '${entry.key}: ',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                          maxLines: 1,
                          minFontSize: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: AutoSizeText(
                          '${entry.value.toStringAsFixed(2)} m',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          minFontSize: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ),
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

 Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }
  

  void _toggleEditMode() {
    setState(() {
      _isEditingRoomInfo = !_isEditingRoomInfo;
    });
  }

  void _editRoomInfo(String sectionType) {
    final allRooms = _getAllRooms();
    if (allRooms.isEmpty) return;
    
    final room = allRooms[_selectedRoomIndex];
    final roomName = room['defaultName'] as String;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String editedName = roomName;
        String editedDescription = room.containsKey('description') ? room['description'] as String : '';
        
        return AlertDialog(
          backgroundColor: Colors.grey.withOpacity(0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Edit Room Information',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Room Name',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
                style: TextStyle(color: Colors.white),
                controller: TextEditingController(text: editedName),
                onChanged: (value) => editedName = value,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
                style: TextStyle(color: Colors.white),
                controller: TextEditingController(text: editedDescription),
                onChanged: (value) => editedDescription = value,
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  room['defaultName'] = editedName;
                  room['description'] = editedDescription;
                });
                Navigator.of(context).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Room information updated successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
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

    return SingleChildScrollView(
      controller: _vitalInfoScrollController,
      child: Column(
        children: [
          // Glossy House Boundary Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange.withOpacity(0.1),
                  Colors.orange.withOpacity(0.05),
                  Colors.white.withOpacity(0.1),
                ],
              ),
              border: Border.all(
                color: Colors.orange.withOpacity(0.3),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Centered Icon and Text
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.home_work_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'House Boundary',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select the house boundary as close as possible to the actual building perimeter',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              
                const SizedBox(height: 20),
              
                // Action Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_hasHouseBoundary)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: IconButton(
                          onPressed: _clearHouseBoundary,
                          icon: Icon(Icons.clear, color: Colors.red[400], size: 24),
                          tooltip: 'Clear Boundary',
                        ),
                      ),
                    if (_hasHouseBoundary) const SizedBox(width: 16),
                    if (_hasHouseBoundary && !_isDrawingHouseBoundary)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                        ),
                        child: IconButton(
                          onPressed: _editHouseBoundary,
                          icon: Icon(Icons.edit, color: Colors.blue[400], size: 24),
                          tooltip: 'Edit Boundary',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        
          // Image Container with Reserved Space for Finish Button
          Container(
            height: MediaQuery.of(context).size.height * 0.5, // Fixed height for image
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Container(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildHouseBoundaryImageWidget(_result.originalImageBase64!),
              ),
            ),
          ),
              
          // Reserved Space for Finish Button (always present)
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isDrawingHouseBoundary && _houseBoundaryPoints.length >= 3
                  ? Container(
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 280,
                            minWidth: 200,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.blue[400]!,
                                Colors.blue[600]!,
                                Colors.blue[800]!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.4),
                                blurRadius: 15,
                                offset: const Offset(0, 6),
                              ),
                              BoxShadow(
                                color: Colors.white.withOpacity(0.1),
                                blurRadius: 2,
                                offset: const Offset(0, -1),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _finishHouseBoundary,
                            icon: const Icon(
                              Icons.arrow_downward,
                              size: 22,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Next: Wall Details',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      child: Center(
                        child: Text(
                          _isDrawingHouseBoundary 
                              ? 'Add more points to complete the boundary'
                              : (_houseBoundaryPoints.isEmpty && !_isDrawingHouseBoundary && !_hasHouseBoundary)
                                  ? 'Click on the image to start drawing the house perimeter'
                                  : '',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                ),
              ),
            
          // Animated Wall Details Sections
          if (_hasHouseBoundary) ...[
            AnimatedSlide(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              offset: Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 600),
                opacity: 1.0,
                child: Column(
                  children: [
                    // Futuristic Glassy Wall Thickness Section
                    Container(
                      key: _houseThicknessKey,
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.deepPurple.withOpacity(0.1),
                            Colors.deepPurple.withOpacity(0.05),
                            Colors.white.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.deepPurple.withOpacity(0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.deepPurple.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, -1),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.architecture,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'House Wall Thickness',
                                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Measure the thickness of your house\'s outer perimeter walls',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _buildHouseWallThicknessSection(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  
                    // Futuristic Glassy Material Selection Section
                    Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.blue.withOpacity(0.1),
                            Colors.blue.withOpacity(0.05),
                            Colors.white.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, -1),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.construction,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'House Material Selection',
                                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'What material is your house exterior made of?',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _buildMaterialSelection(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
      ),
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
              'No Detection Image Available',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Clean Glassy Toolbar with Scrollable Tools
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Scrollable Tools Section
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildGlassyToolButtonWithTitle('wall', Icons.line_style, Colors.green, 'Wall'),
                      const SizedBox(width: 12),
                      _buildGlassyToolButtonWithTitle('window', Icons.window, Colors.blue, 'Window'),
                      const SizedBox(width: 12),
                      _buildGlassyToolButtonWithTitle('door', Icons.door_front_door, Colors.orange, 'Door'),
                      const SizedBox(width: 12),
                      _buildGlassyToolButtonWithTitle('column', Icons.view_column, Colors.red, 'Column'),
                      const SizedBox(width: 12),
                      _buildEnhancedGlassyToolButton('stairway', Icons.stairs, Colors.purple, 'Stairway'),
                      const SizedBox(width: 12),
                      _buildEnhancedGlassyToolButton('mamad', Icons.security, Colors.pink, 'MAMAD'),
                      const SizedBox(width: 12),
                      _buildRoomGlassyToolButton(),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Anchored Action Buttons
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _userAnnotations.isNotEmpty ? _undoLastAnnotation : null,
                      icon: Icon(
                        Icons.undo,
                        color: _userAnnotations.isNotEmpty ? Colors.white : Colors.white54,
                        size: 20,
                      ),
                      tooltip: 'Undo',
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _currentDrawingTool = 'eraser';
                        _currentDrawingColor = Colors.grey;
                      }),
                      icon: Icon(
                        Icons.delete_forever,
                        color: _currentDrawingTool == 'eraser' ? Colors.red : Colors.white70,
                        size: 20,
                      ),
                      tooltip: 'Eraser',
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    IconButton(
                      onPressed: _hasUnsavedAnnotations ? _saveAnnotations : null,
                      icon: Icon(
                        Icons.save,
                        color: _hasUnsavedAnnotations ? Colors.green : Colors.white54,
                        size: 20,
                      ),
                      tooltip: 'Save',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Image Area
        Expanded(
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildDrawableImageWidget(_result.annotatedImageBase64!),
                  ),
                ),
              ),
              if (_showDrawingControls && (_currentDrawingTool == 'stairway' || _currentDrawingTool == 'mamad')) 
                _buildFloatingEnhancedControls(),
              if (_showRoomTypeSelector && _currentDrawingTool == 'room')
                _buildFloatingRoomControls(),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildGlassyToolButtonWithTitle(String tool, IconData icon, Color color, String title) {
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
          color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? color : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? color : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedGlassyToolButton(String tool, IconData icon, Color color, String title) {
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
          color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ] : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? color : Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? color : Colors.white70,
                  ),
                ),
                if (isSelected && _showDrawingControls) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more,
                    size: 14,
                    color: isSelected ? color : Colors.white70,
                  ),
                ],
              ],
            ),
            if (isSelected && _showDrawingControls) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDrawingModeButton('rectangle', Icons.crop_free, 'Rect'),
                  const SizedBox(width: 4),
                  _buildDrawingModeButton('polygon', Icons.polyline, 'Poly'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoomGlassyToolButton() {
    final isSelected = _currentDrawingTool == 'room';
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentDrawingTool = 'room';
          _currentDrawingColor = Colors.teal;
          _showRoomTypeSelector = isSelected ? !_showRoomTypeSelector : true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal.withOpacity(0.2) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.teal : Colors.white.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.teal.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ] : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.meeting_room,
                  size: 18,
                  color: isSelected ? Colors.teal : Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  'Room',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.teal : Colors.white70,
                  ),
                ),
                if (isSelected && _showRoomTypeSelector) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more,
                    size: 14,
                    color: isSelected ? Colors.teal : Colors.white70,
                  ),
                ],
              ],
            ),
            if (isSelected && _showRoomTypeSelector) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDrawingModeButton('rectangle', Icons.crop_free, 'Rect'),
                  const SizedBox(width: 4),
                  _buildDrawingModeButton('polygon', Icons.polyline, 'Poly'),
                ],
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
        _invalidateRiskCache(); // Invalidate risk cache when annotations are removed
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
        _invalidateRiskCache(); // Invalidate risk cache when annotations are removed
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
        _invalidateRiskCache(); // Invalidate risk cache when new annotations are added
      });
      
      print('🎨 Enhanced $tool rectangle completed with area ${tool == 'mamad' ? (annotation['roomData'] as Map)['area'] : 'N/A'}');
    }
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
        _invalidateRiskCache(); // Invalidate risk cache when new annotations are added
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
      _invalidateRiskCache(); // Invalidate risk cache when new annotations are added
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
            _invalidateRiskCache(); // Invalidate risk cache when new annotations are added
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
      _invalidateRiskCache(); // Invalidate risk cache when new annotations are added
      _currentStroke = [];
      _isDrawingRoom = false;
      _hasUnsavedAnnotations = true;
    });
    
    print('🏠 Local room created: $_selectedRoomType with area ${(roomAnnotation['roomData'] as Map)['area']}');
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
      
      // Scroll smoothly to the house thickness section after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        _scrollToHouseThickness();
      });
    }
  }

  void _scrollToHouseThickness() {
    if (_houseThicknessKey.currentContext != null) {
      final RenderBox renderBox = _houseThicknessKey.currentContext!.findRenderObject() as RenderBox;
      final position = renderBox.localToGlobal(Offset.zero);
      
      // Account for the floating tabs bar height and some additional padding
      // Floating tabs container has padding (12 vertical) + tab height (~60px) + app bar
      final topBarOffset = 200.0; // Generous offset to account for floating tabs and app bar
      final scrollPosition = _vitalInfoScrollController.offset + position.dy - topBarOffset;

      _vitalInfoScrollController.animateTo(
        scrollPosition,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
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

  // Build material selection widget with futuristic square containers
  Widget _buildMaterialSelection() {
    final totalPercentage = _selectedHouseMaterials.values.fold(0.0, (a, b) => a + b);
    
    return Column(
      children: [
        // Futuristic Progress Indicator
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                totalPercentage == 100 
                    ? Colors.green.withOpacity(0.2)
                    : totalPercentage > 100 
                        ? Colors.red.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                totalPercentage == 100 
                    ? Colors.green.withOpacity(0.1)
                    : totalPercentage > 100 
                        ? Colors.red.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: totalPercentage == 100 
                  ? Colors.green.withOpacity(0.4)
                  : totalPercentage > 100 
                      ? Colors.red.withOpacity(0.4)
                      : Colors.orange.withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: totalPercentage == 100 
                    ? Colors.green.withOpacity(0.3)
                    : totalPercentage > 100 
                        ? Colors.red.withOpacity(0.3)
                        : Colors.orange.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: totalPercentage == 100 
                      ? Colors.green.withOpacity(0.3)
                      : totalPercentage > 100 
                          ? Colors.red.withOpacity(0.3)
                          : Colors.orange.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  totalPercentage == 100 ? Icons.check_circle : Icons.pie_chart,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total: ${totalPercentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (totalPercentage / 100).clamp(0.0, 1.0),
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation(
                        totalPercentage == 100 
                            ? Colors.green
                            : totalPercentage > 100 
                                ? Colors.red
                                : Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalPercentage == 100 
                          ? 'Complete'
                          : totalPercentage > 100 
                              ? 'Over 100%'
                              : '${(100 - totalPercentage).toStringAsFixed(0)}% left',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        
        // Futuristic Material Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: _selectedHouseMaterials.isNotEmpty ? 0.85 : 1.0,
          ),
          itemCount: _israeliHouseMaterials.length,
          itemBuilder: (context, index) {
            final material = _israeliHouseMaterials[index];
            final materialName = material['name'] as String;
            final isSelected = _selectedHouseMaterials.containsKey(materialName);
            
            // Initialize controller if not exists
            if (!_percentageControllers.containsKey(materialName)) {
              _percentageControllers[materialName] = TextEditingController();
            }
            
            return GestureDetector(
              onTap: () => _toggleMaterial(materialName),
              child: AnimatedScale(
                scale: isSelected ? 1.02 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected 
                        ? Colors.white.withOpacity(0.6)
                        : Colors.white.withOpacity(0.3),
                    width: isSelected ? 2.0 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected 
                          ? Colors.white.withOpacity(0.3)
                          : Colors.white.withOpacity(0.1),
                      blurRadius: isSelected ? 20 : 10,
                      offset: isSelected ? const Offset(0, 8) : const Offset(0, 4),
                      spreadRadius: isSelected ? 2 : 0,
                    ),
                    if (isSelected)
                      BoxShadow(
                        color: Colors.white.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, -2),
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Material Icon
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected 
                              ? Border.all(color: Colors.white.withOpacity(0.4), width: 1)
                              : null,
                        ),
                        child: Icon(
                          material['icon'] as IconData,
                          color: Colors.white,
                          size: isSelected ? 30 : 28,
                        ),
                      ),
                      const SizedBox(height: 4),
                      
                      // Material Title
                      Text(
                        material['name'],
                        style: TextStyle(
                          fontSize: isSelected ? 13 : 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      
                      // Hebrew Name
                      Text(
                        material['hebrew'],
                        style: TextStyle(
                          fontSize: isSelected ? 12 : 11,
                          color: isSelected ? Colors.white.withOpacity(0.8) : Colors.white70,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      // Percentage Input (if selected)
                      if (isSelected) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _percentageControllers[materialName],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '0',
                                    hintStyle: TextStyle(color: Colors.white60, fontSize: 12),
                                    border: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white, width: 1),
                                    ),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white, width: 1),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white, width: 2),
                                    ),
                                    filled: false,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  ),
                                  onChanged: (value) => _updatePercentage(materialName, value),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            );
          },
        ),
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

  // Check if all vital information is complete
  bool _isVitalInfoComplete() {
    // Check if house boundary exists
    if (!_hasHouseBoundary) return false;
    
    // Check if materials total 100%
    final totalPercentage = _selectedHouseMaterials.values.fold(0.0, (a, b) => a + b);
    if (totalPercentage != 100.0) return false;
    
    // Check if house wall thickness is measured
    if (_houseWallThicknessResults.isEmpty) return false;
    
    return true;
  }

  // Navigate to risk assessment screen
  void _navigateToRiskAssessment() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RiskAssessmentScreen(
          detectionResult: _result,
          userAnnotations: _userAnnotations,
          selectedHouseMaterials: _selectedHouseMaterials,
          houseBoundaryPoints: _houseBoundaryPoints,
        ),
      ),
    );
  }

  // Add new method for wall thickness analysis section
  Widget _buildWallThicknessAnalysisSection(Map<String, dynamic> room) {
    final roomId = room['roomId']?.toString() ?? room['id']?.toString() ?? '';
    final wallThicknessData = _wallThicknessResults[roomId];
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.architecture, color: Colors.deepPurple, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AutoSizeText(
                        'Wall Thickness Analysis',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        minFontSize: 12,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Wall thickness analysis card
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.camera_alt, color: Colors.deepPurple[600], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AutoSizeText(
                                'Measure Wall Thickness',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                minFontSize: 12,
                                overflow: TextOverflow.ellipsis,
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
                                    AutoSizeText(
                                      'Analyzed',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      minFontSize: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        AutoSizeText(
                          'Take a photo of a door or window frame to measure wall thickness using AI depth analysis.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                          maxLines: 2,
                          minFontSize: 10,
                          overflow: TextOverflow.ellipsis,
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
                                    Expanded(
                                      child: AutoSizeText(
                                        'Analysis Results',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        minFontSize: 12,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                // Wall thickness result
                                Row(
                                  children: [
                                    const Text('Wall Thickness: ', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                    Expanded(
                                      child: AutoSizeText(
                                        '${wallThicknessData['wall_thickness_cm']} cm',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        minFontSize: 10,
                                        overflow: TextOverflow.ellipsis,
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
                                        child: AutoSizeText(
                                          'Manual',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.orange[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          minFontSize: 8,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                
                                // Confidence level
                                Row(
                                  children: [
                                    const Text('Confidence: ', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                    Expanded(
                                      child: AutoSizeText(
                                        '${(wallThicknessData['confidence'] * 100).toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _getConfidenceColor(wallThicknessData['confidence']),
                                        ),
                                        maxLines: 1,
                                        minFontSize: 10,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                
                                // Measurement points
                                Row(
                                  children: [
                                    const Text('Measurement Points: ', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                    Expanded(
                                      child: AutoSizeText(
                                        '${wallThicknessData['measurement_points']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        minFontSize: 10,
                                        overflow: TextOverflow.ellipsis,
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
                                      color: Colors.white70,
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
            ),
          ),
        ),
      ),
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
    
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.25),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: SingleChildScrollView(
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

/// Custom painter for drawing risk heatmap overlay
class RiskHeatmapPainter extends CustomPainter {
  final List<List<RiskGridPoint>> riskGrid;
  final double imageWidth;
  final double imageHeight;
  final double containerWidth;
  final double containerHeight;

  RiskHeatmapPainter({
    required this.riskGrid,
    required this.imageWidth,
    required this.imageHeight,
    required this.containerWidth,
    required this.containerHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (riskGrid.isEmpty || size.width <= 0 || size.height <= 0) return;
    if (imageWidth <= 0 || imageHeight <= 0) return;

    // Calculate scaling factors to map grid coordinates to display coordinates
    double scaleX = size.width / imageWidth;
    double scaleY = size.height / imageHeight;
    
    // Use the smaller scale to maintain aspect ratio
    double scale = math.min(scaleX, scaleY);
    
    // Ensure scale is valid
    if (scale <= 0 || !scale.isFinite) return;
    
    // Calculate offset to center the image
    double offsetX = (size.width - imageWidth * scale) / 2;
    double offsetY = (size.height - imageHeight * scale) / 2;

    // Draw risk points
    for (List<RiskGridPoint> row in riskGrid) {
      for (RiskGridPoint point in row) {
        // Transform grid coordinates to screen coordinates
        double screenX = point.x * scale + offsetX;
        double screenY = point.y * scale + offsetY;
        
        // Skip points that are outside the visible area
        if (screenX < 0 || screenX > size.width || screenY < 0 || screenY > size.height) {
          continue;
        }

        // Create paint for this risk point
        final paint = Paint()
          ..color = point.color.withOpacity(0.7)
          ..style = PaintingStyle.fill;

        // Draw point as a small circle, scaled appropriately
        final double pointSize = _getPointSize(point.riskLevel) * scale;
        canvas.drawCircle(
          Offset(screenX, screenY),
          pointSize,
          paint,
        );

        // Draw border for better visibility
        final borderPaint = Paint()
          ..color = point.color.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

        canvas.drawCircle(
          Offset(screenX, screenY),
          pointSize,
          borderPaint,
        );

        // For critical and high risk points, add a pulsing effect indicator
        if (point.riskLevel == 'CRITICAL' || point.riskLevel == 'HIGH') {
          final pulseColor = point.riskLevel == 'CRITICAL' ? Colors.red : Colors.orange;
          final pulsePaint = Paint()
            ..color = pulseColor.withOpacity(0.3)
            ..style = PaintingStyle.fill;

          canvas.drawCircle(
            Offset(screenX, screenY),
            pointSize * 1.5,
            pulsePaint,
          );
        }
      }
    }

    // Draw risk score text for high-risk points (optional, for debugging)
    if (riskGrid.isNotEmpty && riskGrid.first.isNotEmpty && scale > 0.5) {
      final textStyle = TextStyle(
        color: Colors.black,
        fontSize: 8 * scale,
        background: Paint()..color = Colors.white.withOpacity(0.8),
      );

      for (List<RiskGridPoint> row in riskGrid) {
        for (RiskGridPoint point in row) {
          // Only show text for critical points to avoid clutter, and only if grid is not too dense
          if (point.riskLevel == 'CRITICAL') {
            double screenX = point.x * scale + offsetX;
            double screenY = point.y * scale + offsetY;
            
            // Skip if outside visible area
            if (screenX < 0 || screenX > size.width || screenY < 0 || screenY > size.height) {
              continue;
            }
            
            final textSpan = TextSpan(
              text: '${(point.riskScore * 100).round()}',
              style: textStyle,
            );
            final textPainter = TextPainter(
              text: textSpan,
              textDirection: TextDirection.ltr,
            );
            textPainter.layout();
            textPainter.paint(
              canvas,
              Offset(
                screenX - textPainter.width / 2,
                screenY - textPainter.height / 2,
              ),
            );
          }
        }
      }
    }
  }

  double _getPointSize(String riskLevel) {
    switch (riskLevel) {
      case 'CRITICAL':
        return 6.0;
      case 'HIGH':
        return 5.0;
      case 'MEDIUM':
        return 4.0;
      case 'LOW':
        return 3.0;
      case 'MINIMAL':
        return 2.5;
      default:
        return 3.0;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if (oldDelegate is RiskHeatmapPainter) {
      return oldDelegate.riskGrid != riskGrid;
    }
    return true;
  }
} 
