import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'enhanced_safety_heatmap_screen.dart';
import '../services/structured_safety_service.dart';

class RoomSafetyAssessmentScreen extends StatefulWidget {
  final List<Map<String, dynamic>> rooms;
  final String annotationId;

  const RoomSafetyAssessmentScreen({
    Key? key,
    required this.rooms,
    required this.annotationId,
  }) : super(key: key);

  @override
  _RoomSafetyAssessmentScreenState createState() => _RoomSafetyAssessmentScreenState();
}

class _RoomSafetyAssessmentScreenState extends State<RoomSafetyAssessmentScreen> {
  int _currentRoomIndex = 0;
  Map<String, RoomSafetyData> _roomSafetyData = {};
  bool _loading = false;
  bool _showVisionDetails = true;

  @override
  void initState() {
    super.initState();
    // Initialize safety data for all rooms
    for (var room in widget.rooms) {
      final roomId = room['id']?.toString() ?? room['room_id']?.toString() ?? 'unknown';
      final roomName = room['name']?.toString() ?? room['default_name']?.toString() ?? 'Unknown Room';
      final roomType = room['type']?.toString() ?? 'room';
      
      _roomSafetyData[roomId] = RoomSafetyData(
        roomId: roomId,
        roomName: roomName,
        roomType: roomType,
      );
    }
  }

  Map<String, dynamic> get _currentRoom => widget.rooms[_currentRoomIndex];
  RoomSafetyData get _currentSafetyData {
    final roomId = _currentRoom['id']?.toString() ?? _currentRoom['room_id']?.toString() ?? 'unknown';
    return _roomSafetyData[roomId] ?? RoomSafetyData(
      roomId: roomId,
      roomName: 'Unknown Room',
      roomType: 'room',
    );
  }

