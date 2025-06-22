import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class EnhancedFloorPlanService {
  static const String baseUrl = 'http://localhost:8000/api';
  
  /// Analyze floor plan using the enhanced model
  static Future<Map<String, dynamic>> analyzeFloorPlan(
    Uint8List imageBytes, {
    String method = 'enhanced',
    double confidence = 0.4,
    bool enableSam = true,
  }) async {
    try {
      // Use SAM endpoint for enhanced method if SAM is enabled
      String endpoint;
      if (method == 'enhanced' && enableSam) {
        endpoint = '$baseUrl/analyze-floor-plan-with-sam';
      } else {
        endpoint = '$baseUrl/analyze-floor-plan?method=$method&confidence=$confidence';
      }
      
      var request = http.MultipartRequest('POST', Uri.parse(endpoint));
      
      // Add the image file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'floorplan.jpg',
          contentType: MediaType.parse('image/jpeg'),
        ),
      );
      
      // Add form parameters for SAM endpoint
      if (method == 'enhanced' && enableSam) {
        request.fields['confidence'] = confidence.toString();
        request.fields['enable_sam'] = 'true';
      }
      
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final result = json.decode(responseBody);
        print('🎯 API Response received with keys: ${result.keys.toList()}');
        
        // Debug SAM visualization
        if (result['sam_visualization'] != null) {
          print('✅ SAM visualization data found!');
        } else {
          print('⚠️ No SAM visualization in response');
        }
        
        return result;
      } else {
        throw Exception('API Error: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      throw Exception('Failed to analyze floor plan: $e');
    }
  }
  
  /// Analyze floor plan with SAM integration (dedicated method)
  static Future<Map<String, dynamic>> analyzeFloorPlanWithSam(
    Uint8List imageBytes, {
    double confidence = 0.4,
    bool enableSam = true,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('$baseUrl/analyze-floor-plan-with-sam')
      );
      
      // Add the image file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'floorplan.jpg',
          contentType: MediaType.parse('image/jpeg'),
        ),
      );
      
      // Add form parameters
      request.fields['confidence'] = confidence.toString();
      request.fields['enable_sam'] = enableSam.toString();
      
      print('🚀 Calling SAM endpoint with confidence: $confidence, enable_sam: $enableSam');
      
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final result = json.decode(responseBody);
        print('🎯 SAM API Response received with keys: ${result.keys.toList()}');
        
        // Debug visualization data
        if (result['sam_visualization'] != null) {
          final samVizLength = result['sam_visualization'].toString().length;
          print('✅ SAM visualization found! Length: $samVizLength characters');
        } else {
          print('⚠️ No SAM visualization in response');
        }
        
        if (result['annotated_image_base64'] != null) {
          final yoloVizLength = result['annotated_image_base64'].toString().length;
          print('✅ YOLO annotated image found! Length: $yoloVizLength characters');
        } else {
          print('⚠️ No YOLO annotated image in response');
        }
        
        return result;
      } else {
        throw Exception('SAM API Error: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      throw Exception('Failed to analyze floor plan with SAM: $e');
    }
  }
  
  /// Set the enhanced model path
  static Future<Map<String, dynamic>> setModel(String modelPath) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/set-floor-plan-model?model_path=$modelPath'),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to set model: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to set model: $e');
    }
  }
  
  /// Get model status
  static Future<Map<String, dynamic>> getModelStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/model-status'));
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get model status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get model status: $e');
    }
  }
  
  /// Save floor plan annotations (including drawing annotations)
  static Future<Map<String, dynamic>> saveAnnotations(
    List<Map<String, dynamic>> annotations,
    Map<String, dynamic> imageSize,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/save-floor-plan-annotations'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'rooms': [], // Empty rooms for now, can be populated later
          'annotations': annotations, // Drawing annotations
          'imageSize': imageSize,
          'image_dimensions': imageSize,
          'display_dimensions': imageSize, // Can be different if needed
          'metadata': {
            'annotation_type': 'drawing_annotations',
            'total_annotations': annotations.length,
            'timestamp': DateTime.now().toIso8601String(),
          }
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to save annotations: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to save annotations: $e');
    }
  }
}

/// Data classes for enhanced floor plan results
class EnhancedFloorPlanResult {
  final List<DetectedRoom> detectedRooms;
  final List<ArchitecturalElement> architecturalElements;
  final Map<String, int> imageDimensions;
  final String processingMethod;
  final double detectionConfidence;
  final int totalDoors;
  final int totalWindows;
  final int totalWalls;
  final int totalStairs;
  final Map<String, int> elementCounts;
  final String analysisSummary;
  final String? error;
  final String? annotatedImageBase64;
  final String? samVisualization;
  final String? originalImageBase64;
  final Map<String, dynamic>? individualVisualizations;
  
