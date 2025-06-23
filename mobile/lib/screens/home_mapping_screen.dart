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

class _HomeMappingScreenState extends State<HomeMappingScreen> with TickerProviderStateMixin {
  File? _imageFile;
  Uint8List? _webImage;
  final ImagePicker _picker = ImagePicker();
  bool _imageSelected = false;
  bool _loading = false;
  bool _checkingModelStatus = false;
  Map<String, dynamic>? _modelStatus;
  String _selectedMethod = 'auto';
  double _confidence = 0.4;
  bool _showTutorial = true;
  bool _developerMode = false;
  
  late AnimationController _tutorialAnimationController;
  late Animation<double> _tutorialFadeAnimation;
  late Animation<double> _tutorialScaleAnimation;
  
  late AnimationController _analysisAnimationController;
  late Animation<double> _analysisFadeAnimation;
  late Animation<Offset> _analysisSlideAnimation;
  
  late AnimationController _backgroundAnimationController;
  late Animation<double> _backgroundRotationAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
    
    // Initialize tutorial animations
    _tutorialAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _tutorialFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tutorialAnimationController,
      curve: Curves.easeOut,
    ));
    
    _tutorialScaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tutorialAnimationController,
      curve: Curves.elasticOut,
    ));
    
    // Analysis section animations
    _analysisAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _analysisFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _analysisAnimationController,
      curve: Curves.easeOut,
    ));
    
    _analysisSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _analysisAnimationController,
      curve: Curves.easeOutCubic,
    ));

    // Background animations
    _backgroundAnimationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    
    _backgroundRotationAnimation = Tween<double>(
      begin: 0,
      end: 2 * 3.14159,
    ).animate(_backgroundAnimationController);
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _backgroundAnimationController,
      curve: Curves.easeInOut,
    ));

    // Show tutorial popup after a brief delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _showTutorial) {
        _tutorialAnimationController.forward();
      }
    });
  }
  
  @override
  void dispose() {
    _tutorialAnimationController.dispose();
    _analysisAnimationController.dispose();
    _backgroundAnimationController.dispose();
    super.dispose();
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

  void _closeTutorial() {
    _tutorialAnimationController.reverse().then((_) {
      setState(() {
        _showTutorial = false;
      });
    });
  }

  void _proceedToStep() {
    _closeTutorial();
    // Auto-scroll or focus to the upload section
  }

  void _showDeveloperModeDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.developer_mode,
                    color: Theme.of(context).primaryColor,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Developer Mode',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildModelStatusCard(),
              const SizedBox(height: 16),
              if (_imageSelected) ...[
                const Divider(),
                const SizedBox(height: 16),
                _buildAdvancedMethodSelection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedMethodSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Advanced Settings',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildMethodOption('auto', 'Auto (Recommended)', 'Automatically select the best available method'),
        _buildMethodOption('enhanced', 'Enhanced AI Model', 'Use specialized floor plan detection model'),
        _buildMethodOption('yolo', 'YOLO + Computer Vision', 'Use YOLO object detection with computer vision'),
        _buildMethodOption('google_vision', 'Google Vision API', 'Use Google Cloud Vision API'),
        if (_selectedMethod == 'enhanced') ...[
          const SizedBox(height: 16),
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
    );
  }

    Future<void> _getImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      // Reset animation controller for new image
      _analysisAnimationController.reset();
      
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
      
      // Trigger the analysis section animation
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _analysisAnimationController.forward();
        }
      });
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

  Widget _buildTutorialPopup() {
    return AnimatedBuilder(
      animation: Listenable.merge([_tutorialFadeAnimation, _tutorialScaleAnimation]),
      builder: (context, child) {
        return Opacity(
          opacity: _tutorialFadeAnimation.value,
          child: Container(
            color: Colors.black.withOpacity(0.6), // Semi-transparent overlay
            child: Center(
              child: Transform.scale(
                scale: _tutorialScaleAnimation.value,
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Stage indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'STAGE 1',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Shield icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: const Icon(
                          Icons.home_work_outlined,
                          size: 40,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Title
                      const Text(
                        'Start Risk Assessment',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Description
                      const Text(
                        'Welcome to SafeMad\'s intelligent home safety analysis. We\'ll help you identify the safest areas in your home during emergencies.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF666666),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Instructions
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE8EAF6),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'How it works:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildInstructionStep('1', 'Upload or take a photo of your home\'s floor plan'),
                            const SizedBox(height: 8),
                            _buildInstructionStep('2', 'Choose AI detection or manually draw room boundaries'),
                            const SizedBox(height: 8),
                            _buildInstructionStep('3', 'Our AI will analyze safety zones and risk factors'),
                            const SizedBox(height: 8),
                            _buildInstructionStep('4', 'Get personalized safety recommendations'),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _closeTutorial,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFF1565C0)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Skip Tutorial',
                                style: TextStyle(
                                  color: Color(0xFF1565C0),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _proceedToStep,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1565C0),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 2,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Start Assessment',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 18),
                                ],
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
        );
      },
    );
  }

  Widget _buildInstructionStep(String number, String instruction) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            instruction,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1A1A1A),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageDisplayArea() {
    return Container(
      width: double.infinity,
      height: 300,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      child: _imageSelected
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: kIsWeb && _webImage != null
                  ? Image.memory(
                      _webImage!,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : (!kIsWeb && _imageFile != null)
                      ? Image.file(
                          _imageFile!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : const Center(child: Text('No image selected')),
            )
                  : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.home_work_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Upload Your Floor Plan',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Take a photo or upload an existing floor plan\nto start your safety assessment',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildAnimatedHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor.withOpacity(0.05),
            Theme.of(context).primaryColor.withOpacity(0.02),
          ],
        ),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _backgroundAnimationController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _backgroundRotationAnimation.value,
                child: Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor.withOpacity(0.3),
                          Theme.of(context).primaryColor.withOpacity(0.1),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.security,
                      size: 40,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'AI-Powered Safety Analysis',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload your floor plan and let our advanced AI identify\nthe safest zones in your home during emergencies',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildFeatureChip(Icons.psychology, 'AI Analysis'),
              _buildFeatureChip(Icons.speed, 'Fast Results'),
              _buildFeatureChip(Icons.verified, 'Accurate'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadHint(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _getImage(ImageSource.gallery),
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Image'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _getImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildAnalysisButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.1),
                  Theme.of(context).primaryColor.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.psychology,
                  size: 48,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ready for Analysis',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose how you\'d like to analyze your floor plan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _analyzeFloorPlan,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('AI Analysis'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _useInteractiveAnnotation,
                        icon: const Icon(Icons.edit),
                        label: const Text('Manual Draw'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text(
              'Analyzing your floor plan...',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stage 1'),
        actions: [
          IconButton(
            icon: const Icon(Icons.developer_mode),
            onPressed: _showDeveloperModeDialog,
            tooltip: 'Developer Mode',
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Section with Animation
                _buildAnimatedHeader(),
                
                const SizedBox(height: 12),
                
                // Image Display Area
                _buildImageDisplayArea(),
                
                // Upload Buttons
                if (!_imageSelected) _buildUploadButtons(),
                

                
                // Analysis Options (shown when image is selected)
                if (_imageSelected) 
                  AnimatedBuilder(
                    animation: _analysisAnimationController,
                    builder: (context, child) {
                      return FadeTransition(
                        opacity: _analysisFadeAnimation,
                        child: SlideTransition(
                          position: _analysisSlideAnimation,
                          child: _buildAnalysisButtons(),
                        ),
                      );
                    },
                  ),
                
                const SizedBox(height: 32),
              ],
            ),
          ),
          
          // Tutorial Overlay
          if (_showTutorial)
            _buildTutorialPopup(),
        ],
      ),
    );
  }
} 