  List<VitalInfoItem> _getVitalInfoForRoom(String roomType) {
    List<VitalInfoItem> baseInfo = [
      VitalInfoItem(
        key: 'wall_material',
        question: 'What are the walls made of?',
        type: InfoType.multipleChoice,
        options: ['Concrete', 'Brick', 'Drywall', 'Wood', 'Steel', 'Unknown'],
        importance: Importance.critical,
        hasImageAnalysis: true,
      ),
      VitalInfoItem(
        key: 'wall_thickness',
        question: 'Wall thickness/depth?',
        type: InfoType.wallDepth,
        options: ['Thin (<10cm)', 'Medium (10-20cm)', 'Thick (20-30cm)', 'Very Thick (>30cm)', 'Manual Measurement', 'AI Analysis'],
        importance: Importance.critical,
        hasImageAnalysis: true,
        hasManualMeasurement: true,
      ),
      VitalInfoItem(
        key: 'windows_count',
        question: 'Number of windows?',
        type: InfoType.multipleChoice,
        options: ['None', '1', '2', '3', '4+'],
        importance: Importance.medium,
      ),
      VitalInfoItem(
        key: 'window_sizes',
        question: 'Window sizes (if any)?',
        type: InfoType.windowSize,
        options: ['Small (<1m²)', 'Medium (1-2m²)', 'Large (>2m²)', 'Mixed Sizes', 'Manual Measurement'],
        importance: Importance.medium,
        hasManualMeasurement: true,
        dependsOn: 'windows_count',
        dependsOnValue: ['1', '2', '3', '4+'],
      ),
      VitalInfoItem(
        key: 'ceiling_height',
        question: 'Ceiling height?',
        type: InfoType.multipleChoice,
        options: ['Low (<2.5m)', 'Normal (2.5-3m)', 'High (>3m)', 'Manual Measurement'],
        importance: Importance.medium,
        hasManualMeasurement: true,
      ),
      VitalInfoItem(
        key: 'multiple_exits',
        question: 'Does this room have multiple exits?',
        type: InfoType.yesNo,
        importance: Importance.high,
      ),
      VitalInfoItem(
        key: 'clear_pathways',
        question: 'Are pathways clear of obstacles?',
        type: InfoType.yesNo,
        importance: Importance.high,
      ),
    ];

    // Add room-specific questions
    switch (roomType.toLowerCase()) {
      case 'kitchen':
        baseInfo.addAll([
          VitalInfoItem(
            key: 'gas_lines',
            question: 'Are there gas lines in this room?',
            type: InfoType.yesNo,
            importance: Importance.critical,
          ),
          VitalInfoItem(
            key: 'fire_extinguisher',
            question: 'Is there a fire extinguisher nearby?',
            type: InfoType.yesNo,
            importance: Importance.high,
          ),
        ]);
        break;
      
      case 'bedroom':
        baseInfo.addAll([
          VitalInfoItem(
            key: 'smoke_detector',
            question: 'Is there a smoke detector?',
            type: InfoType.yesNo,
            importance: Importance.critical,
          ),
          VitalInfoItem(
            key: 'window_escape',
            question: 'Can windows be used for emergency exit?',
            type: InfoType.yesNo,
            importance: Importance.high,
          ),
        ]);
        break;
      
      case 'mamad':
        baseInfo.addAll([
          VitalInfoItem(
            key: 'air_filtration',
            question: 'Does it have air filtration system?',
            type: InfoType.yesNo,
            importance: Importance.critical,
          ),
          VitalInfoItem(
            key: 'communication_device',
            question: 'Is there communication equipment?',
            type: InfoType.yesNo,
            importance: Importance.critical,
          ),
          VitalInfoItem(
            key: 'emergency_supplies',
            question: 'Are emergency supplies stored here?',
            type: InfoType.yesNo,
            importance: Importance.high,
          ),
        ]);
        break;
      
      case 'bathroom':
        baseInfo.addAll([
          VitalInfoItem(
            key: 'water_access',
            question: 'Is water source reliable?',
            type: InfoType.yesNo,
            importance: Importance.high,
          ),
          VitalInfoItem(
            key: 'ventilation',
            question: 'Is ventilation adequate?',
            type: InfoType.yesNo,
            importance: Importance.medium,
          ),
        ]);
        break;
      
      case 'balcony':
        baseInfo.addAll([
          VitalInfoItem(
            key: 'weather_protection',
            question: 'Is there weather protection?',
            type: InfoType.yesNo,
            importance: Importance.medium,
          ),
          VitalInfoItem(
            key: 'structural_integrity',
            question: 'Are railings and structure secure?',
            type: InfoType.yesNo,
            importance: Importance.critical,
          ),
        ]);
        break;
      
      case 'staircases':
        baseInfo.addAll([
          VitalInfoItem(
            key: 'emergency_lighting',
            question: 'Is there emergency lighting?',
            type: InfoType.yesNo,
            importance: Importance.critical,
          ),
          VitalInfoItem(
            key: 'handrails',
            question: 'Are handrails secure and present?',
            type: InfoType.yesNo,
            importance: Importance.high,
          ),
        ]);
        break;
    }

    return baseInfo;
  }

