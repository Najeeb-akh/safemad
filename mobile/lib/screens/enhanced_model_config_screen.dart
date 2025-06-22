import 'package:flutter/material.dart';
import '../services/enhanced_floor_plan_service.dart';

class EnhancedModelConfigScreen extends StatefulWidget {
  const EnhancedModelConfigScreen({Key? key}) : super(key: key);

  @override
  _EnhancedModelConfigScreenState createState() => _EnhancedModelConfigScreenState();
}

class _EnhancedModelConfigScreenState extends State<EnhancedModelConfigScreen> {
  Map<String, dynamic>? _modelStatus;
  bool _loading = false;
  bool _checkingStatus = false;
  final TextEditingController _modelPathController = TextEditingController();
  String _statusMessage = '';
  Color _statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  @override
  void dispose() {
    _modelPathController.dispose();
    super.dispose();
  }

  Future<void> _checkModelStatus() async {
    setState(() { _checkingStatus = true; });
    
    try {
      final status = await EnhancedFloorPlanService.getModelStatus();
      setState(() { 
        _modelStatus = status;
        _checkingStatus = false;
        _updateStatusMessage();
      });
    } catch (e) {
      setState(() { 
        _checkingStatus = false;
        _statusMessage = 'Failed to check model status: $e';
        _statusColor = Colors.red;
      });
    }
  }

  void _updateStatusMessage() {
    if (_modelStatus == null) {
      _statusMessage = 'Unable to check model status';
      _statusColor = Colors.red;
      return;
    }

    if (_modelStatus!['enhanced_model_loaded'] == true) {
      _statusMessage = 'Enhanced model is loaded and ready';
      _statusColor = Colors.green;
    } else {
      _statusMessage = 'Enhanced model not loaded. Please set a model path.';
      _statusColor = Colors.orange;
    }
  }

  Future<void> _setModelPath() async {
    final modelPath = _modelPathController.text.trim();
    if (modelPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a model path')),
      );
      return;
    }

    setState(() { _loading = true; });
    
    try {
      final result = await EnhancedFloorPlanService.setModel(modelPath);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Model set successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh status
      await _checkModelStatus();
      
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set model: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhanced Model Configuration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkModelStatus,
            tooltip: 'Refresh status',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 20),
            _buildModelSetupCard(),
            const SizedBox(height: 20),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _checkingStatus ? Icons.hourglass_empty : Icons.info_outline,
                  color: _checkingStatus ? Colors.blue : _statusColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Model Status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_checkingStatus) ...[
              const Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Checking model status...'),
                ],
              ),
            ] else ...[
              _buildStatusItem('Enhanced Model', _modelStatus?['enhanced_model_loaded'] ?? false),
              _buildStatusItem('YOLO Detection', _modelStatus?['yolo_available'] ?? false),
              _buildStatusItem('Google Vision API', _modelStatus?['google_vision_api'] ?? false),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _statusColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: _statusColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(color: _statusColor),
                      ),
                    ),
                  ],
                ),
              ),
              if (_modelStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Recommended Method: ${_modelStatus!['recommended_method']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ],
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

  Widget _buildModelSetupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Model Setup',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _modelPathController,
              decoration: const InputDecoration(
                labelText: 'Model Path',
                hintText: 'Enter path to your .pt model file',
                border: OutlineInputBorder(),
                helperText: 'Example: /path/to/models/best.pt',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _setModelPath,
                icon: _loading 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
                label: Text(_loading ? 'Setting Model...' : 'Set Model'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Setup Instructions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'To use the enhanced floor plan detection:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildInstructionStep(
              1,
              'Download the trained YOLOv8 floor plan model (best.pt)',
            ),
            _buildInstructionStep(
              2,
              'Place the model file in your backend/models directory',
            ),
            _buildInstructionStep(
              3,
              'Enter the full path to the model file above',
            ),
            _buildInstructionStep(
              4,
              'Click "Set Model" to load the enhanced detection',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Tip:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'The enhanced model can detect architectural elements like doors, windows, walls, and stairs with high accuracy. This provides much better room detection and safety assessment capabilities.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(int step, String instruction) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                step.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(instruction),
          ),
        ],
      ),
    );
  }
} 