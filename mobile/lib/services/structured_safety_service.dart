import 'dart:convert';
import 'package:http/http.dart' as http;

class StructuredSafetyService {
  static const String baseUrl = 'http://localhost:8000/api/structured-safety';
  static const String dataUrl = 'http://localhost:8000/api/structured-data';

  /// Convert old assessment data to structured format
  /// This is useful for migrating existing data
  static Future<Map<String, dynamic>> convertOldAssessment({
    required Map<String, dynamic> oldAssessmentData,
    required String annotationId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/convert-old-assessment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'old_assessment_data': oldAssessmentData,
          'annotation_id': annotationId,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to convert assessment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error converting assessment: $e');
    }
  }

  /// Create structured data from enhanced detection results
  /// This replaces the old annotation saving process
  static Future<String> createStructuredDataFromDetections({
    required Map<String, dynamic> enhancedResults,
    required List<Map<String, dynamic>> userAnnotations,
    required Map<String, dynamic> userAssessments,
    String? userId,
    Map<String, dynamic>? floorPlanMetadata,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$dataUrl/convert-and-store'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'ai_detections': enhancedResults,
          'user_annotations': userAnnotations,
          'user_assessments': userAssessments,
          'user_id': userId,
          'floor_plan_metadata': floorPlanMetadata,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return result['analysis_id'];
      } else {
        throw Exception('Failed to create structured data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error creating structured data: $e');
    }
  }

  /// Submit safety assessment using structured data
  /// This replaces the old room safety assessment submission
  static Future<Map<String, dynamic>> submitStructuredSafetyAssessment({
    required String analysisId,
    required List<Map<String, dynamic>> roomAssessments,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/submit-assessment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'analysis_id': analysisId,
          'room_assessments': roomAssessments,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to submit assessment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error submitting assessment: $e');
    }
  }

  /// Get structured safety assessment results
  static Future<Map<String, dynamic>> getAssessmentResults(String analysisId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/assessment-results/$analysisId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get assessment results: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error getting assessment results: $e');
    }
  }

  /// Get structured data summary
  static Future<Map<String, dynamic>> getStructuredDataSummary(String analysisId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/structured-data/$analysisId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get structured data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error getting structured data: $e');
    }
  }

  /// Generate heatmap using structured data
  static Future<Map<String, dynamic>> generateStructuredHeatmap(String analysisId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/generate-heatmap'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'analysis_id': analysisId,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to generate heatmap: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error generating heatmap: $e');
    }
  }

  /// Get room analysis using structured data
  static Future<Map<String, dynamic>> getStructuredRoomAnalysis(String analysisId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/room-analysis/$analysisId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get room analysis: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error getting room analysis: $e');
    }
  }

  /// Update room data in structured format
  static Future<Map<String, dynamic>> updateRoomData({
    required String analysisId,
    required String roomId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/update-room/$analysisId/$roomId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updates),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to update room: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error updating room: $e');
    }
  }

  /// Get all analyses for a user
  static Future<Map<String, dynamic>> getUserAnalyses(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user-analyses/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get user analyses: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error getting user analyses: $e');
    }
  }

  /// Compatibility method for gradual migration
  /// This uses the new structured system but maintains the old interface
  static Future<Map<String, dynamic>> submitRoomSafetyAssessmentCompatibility({
    required String annotationId,
    required List<Map<String, dynamic>> roomSafetyData,
  }) async {
    try {
      print('🔄 Using compatibility mode for safety assessment');
      print('   Converting to structured format...');

      // Use the compatibility endpoint that automatically converts to structured format
      final response = await http.post(
        Uri.parse('$baseUrl/submit-room-safety-assessment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'annotation_id': annotationId,
          'room_safety_data': roomSafetyData,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        // Log migration information
        if (result.containsKey('_migration_info')) {
          print('✅ Successfully converted to structured format');
          print('   Analysis ID: ${result['_migration_info']['analysis_id']}');
          print('   Please migrate to: ${result['_migration_info']['new_endpoint']}');
        }
        
        return result;
      } else {
        throw Exception('Failed to submit assessment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error submitting assessment: $e');
    }
  }

  /// Compatibility method for heatmap generation
  static Future<Map<String, dynamic>> generateExplosiveRiskHeatmapCompatibility({
    required Map<String, dynamic> heatmapData,
    String? analysisId,
  }) async {
    try {
      print('🔄 Using compatibility mode for heatmap generation');
      
      // Add analysis_id if available to use structured approach
      if (analysisId != null) {
        heatmapData['analysis_id'] = analysisId;
        print('   Using structured data approach with analysis_id: $analysisId');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/generate-explosive-risk-heatmap'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(heatmapData),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        
        // Log migration information
        if (result.containsKey('_migration_info')) {
          print('✅ Successfully used structured format');
          print('   Please migrate to: ${result['_migration_info']['new_endpoint']}');
        } else if (result.containsKey('_fallback_used')) {
          print('⚠️ Used fallback method - consider providing analysis_id');
        }
        
        return result;
      } else {
        throw Exception('Failed to generate heatmap: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error generating heatmap: $e');
    }
  }

  /// Helper method to extract detection data from enhanced results screen
  static Map<String, dynamic> extractDetectionDataFromEnhancedResults(
    Map<String, dynamic> enhancedResults
  ) {
    return {
      'rooms': enhancedResults['detectedRooms'] ?? [],
      'walls': enhancedResults['detectedWalls'] ?? [],
      'doors': enhancedResults['detectedDoors'] ?? [],
      'windows': enhancedResults['detectedWindows'] ?? [],
      'architectural_elements': enhancedResults['architecturalElements'] ?? [],
      'measurements': enhancedResults['measurements'] ?? [],
      'detection_metadata': {
        'detection_method': enhancedResults['detectionMethod'] ?? 'unknown',
        'confidence': enhancedResults['confidence'] ?? 0.0,
        'timestamp': DateTime.now().toIso8601String(),
      }
    };
  }

  /// Helper method to format room assessments for structured submission
  static List<Map<String, dynamic>> formatRoomAssessmentsForStructured(
    List<Map<String, dynamic>> roomSafetyData
  ) {
    return roomSafetyData.map((roomData) {
      return {
        'room_id': roomData['room_id'],
        'room_name': roomData['room_name'] ?? 'Unknown Room',
        'room_type': roomData['room_type'] ?? 'room',
        'responses': roomData['responses'] ?? {},
      };
    }).toList();
  }
} 