  Widget _buildInfoItem(VitalInfoItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getImportanceIcon(item.importance),
                  color: _getImportanceColor(item.importance),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.question,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (item.type == InfoType.yesNo)
              _buildYesNoButtons(item)
            else if (item.type == InfoType.multipleChoice)
              _buildMultipleChoice(item)
            else if (item.type == InfoType.wallDepth)
              _buildWallDepthInput(item)
            else if (item.type == InfoType.windowSize)
              _buildWindowSizeInput(item)
            else if (item.type == InfoType.text)
              _buildTextInput(item),
          ],
        ),
      ),
    );
  }

  Widget _buildYesNoButtons(VitalInfoItem item) {
    final currentValue = _currentSafetyData.responses[item.key];
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _currentSafetyData.responses[item.key] = 'yes';
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: currentValue == 'yes' ? Colors.green : Colors.grey[300],
              foregroundColor: currentValue == 'yes' ? Colors.white : Colors.black,
            ),
            child: const Text('Yes'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _currentSafetyData.responses[item.key] = 'no';
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: currentValue == 'no' ? Colors.red : Colors.grey[300],
              foregroundColor: currentValue == 'no' ? Colors.white : Colors.black,
            ),
            child: const Text('No'),
          ),
        ),
      ],
    );
  }

  Widget _buildMultipleChoice(VitalInfoItem item) {
    final currentValue = _currentSafetyData.responses[item.key];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: item.options!.map((option) {
        final isSelected = currentValue == option;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _currentSafetyData.responses[item.key] = option;
              });
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildWallDepthInput(VitalInfoItem item) {
    final currentValue = _currentSafetyData.responses[item.key];
    final measurementValue = _currentSafetyData.responses['${item.key}_measurement'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Standard options
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: item.options!.where((option) => !option.contains('Manual') && !option.contains('AI')).map((option) {
            final isSelected = currentValue == option;
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _currentSafetyData.responses[item.key] = option;
                    _currentSafetyData.responses.remove('${item.key}_measurement');
                  });
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        
        // Manual measurement option
        if (item.hasManualMeasurement) ...[
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showManualMeasurementDialog(item, 'wall thickness', 'cm'),
                  icon: const Icon(Icons.straighten),
                  label: const Text('Manual Measurement'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentValue == 'manual_measurement' ? Colors.blue : Colors.grey[300],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (item.hasImageAnalysis)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _analyzeWallDepthWithAI(item),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('AI Analysis'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: currentValue == 'ai_analysis' ? Colors.green : Colors.grey[300],
                    ),
                  ),
                ),
            ],
          ),
        ],
        
        // Show measurement result
        if (measurementValue != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Measured: ${measurementValue}cm',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWindowSizeInput(VitalInfoItem item) {
    final currentValue = _currentSafetyData.responses[item.key];
    final measurementValue = _currentSafetyData.responses['${item.key}_measurement'];
    
    // Check if this item should be shown based on dependencies
    if (item.dependsOn != null) {
      final dependsOnValue = _currentSafetyData.responses[item.dependsOn!];
      if (dependsOnValue == null || !item.dependsOnValue!.contains(dependsOnValue)) {
        return const SizedBox.shrink(); // Hide if dependency not met
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: item.options!.where((option) => !option.contains('Manual')).map((option) {
            final isSelected = currentValue == option;
            return ChoiceChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _currentSafetyData.responses[item.key] = option;
                    _currentSafetyData.responses.remove('${item.key}_measurement');
                  });
                }
              },
            );
          }).toList(),
        ),
        
        const SizedBox(height: 12),
        
        // Manual measurement option
        if (item.hasManualMeasurement)
          ElevatedButton.icon(
            onPressed: () => _showWindowMeasurementDialog(),
            icon: const Icon(Icons.aspect_ratio),
            label: const Text('Measure Windows'),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentValue == 'manual_measurement' ? Colors.blue : Colors.grey[300],
            ),
          ),
        
        // Show measurement result
        if (measurementValue != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Measured: ${measurementValue}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTextInput(VitalInfoItem item) {
    return TextField(
      onChanged: (value) {
        _currentSafetyData.responses[item.key] = value;
      },
      decoration: InputDecoration(
        hintText: 'Enter details...',
        border: const OutlineInputBorder(),
      ),
    );
  }

  IconData _getImportanceIcon(Importance importance) {
    switch (importance) {
      case Importance.critical:
        return Icons.warning;
      case Importance.high:
        return Icons.priority_high;
      case Importance.medium:
        return Icons.info;
      case Importance.low:
        return Icons.info_outline;
    }
  }

  Color _getImportanceColor(Importance importance) {
    switch (importance) {
      case Importance.critical:
        return Colors.red;
      case Importance.high:
        return Colors.orange;
      case Importance.medium:
        return Colors.blue;
      case Importance.low:
        return Colors.grey;
    }
  }

  Future<void> _analyzeWithAI() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Room Analysis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Take a photo of this room for AI analysis?'),
            const SizedBox(height: 16),
            const Text(
              'AI will analyze:\n• Wall materials\n• Safety equipment\n• Structural features\n• Potential hazards',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _takePictureForAnalysis();
            },
            child: const Text('Take Photo'),
          ),
        ],
      ),
    );
  }

  Future<void> _takePictureForAnalysis() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);
    
    if (photo != null) {
      setState(() {
        _loading = true;
      });

      try {
        // Here you would send the image to your AI analysis endpoint
        // For now, we'll simulate AI analysis
        await Future.delayed(const Duration(seconds: 2));
        
        // Simulate AI responses based on room type
        _simulateAIAnalysis();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI analysis completed!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e')),
        );
      } finally {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _simulateAIAnalysis() {
    final roomType = _currentRoom['type'].toString().toLowerCase();
    final responses = _currentSafetyData.responses;
    
    // Simulate AI detection based on room type
    switch (roomType) {
      case 'kitchen':
        responses['wall_material'] = 'Drywall';
        responses['gas_lines'] = 'yes';
        responses['fire_extinguisher'] = 'no';
        break;
      case 'bedroom':
        responses['wall_material'] = 'Drywall';
        responses['smoke_detector'] = 'yes';
        responses['window_escape'] = 'yes';
        break;
      case 'mamad':
        responses['wall_material'] = 'Concrete';
        responses['wall_thickness'] = 'Very Thick (>30cm)';
        responses['air_filtration'] = 'yes';
        break;
      default:
        responses['wall_material'] = 'Drywall';
        responses['wall_thickness'] = 'Medium (10-20cm)';
    }
    
    responses['clear_pathways'] = 'yes';
    responses['multiple_exits'] = 'no';
  }

  Future<void> _showManualMeasurementDialog(VitalInfoItem item, String measurementType, String unit) async {
    final TextEditingController controller = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manual $measurementType Measurement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter the $measurementType measurement:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Measurement ($unit)',
                border: const OutlineInputBorder(),
                suffixText: unit,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tip: Use a measuring tape or ruler for accurate results.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.of(context).pop(controller.text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      setState(() {
        _currentSafetyData.responses[item.key] = 'manual_measurement';
        _currentSafetyData.responses['${item.key}_measurement'] = result;
      });
    }
  }

  Future<void> _showWindowMeasurementDialog() async {
    final List<Map<String, double>> windowMeasurements = [];
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Window Measurements'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add measurements for each window:'),
                const SizedBox(height: 16),
                ...windowMeasurements.asMap().entries.map((entry) {
                  final index = entry.key;
                  final measurement = entry.value;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Window ${index + 1}: ${measurement['width']}cm × ${measurement['height']}cm\n'
                              'Area: ${((measurement['width']! * measurement['height']!) / 10000).toStringAsFixed(2)}m²',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setDialogState(() {
                                windowMeasurements.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    _addWindowMeasurement(windowMeasurements, setDialogState);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Window'),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(windowMeasurements);
            },
            child: const Text('Save All'),
          ),
        ],
      ),
    );
    
    if (windowMeasurements.isNotEmpty) {
      final totalArea = windowMeasurements.fold<double>(
        0, 
        (sum, window) => sum + (window['width']! * window['height']! / 10000)
      );
      
      String sizeCategory;
      if (totalArea < 1) {
        sizeCategory = 'Small';
      } else if (totalArea < 2) {
        sizeCategory = 'Medium';
      } else {
        sizeCategory = 'Large';
      }
      
      setState(() {
        _currentSafetyData.responses['window_sizes'] = 'manual_measurement';
        _currentSafetyData.responses['window_sizes_measurement'] = 
            '${windowMeasurements.length} windows, ${totalArea.toStringAsFixed(2)}m² total ($sizeCategory)';
      });
    }
  }

  Future<void> _addWindowMeasurement(List<Map<String, double>> measurements, StateSetter setDialogState) async {
    final widthController = TextEditingController();
    final heightController = TextEditingController();
    
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Window ${measurements.length + 1} Measurement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widthController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Width (cm)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: heightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Height (cm)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final width = double.tryParse(widthController.text);
              final height = double.tryParse(heightController.text);
              if (width != null && height != null) {
                Navigator.of(context).pop({'width': width, 'height': height});
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    
    if (result != null) {
      setDialogState(() {
        measurements.add(result);
      });
    }
  }

  Future<void> _analyzeWallDepthWithAI(VitalInfoItem item) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Wall Depth Analysis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Take a photo showing the wall cross-section or edge for AI analysis.'),
            const SizedBox(height: 16),
            const Text(
              'AI will analyze:\n• Wall thickness from visible edges\n• Material density indicators\n• Structural depth markers',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _takeWallDepthPhoto(item);
            },
            child: const Text('Take Photo'),
          ),
        ],
      ),
    );
  }

  Future<void> _takeWallDepthPhoto(VitalInfoItem item) async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);
    
    if (photo != null) {
      setState(() {
        _loading = true;
      });

      try {
        // Simulate AI wall depth analysis
        await Future.delayed(const Duration(seconds: 3));
        
        // Simulate AI depth measurement based on room type
        final roomType = _currentRoom['type'].toString().toLowerCase();
        String depthResult;
        String measurement;
        
        if (roomType.contains('mamad')) {
          depthResult = 'Very Thick (>30cm)';
          measurement = '35';
        } else if (roomType.contains('kitchen') || roomType.contains('bathroom')) {
          depthResult = 'Medium (10-20cm)';
          measurement = '15';
        } else {
          depthResult = 'Thin (<10cm)';
          measurement = '8';
        }
        
        setState(() {
          _currentSafetyData.responses[item.key] = 'ai_analysis';
          _currentSafetyData.responses['${item.key}_measurement'] = measurement;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI Analysis: $depthResult (${measurement}cm)')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI analysis failed: $e')),
        );
      } finally {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _submitAssessment() async {
    setState(() {
      _loading = true;
    });

    try {
      print('🔄 Submitting safety assessment using structured data system...');
      
      // Format room assessments for structured submission
      final roomAssessments = StructuredSafetyService.formatRoomAssessmentsForStructured(
        _roomSafetyData.values.map((data) => data.toJson()).toList()
      );
      
      // Try to use the new structured approach first
      try {
        print('   Attempting structured submission...');
        
        // For now, we'll use the compatibility mode until we have the analysis_id
        // from the earlier flow. In a full migration, this would come from the 
        // enhanced detection results screen.
        final result = await StructuredSafetyService.submitRoomSafetyAssessmentCompatibility(
          annotationId: widget.annotationId,
          roomSafetyData: roomAssessments,
        );
        
        print('✅ Successfully submitted using structured approach');
        
        // Navigate to results screen with structured data
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => SafetyResultsScreen(
              safetyReport: result,
              annotationId: widget.annotationId,
              analysisId: result['analysis_id'], // Pass the new analysis_id
            ),
          ),
        );
        
      } catch (structuredError) {
        print('⚠️ Structured approach failed, falling back to old method: $structuredError');
        
        // Fallback to old method
        final assessmentData = {
          'annotation_id': widget.annotationId,
          'room_safety_data': _roomSafetyData.values.map((data) => data.toJson()).toList(),
        };

        final response = await http.post(
          Uri.parse('http://localhost:8000/api/submit-room-safety-assessment'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(assessmentData),
        );

        if (response.statusCode == 200) {
          final result = json.decode(response.body);
          
          // Navigate to results screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => SafetyResultsScreen(
                safetyReport: result,
                annotationId: widget.annotationId,
              ),
            ),
          );
        } else {
          throw Exception('Failed to submit assessment');
        }
      }
      
    } catch (e) {
      print('❌ Assessment submission failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting assessment: $e')),
      );
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRoom = _currentRoom;
    final roomName = currentRoom['name']?.toString() ?? currentRoom['default_name']?.toString() ?? 'Unknown Room';
    final roomType = currentRoom['type']?.toString() ?? 'room';
    final vitalInfo = _getVitalInfoForRoom(roomType);

    return Scaffold(
      appBar: AppBar(
        title: Text('Room Safety Assessment'),
        actions: [
          IconButton(
            icon: Icon(Icons.auto_awesome),
            onPressed: _analyzeWithAI,
            tooltip: 'AI Analysis',
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: Column(
              children: [
                Text(
                  '$roomName ($roomType)',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (_currentRoomIndex + 1) / widget.rooms.length,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                const SizedBox(height: 4),
                Text('Room ${_currentRoomIndex + 1} of ${widget.rooms.length}'),
              ],
            ),
          ),
          
          // Room description from Vision API (new)
          if (currentRoom.containsKey('description'))
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with toggle button
                  Row(
                    children: [
                      const Icon(Icons.analytics, color: Colors.green),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'AI Vision Analysis',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _showVisionDetails ? Icons.expand_less : Icons.expand_more,
                          color: Colors.green,
                        ),
                        onPressed: () {
                          setState(() {
                            _showVisionDetails = !_showVisionDetails;
                          });
                        },
                      ),
                    ],
                  ),
                  
                  // Collapsible content
                  if (_showVisionDetails) ...[
                    const SizedBox(height: 8),
                    Text(
                      currentRoom['description'],
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    
                    // Show dimensions if available
                    if (currentRoom.containsKey('estimated_dimensions')) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Estimated Dimensions:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Width: ${currentRoom['estimated_dimensions']['width_cm']} cm'),
                                Text('Length: ${currentRoom['estimated_dimensions']['length_cm']} cm'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Area: ${currentRoom['estimated_dimensions']['area_sqm']} m²'),
                                Text('Ceiling: ${currentRoom['estimated_dimensions']['estimated_ceiling_height_cm']} cm'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    
                    // Show detected elements if available
                    if (currentRoom.containsKey('doors') && currentRoom['doors'].isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Detected Elements:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.door_front_door, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text('${currentRoom['doors'].length} doors'),
                          const SizedBox(width: 16),
                          if (currentRoom.containsKey('windows') && currentRoom['windows'].isNotEmpty) ...[
                            Icon(Icons.window, size: 16, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text('${currentRoom['windows'].length} windows'),
                          ],
                        ],
                      ),
                    ],
                    
                    // Show measurements if available
                    if (currentRoom.containsKey('measurements') && currentRoom['measurements'].isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Detected Measurements:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      ...currentRoom['measurements'].map<Widget>((measurement) => 
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '• ${measurement['value']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        )
                      ).toList(),
                    ],
                    
                    // Show confidence level
                    if (currentRoom.containsKey('confidence')) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Detection Confidence: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${(currentRoom['confidence'] * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: currentRoom['confidence'] > 0.8 ? Colors.green : 
                                     currentRoom['confidence'] > 0.6 ? Colors.orange : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          
          // Questions
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: vitalInfo.length,
              itemBuilder: (context, index) {
                return _buildInfoItem(vitalInfo[index]);
              },
            ),
          ),
          
          // Navigation buttons
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_currentRoomIndex > 0)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _currentRoomIndex--;
                        });
                      },
                      child: const Text('Previous Room'),
                    ),
                  ),
                if (_currentRoomIndex > 0) const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : () {
                      if (_currentRoomIndex < widget.rooms.length - 1) {
                        setState(() {
                          _currentRoomIndex++;
                        });
                      } else {
                        _submitAssessment();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentRoomIndex == widget.rooms.length - 1 
                          ? Colors.green 
                          : Colors.blue,
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_currentRoomIndex == widget.rooms.length - 1 
                            ? 'Complete Assessment' 
                            : 'Next Room'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VitalInfoItem {
  final String key;
  final String question;
  final InfoType type;
  final List<String>? options;
  final Importance importance;
  final bool hasImageAnalysis;
  final bool hasManualMeasurement;
  final String? dependsOn;
  final List<String>? dependsOnValue;

  VitalInfoItem({
    required this.key,
    required this.question,
    required this.type,
    this.options,
    required this.importance,
    this.hasImageAnalysis = false,
    this.hasManualMeasurement = false,
    this.dependsOn,
    this.dependsOnValue,
  });
}

enum InfoType { yesNo, multipleChoice, text, wallDepth, windowSize }
enum Importance { critical, high, medium, low }

class RoomSafetyData {
  final String roomId;
  final String roomName;
  final String roomType;
  final Map<String, dynamic> responses;

  RoomSafetyData({
    required this.roomId,
    required this.roomName,
    required this.roomType,
  }) : responses = {};

  Map<String, dynamic> toJson() {
    return {
      'room_id': roomId,
      'room_name': roomName,
      'room_type': roomType,
      'responses': responses,
    };
  }
}

// Placeholder for results screen
class SafetyResultsScreen extends StatelessWidget {
  final Map<String, dynamic> safetyReport;
  final String annotationId;
  final String? analysisId; // New parameter for structured data

  const SafetyResultsScreen({
    Key? key,
    required this.safetyReport,
    required this.annotationId,
    this.analysisId, // Optional for backward compatibility
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_on),
            onPressed: () => _navigateToEnhancedHeatmap(context),
            tooltip: 'View Enhanced Heatmap',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: const Center(
              child: Text('Safety Results - To be implemented'),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _navigateToEnhancedHeatmap(context),
                  icon: const Icon(Icons.grid_on),
                  label: const Text('View Enhanced Safety Heatmap'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Assessment'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEnhancedHeatmap(BuildContext context) {
    // Convert safety report data to format expected by enhanced heatmap screen
    final rooms = <Map<String, dynamic>>[];
    
    // If rooms data is available in the safety report, use it
    if (safetyReport.containsKey('rooms')) {
      rooms.addAll(List<Map<String, dynamic>>.from(safetyReport['rooms']));
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnhancedSafetyHeatmapScreen(
          rooms: rooms,
          architecturalElements: [], // Will be configured in the screen
          annotationId: annotationId,
          analysisId: analysisId, // Pass analysis_id for structured approach
        ),
      ),
    );
  }
} 