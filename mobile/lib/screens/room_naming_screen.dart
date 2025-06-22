import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'room_safety_assessment_screen.dart';
import 'enhanced_safety_heatmap_screen.dart';

class RoomNamingScreen extends StatefulWidget {
  final List rooms;
  const RoomNamingScreen({Key? key, required this.rooms}) : super(key: key);

  @override
  State<RoomNamingScreen> createState() => _RoomNamingScreenState();
}

class _RoomNamingScreenState extends State<RoomNamingScreen> {
  late List<TextEditingController> _controllers;
  List<File?> _imageFiles = [];
  List<Uint8List?> _webImages = [];

  @override
  void initState() {
    super.initState();
    _controllers = widget.rooms.map<TextEditingController>((room) => TextEditingController(text: room['default_name'])).toList();
    _imageFiles = List<File?>.filled(widget.rooms.length, null);
    _webImages = List<Uint8List?>.filled(widget.rooms.length, null);
  }

  Future<void> _pickWallImage(int index) async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImages[index] = bytes;
        });
      } else {
        setState(() {
          _imageFiles[index] = File(pickedFile.path);
        });
      }
    }
  }

  void _showSafetyAssessmentOptions() {
    // Update room names with user input
    final updatedRooms = widget.rooms.asMap().entries.map((entry) {
      final index = entry.key;
      final room = entry.value as Map<String, dynamic>;
      return {
        ...room,
        'name': _controllers[index].text,
        'type': _controllers[index].text.toLowerCase().contains('bedroom') ? 'bedroom' :
                _controllers[index].text.toLowerCase().contains('kitchen') ? 'kitchen' :
                _controllers[index].text.toLowerCase().contains('bathroom') ? 'bathroom' :
                _controllers[index].text.toLowerCase().contains('living') ? 'living' :
                _controllers[index].text.toLowerCase().contains('dining') ? 'dining' :
                _controllers[index].text.toLowerCase().contains('office') ? 'office' :
                _controllers[index].text.toLowerCase().contains('hall') ? 'hall' : 'room',
      };
    }).toList().cast<Map<String, dynamic>>();

    // Generate a unique annotation ID
    final annotationId = DateTime.now().millisecondsSinceEpoch.toString();

    // Show options dialog
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
                  _navigateToEnhancedHeatmap(updatedRooms, annotationId);
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
                  _navigateToTraditionalAssessment(updatedRooms, annotationId);
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
    Navigator.push(
      context,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoomSafetyAssessmentScreen(
          rooms: rooms,
          annotationId: annotationId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Name the Rooms')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.rooms.length,
              itemBuilder: (context, index) {
                final room = widget.rooms[index];
                Widget imageWidget;
                if (kIsWeb && _webImages[index] != null) {
                  imageWidget = Image.memory(_webImages[index]!, height: 100);
                } else if (!kIsWeb && _imageFiles[index] != null) {
                  imageWidget = Image.file(_imageFiles[index]!, height: 100);
                } else {
                  imageWidget = const Text('No wall image selected.');
                }
                return Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Room ID: ${room['room_id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _controllers[index],
                          decoration: const InputDecoration(labelText: 'Room Name'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            imageWidget,
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: () => _pickWallImage(index),
                              child: const Text('Upload Wall Side Photo'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Continue button at the bottom
          Container(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _showSafetyAssessmentOptions,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                'Continue to Safety Assessment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 