  EnhancedFloorPlanResult({
    required this.detectedRooms,
    required this.architecturalElements,
    required this.imageDimensions,
    required this.processingMethod,
    required this.detectionConfidence,
    required this.totalDoors,
    required this.totalWindows,
    required this.totalWalls,
    required this.totalStairs,
    required this.elementCounts,
    required this.analysisSummary,
    this.error,
    this.annotatedImageBase64,
    this.samVisualization,
    this.originalImageBase64,
    this.individualVisualizations,
  });
  
  factory EnhancedFloorPlanResult.fromJson(Map<String, dynamic> json) {
    return EnhancedFloorPlanResult(
      detectedRooms: (json['detected_rooms'] as List?)
          ?.map((room) => DetectedRoom.fromJson(room))
          .toList() ?? [],
      architecturalElements: (json['architectural_elements'] as List?)
          ?.map((element) => ArchitecturalElement.fromJson(element))
          .toList() ?? [],
      imageDimensions: Map<String, int>.from(json['image_dimensions'] ?? {}),
      processingMethod: json['processing_method'] ?? 'unknown',
      detectionConfidence: (json['detection_confidence'] ?? 0.0).toDouble(),
      totalDoors: json['total_doors'] ?? 0,
      totalWindows: json['total_windows'] ?? 0,
      totalWalls: json['total_walls'] ?? 0,
      totalStairs: json['total_stairs'] ?? 0,
      elementCounts: Map<String, int>.from(json['element_counts'] ?? {}),
      analysisSummary: json['analysis_summary'] ?? '',
      error: json['error'],
      annotatedImageBase64: json['annotated_image_base64'],
      samVisualization: json['sam_visualization'],
      originalImageBase64: json['original_image_base64'],
      individualVisualizations: json['individual_visualizations'] != null 
          ? Map<String, dynamic>.from(json['individual_visualizations'])
          : null,
    );
  }
}

class DetectedRoom {
  final String roomId;
  final String defaultName;
  final Map<String, dynamic> boundaries;
  final double confidence;
  final List<ArchitecturalElement> architecturalElements;
  final String description;
  final String detectionMethod;
  final List<ArchitecturalElement> doors;
  final List<ArchitecturalElement> windows;
  final List<ArchitecturalElement> walls;
  final Map<String, double> estimatedDimensions;
  
  DetectedRoom({
    required this.roomId,
    required this.defaultName,
    required this.boundaries,
    required this.confidence,
    required this.architecturalElements,
    required this.description,
    required this.detectionMethod,
    required this.doors,
    required this.windows,
    required this.walls,
    required this.estimatedDimensions,
  });
  
  factory DetectedRoom.fromJson(Map<String, dynamic> json) {
    return DetectedRoom(
      roomId: json['room_id']?.toString() ?? '',
      defaultName: json['default_name'] ?? '',
      boundaries: Map<String, dynamic>.from(json['boundaries'] ?? {}),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      architecturalElements: (json['architectural_elements'] as List?)
          ?.map((element) => ArchitecturalElement.fromJson(element))
          .toList() ?? [],
      description: json['description'] ?? '',
      detectionMethod: json['detection_method'] ?? '',
      doors: (json['doors'] as List?)
          ?.map((door) => ArchitecturalElement.fromJson(door))
          .toList() ?? [],
      windows: (json['windows'] as List?)
          ?.map((window) => ArchitecturalElement.fromJson(window))
          .toList() ?? [],
      walls: (json['walls'] as List?)
          ?.map((wall) => ArchitecturalElement.fromJson(wall))
          .toList() ?? [],
      estimatedDimensions: Map<String, double>.from(json['estimated_dimensions'] ?? {}),
    );
  }
}

class ArchitecturalElement {
  final String type;
  final double confidence;
  final Map<String, int> bbox;
  final Map<String, int> center;
  final Map<String, int> dimensions;
  final int area;
  final String relativePosition;
  
  ArchitecturalElement({
    required this.type,
    required this.confidence,
    required this.bbox,
    required this.center,
    required this.dimensions,
    required this.area,
    required this.relativePosition,
  });
  
  factory ArchitecturalElement.fromJson(Map<String, dynamic> json) {
    return ArchitecturalElement(
      type: json['type'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      bbox: Map<String, int>.from(json['bbox'] ?? {}),
      center: Map<String, int>.from(json['center'] ?? {}),
      dimensions: Map<String, int>.from(json['dimensions'] ?? {}),
      area: json['area'] ?? 0,
      relativePosition: json['relative_position'] ?? '',
    );
  }
} 