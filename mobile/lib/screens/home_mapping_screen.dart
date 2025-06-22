import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import 'room_naming_screen.dart';
import 'interactive_floor_plan_screen.dart';
import 'enhanced_detection_results_screen.dart';
import 'enhanced_model_config_screen.dart';
import '../services/enhanced_floor_plan_service.dart';

class HomeMappingScreen extends StatefulWidget {
  const HomeMappingScreen({Key? key}) : super(key: key);

  @override
  _HomeMappingScreenState createState() => _HomeMappingScreenState();
}

class _HomeMappingScreenState extends State<HomeMappingScreen> {
  File? _imageFile;
  Uint8List? _webImage;
  final ImagePicker _picker = ImagePicker();
  bool _imageSelected = false;
  bool _loading = false;
  bool _checkingModelStatus = false;
  Map<String, dynamic>? _modelStatus;
  String _selectedMethod = 'auto';
  double _confidence = 0.4;

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    setState(() { _checkingModelStatus = true; });
    
    try {
      final status = await EnhancedFloorPlanService.getModelStatus();
      setState(() { 
        _modelStatus = status;
        _checkingModelStatus = false;
      });
    } catch (e) {
      print('Failed to check model status: $e');
      setState(() { _checkingModelStatus = false; });
    }
  }

  Future<void> _getImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImage = bytes;
          _imageSelected = true;
        });
      } else {
        setState(() {
          _imageFile = File(pickedFile.path);
          _imageSelected = true;
        });
      }
    }
  }

  void _useInteractiveAnnotation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InteractiveFloorPlanScreen(
          imageFile: _imageFile,
          webImage: _webImage,
        ),
      ),
    );
  }

  Future<void> _analyzeFloorPlan() async {
    setState(() { _loading = true; });
    
    try {
      Uint8List imageBytes;
      if (kIsWeb && _webImage != null) {
        imageBytes = _webImage!;
      } else if (_imageFile != null) {
        imageBytes = await _imageFile!.readAsBytes();
      } else {
        throw Exception('No image selected');
      }

      // Use enhanced service for analysis
      final result = await EnhancedFloorPlanService.analyzeFloorPlan(
        imageBytes,
        method: _selectedMethod,
        confidence: _confidence,
      );

      if (!mounted) return;

      // Check for errors
      if (result['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Analysis failed: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Navigate to results
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EnhancedDetectionResultsScreen(detectionResult: result),
        ),
      );
    } catch (e) {
      print('Exception during analysis: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() { _loading = false; });
    }
  }

  void _showMethodSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Analysis Method'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMethodOption('auto', 'Auto (Recommended)', 'Automatically select the best available method'),
            _buildMethodOption('enhanced', 'Enhanced AI Model', 'Use specialized floor plan detection model'),
            _buildMethodOption('yolo', 'YOLO + Computer Vision', 'Use YOLO object detection with computer vision'),
            _buildMethodOption('google_vision', 'Google Vision API', 'Use Google Cloud Vision API'),
            const SizedBox(height: 16),
            if (_selectedMethod == 'enhanced') ...[
              const Text('Confidence Threshold:'),
              Slider(
                value: _confidence,
                min: 0.1,
                max: 0.9,
                divisions: 8,
                label: _confidence.toStringAsFixed(1),
                onChanged: (value) {
                  setState(() { _confidence = value; });
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _analyzeFloorPlan();
            },
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodOption(String method, String title, String description) {
    final isSelected = _selectedMethod == method;
    final isAvailable = _modelStatus != null && _isMethodAvailable(method);
    
    return RadioListTile<String>(
      value: method,
      groupValue: _selectedMethod,
      onChanged: isAvailable ? (value) {
        setState(() { _selectedMethod = value!; });
      } : null,
      title: Text(
        title,
        style: TextStyle(
          color: isAvailable ? null : Colors.grey,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          color: isAvailable ? null : Colors.grey,
        ),
      ),
      secondary: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
    );
  }

  bool _isMethodAvailable(String method) {
    if (_modelStatus == null) return false;
    
    switch (method) {
      case 'auto':
        return true;
      case 'enhanced':
        return _modelStatus!['enhanced_model_loaded'] == true;
      case 'yolo':
        return _modelStatus!['yolo_available'] == true;
      case 'google_vision':
        return _modelStatus!['google_vision_api'] == true;
      default:
        return false;
    }
  }

  Widget _buildModelStatusCard() {
    if (_checkingModelStatus) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Checking model status...'),
            ],
          ),
        ),
      );
    }

    if (_modelStatus == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Unable to check model status'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI Model Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildStatusItem('Enhanced Model', _modelStatus!['enhanced_model_loaded']),
            _buildStatusItem('YOLO Detection', _modelStatus!['yolo_available']),
            _buildStatusItem('Google Vision API', _modelStatus!['google_vision_api']),
            const SizedBox(height: 8),
            Text(
              'Recommended: ${_modelStatus!['recommended_method']}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, bool status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            status ? Icons.check_circle : Icons.cancel,
            color: status ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (kIsWeb && _webImage != null) {
      imageWidget = Image.memory(_webImage!, height: 200);
    } else if (!kIsWeb && _imageFile != null) {
      imageWidget = Image.file(_imageFile!, height: 200);
    } else {
      imageWidget = const Text('No image selected.');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Mapping'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EnhancedModelConfigScreen(),
                ),
              );
            },
            tooltip: 'Enhanced Model Settings',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkModelStatus,
            tooltip: 'Refresh model status',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildModelStatusCard(),
            const SizedBox(height: 20),
            imageWidget,
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _getImage(ImageSource.gallery),
                  child: const Text('Upload Floor Plan'),
                ),
                ElevatedButton(
                  onPressed: () => _getImage(ImageSource.camera),
                  child: const Text('Take a Photo'),
                ),
              ],
            ),
            if (_imageSelected) ...[
              const SizedBox(height: 20),
              const Text(
                'Choose annotation method:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _useInteractiveAnnotation,
                    icon: const Icon(Icons.edit),
                    label: const Text('Draw Rooms'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showMethodSelectionDialog,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('AI Detect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              if (_selectedMethod != 'auto') ...[
                const SizedBox(height: 10),
                Text(
                  'Selected: $_selectedMethod${_selectedMethod == 'enhanced' ? ' (${_confidence.toStringAsFixed(1)})' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
            if (_loading) const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      ),
    );
  }
} 