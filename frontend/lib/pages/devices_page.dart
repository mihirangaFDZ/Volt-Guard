import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/device_service.dart';
import '../services/fault_detection_service.dart';
import '../services/ml_training_service.dart';
import '../models/energy_reading.dart';

/// Devices page showing connected IoT devices with 24h insights and fault detection
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

enum TimeRange { hours6, hours24, days7 }

class _DevicesPageState extends State<DevicesPage> {
  final DeviceService _deviceService = DeviceService();
  final FaultDetectionService _faultService = FaultDetectionService();
  final MLTrainingService _mlTrainingService = MLTrainingService();
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  String? _error;
  final Map<String, bool> _expandedDevices = {};
  final Map<String, List<EnergyReading>> _deviceReadings = {};
  final Map<String, bool> _loadingReadings = {};
  final Map<String, String?> _readingErrors = {};
  final Map<String, DateTime> _lastUpdated = {};
  final Map<String, TimeRange> _timeRanges = {};
  final Map<String, List<dynamic>> _deviceFaults = {};
  final Map<String, bool> _loadingFaults = {};
  Map<String, Map<String, dynamic>> _deviceHealth = {}; // Store device health data
  
  // Summary statistics
  int _totalDevices = 0;
  int _activeDevices = 0;
  int _totalFaults = 0;
  bool _loadingSummary = false;
  final Map<String, DateTime?> _deviceLastReadings = {}; // Track last reading time per device

  // ML training status
  Map<String, dynamic>? _trainingStatus;
  Map<String, dynamic>? _modelInfo;
  bool _trainingStatusLoading = false;
  bool _modelInfoLoading = false;
  String? _trainingStatusError;
  String? _modelInfoError;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _loadMlOps();
  }

  Future<void> _loadDevices() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
        _loadingSummary = true;
      });

      final devices = await _deviceService.fetchDevices();
      if (!mounted) return;

      setState(() {
        _devices = devices;
        _totalDevices = devices.length;
        // Initialize time ranges to 24h
        for (final device in devices) {
          final deviceId = device['device_id'] as String? ?? '';
          _timeRanges[deviceId] = TimeRange.hours24;
        }
      });

      // Load summary statistics and device health
      await Future.wait([
        _loadSummaryStatistics(),
        _loadDeviceHealth(),
      ]);
      
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load devices: $e';
        _loading = false;
        _loadingSummary = false;
      });
    }
  }

  Future<void> _loadMlOps() async {
    await Future.wait([
      _loadTrainingStatus(),
      _loadModelInfo(),
    ]);
  }

  Future<void> _loadTrainingStatus() async {
    try {
      setState(() {
        _trainingStatusLoading = true;
        _trainingStatusError = null;
      });
      final status = await _mlTrainingService.fetchStatus();
      if (!mounted) return;
      setState(() {
        _trainingStatus = status;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trainingStatusError = 'Unable to load training status: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _trainingStatusLoading = false;
      });
    }
  }

  Future<void> _loadModelInfo() async {
    try {
      setState(() {
        _modelInfoLoading = true;
        _modelInfoError = null;
      });
      final info = await _mlTrainingService.fetchModelInfo();
      if (!mounted) return;
      setState(() {
        _modelInfo = info;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelInfoError = 'Unable to load model info: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _modelInfoLoading = false;
      });
    }
  }

  Future<void> _startTraining() async {
    try {
      setState(() {
        _trainingStatusLoading = true;
        _trainingStatusError = null;
      });
      final result = await _mlTrainingService.startTraining();
      if (!mounted) return;
      setState(() {
        _trainingStatus = {
          "status": "running",
          "last_trained": DateTime.now().toUtc().toIso8601String(),
          "message": result["message"] ?? "Training initiated",
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ML training started in background')),
      );
      await Future.delayed(const Duration(seconds: 1));
      await _loadTrainingStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trainingStatusError = 'Failed to start training: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Training failed to start: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _trainingStatusLoading = false;
      });
    }
  }

  Future<void> _loadDeviceHealth() async {
    try {
      final deviceHealth = await _faultService.fetchDeviceHealth(limit: 100);
      if (!mounted) return;
      
      final healthMap = <String, Map<String, dynamic>>{};
      for (final health in deviceHealth) {
        final deviceId = health['device_id'] as String?;
        if (deviceId != null) {
          healthMap[deviceId] = health as Map<String, dynamic>;
        }
      }
      
      setState(() {
        _deviceHealth = healthMap;
      });
    } catch (e) {
      // Silently fail - health is not critical
    }
  }

  Future<void> _loadSummaryStatistics() async {
    try {
      // Fetch active faults
      final activeFaults = await _faultService.fetchActive(limit: 100);
      
      // Check active devices by fetching latest readings for each device
      int activeCount = 0;
      final now = DateTime.now();
      
      for (final device in _devices) {
        final deviceId = device['device_id'] as String? ?? '';
        try {
          // Fetch just the latest reading (limit=1) to check if device is active
          final data = await _deviceService.fetchDeviceEnergyReadings(
            deviceId,
            limit: 1,
            hours: 1, // Check last hour
          );
          final readings = data['readings'] as List<EnergyReading>;
          if (readings.isNotEmpty) {
            final lastReading = readings.first;
            final timeDiff = now.difference(lastReading.receivedAt);
            _deviceLastReadings[deviceId] = lastReading.receivedAt;
            
            // Active if last reading is less than 5 seconds ago
            if (timeDiff.inSeconds < 5) {
              activeCount++;
            }
          }
        } catch (e) {
          // If error fetching, consider device inactive
          _deviceLastReadings[deviceId] = null;
        }
      }
      
      if (!mounted) return;
      setState(() {
        _activeDevices = activeCount;
        _totalFaults = activeFaults.length;
      });
    } catch (e) {
      // Silently fail - summary is not critical
      if (mounted) {
        setState(() {
          _activeDevices = 0;
          _totalFaults = 0;
        });
      }
    }
  }

  void _toggleDevice(String deviceId) {
    setState(() {
      final isExpanded = _expandedDevices[deviceId] ?? false;
      _expandedDevices[deviceId] = !isExpanded;

      if (!isExpanded) {
        // Expanding: load data
        _loadDeviceData(deviceId);
      }
    });
  }

  int _getHoursForRange(TimeRange range) {
    switch (range) {
      case TimeRange.hours6:
        return 6;
      case TimeRange.hours24:
        return 24;
      case TimeRange.days7:
        return 168; // 7 days
    }
  }

  String _getTimeRangeLabel(TimeRange range) {
    switch (range) {
      case TimeRange.hours6:
        return '6h Insights';
      case TimeRange.hours24:
        return '24h Insights';
      case TimeRange.days7:
        return '7d Insights';
    }
  }

  Future<void> _loadDeviceData(String deviceId) async {
    await Future.wait([
      _loadDeviceReadings(deviceId),
      _loadDeviceFaults(deviceId),
    ]);
  }

  Future<void> _loadDeviceReadings(String deviceId) async {
    if (_loadingReadings[deviceId] == true) return;

    setState(() {
      _loadingReadings[deviceId] = true;
      _readingErrors[deviceId] = null;
    });

    try {
      final timeRange = _timeRanges[deviceId] ?? TimeRange.hours24;
      final hours = _getHoursForRange(timeRange);
      final data = await _deviceService.fetchDeviceEnergyReadings(
        deviceId,
        limit: 5000,
        hours: hours,
      );
      if (!mounted) return;

      final readings = data['readings'] as List<EnergyReading>;
      final now = DateTime.now();
      setState(() {
        _deviceReadings[deviceId] = readings;
        _loadingReadings[deviceId] = false;
        _lastUpdated[deviceId] = now;
        
        // Update last reading time for active device calculation
        if (readings.isNotEmpty) {
          _deviceLastReadings[deviceId] = readings.first.receivedAt;
        }
        
        // Recalculate active devices count
        _recalculateActiveDevices();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _readingErrors[deviceId] = 'Failed to load readings: $e';
        _loadingReadings[deviceId] = false;
      });
    }
  }

  Future<void> _loadDeviceFaults(String deviceId) async {
    if (_loadingFaults[deviceId] == true) return;

    setState(() {
      _loadingFaults[deviceId] = true;
    });

    try {
      final faults = await _faultService.fetchDeviceFaultHistory(deviceId, limit: 50);
      if (!mounted) return;

      setState(() {
        _deviceFaults[deviceId] = faults;
        _loadingFaults[deviceId] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFaults[deviceId] = false;
      });
    }
  }

  void _onTimeRangeChanged(String deviceId, TimeRange range) {
    setState(() {
      _timeRanges[deviceId] = range;
    });
    _loadDeviceReadings(deviceId);
  }

  void _recalculateActiveDevices() {
    final now = DateTime.now();
    int activeCount = 0;
    for (final device in _devices) {
      final deviceId = device['device_id'] as String? ?? '';
      final lastReading = _deviceLastReadings[deviceId];
      if (lastReading != null && now.difference(lastReading).inSeconds < 5) {
        activeCount++;
      }
    }
    setState(() {
      _activeDevices = activeCount;
    });
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 2,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'Device Overview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadingSummary)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryItem(
                      'Total Devices',
                      '$_totalDevices',
                      Icons.devices,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryItem(
                      'Active Devices',
                      '$_activeDevices',
                      Icons.check_circle,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryItem(
                      'Active Faults',
                      '$_totalFaults',
                      Icons.warning,
                      _totalFaults > 0 ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMlOpsCard() {
    final String status = (_trainingStatus?['status'] ?? 'unknown').toString();
    final String? message = _trainingStatus?['message']?.toString();
    final String? lastTrained = _trainingStatus?['last_trained']?.toString();
    final bool isRunning = status == 'running';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.precision_manufacturing, color: _statusColor(status)),
                const SizedBox(width: 8),
                const Text(
                  'ML Operations',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _buildStatusChip(status),
              ],
            ),
            const SizedBox(height: 12),
            if (_trainingStatusLoading) const LinearProgressIndicator(minHeight: 3),
            if (_trainingStatusError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _trainingStatusError!,
                  style: TextStyle(fontSize: 12, color: Colors.red[700]),
                ),
              ),
            if (message != null && message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text(
                  'Last trained: ${_formatTimestamp(lastTrained)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isRunning || _trainingStatusLoading ? null : _startTraining,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Training'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _trainingStatusLoading ? null : _loadMlOps,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                const Spacer(),
                if ((_trainingStatus?['output'] != null) || (_trainingStatus?['error'] != null))
                  TextButton(
                    onPressed: _showTrainingLogs,
                    child: const Text('View Logs'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildModelInfoSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildModelInfoSection() {
    if (_modelInfoLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    if (_modelInfoError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _modelInfoError!,
          style: TextStyle(fontSize: 12, color: Colors.red[700]),
        ),
      );
    }
    if (_modelInfo == null) {
      return Text(
        'Model info not available yet.',
        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
      );
    }

    final Map<String, dynamic> rf =
        (_modelInfo?['random_forest'] as Map?)?.cast<String, dynamic>() ?? {};
    final Map<String, dynamic> iso =
        (_modelInfo?['isolation_forest'] as Map?)?.cast<String, dynamic>() ?? {};
    final Map<String, dynamic> lstm =
        (_modelInfo?['lstm'] as Map?)?.cast<String, dynamic>() ?? {};

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildModelTile(
          title: 'Random Forest',
          data: rf,
          accent: Colors.blue,
          lines: [
            'Status: ${rf['status'] ?? 'unknown'}',
            'Features: ${_countFeatures(rf['features'])}',
            'MAE: ${_formatMetric(_nestedNum(rf, 'metrics', 'mae'))}',
            'R²: ${_formatMetric(_nestedNum(rf, 'metrics', 'r2'))}',
          ],
        ),
        _buildModelTile(
          title: 'Isolation Forest',
          data: iso,
          accent: Colors.orange,
          lines: [
            'Status: ${iso['status'] ?? 'unknown'}',
            'Features: ${_countFeatures(iso['features'])}',
          ],
        ),
        _buildModelTile(
          title: 'LSTM',
          data: lstm,
          accent: Colors.teal,
          lines: [
            'Status: ${lstm['status'] ?? 'unknown'}',
            'Seq length: ${lstm['sequence_length'] ?? 'n/a'}',
            'Horizon: ${lstm['prediction_horizon'] ?? 'n/a'}',
          ],
        ),
      ],
    );
  }

  Widget _buildModelTile({
    required String title,
    required Map<String, dynamic> data,
    required Color accent,
    required List<String> lines,
  }) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...lines.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              )),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'running':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'idle':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildStatusChip(String status) {
    final Color color = _statusColor(status);
    final String label = status.isEmpty ? 'unknown' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return 'n/a';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  int _countFeatures(dynamic value) {
    if (value is List) return value.length;
    return 0;
  }

  double? _nestedNum(Map<String, dynamic> source, String key1, String key2) {
    final Map<String, dynamic>? nested = (source[key1] as Map?)?.cast<String, dynamic>();
    final value = nested?[key2];
    if (value is num) return value.toDouble();
    return null;
  }

  String _formatMetric(double? value) {
    if (value == null) return 'n/a';
    return value.toStringAsFixed(3);
  }

  void _showTrainingLogs() {
    final String output = _trainingStatus?['output']?.toString() ?? '';
    final String error = _trainingStatus?['error']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scrollController,
                children: [
                  const Text(
                    'Training Logs',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (error.isNotEmpty) ...[
                    Text('Error', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(error, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 12),
                  ],
                  if (output.isNotEmpty) ...[
                    const Text('Output', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    SelectableText(output, style: const TextStyle(fontSize: 12)),
                  ],
                  if (output.isEmpty && error.isEmpty)
                    const Text('No logs available yet.', style: TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'ac':
      case 'air conditioner':
        return Icons.ac_unit;
      case 'pc':
      case 'computer':
        return Icons.computer;
      case 'lab':
        return Icons.science;
      default:
        return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDeviceDialog(context),
            tooltip: 'Add Device',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadDevices(),
            _loadMlOps(),
          ]);
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDevices,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_other, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No devices found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Summary Statistics Card
        _buildSummaryCard(),
        const SizedBox(height: 16),
        _buildMlOpsCard(),
        const SizedBox(height: 16),
        ..._devices.map((device) => _buildDeviceCard(device)),
      ],
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> device) {
    final deviceId = device['device_id'] as String? ?? '';
    final deviceName = device['device_name'] as String? ?? deviceId;
    final deviceType = device['device_type'] as String? ?? 'device';
    final moduleId = device['module_id'] as String?;
    final isExpanded = _expandedDevices[deviceId] ?? false;
    final readings = _deviceReadings[deviceId] ?? [];
    final faults = _deviceFaults[deviceId] ?? [];
    final activeFaults = faults.where((f) => f['status'] == 'active').toList();
    final hasReadings = readings.isNotEmpty;
    final latestReading = hasReadings ? readings.first : null;
    
    // Check if device is active (last reading < 5 seconds)
    final lastReadingTime = _deviceLastReadings[deviceId];
    final isActive = lastReadingTime != null && 
        DateTime.now().difference(lastReadingTime).inSeconds < 5;

    // Get device health from API or calculate from faults/readings
    final deviceHealthData = _deviceHealth[deviceId];
    double healthPercentage = 90.0;
    String statusText = 'Operating normally';
    Color statusColor = Colors.green;
    bool hasInsights = hasReadings;

    if (deviceHealthData != null) {
      // Use health from API
      healthPercentage = (deviceHealthData['health_score'] as num?)?.toDouble() ?? 90.0;
      final status = deviceHealthData['status'] as String? ?? 'Good';
      statusText = deviceHealthData['notes'] != null && 
          (deviceHealthData['notes'] as List).isNotEmpty
          ? (deviceHealthData['notes'] as List).first.toString()
          : 'Operating normally';
      
      if (status == 'Critical') {
        statusColor = Colors.red;
        statusText = statusText.isEmpty ? 'Critical issues detected' : statusText;
      } else if (status == 'Fair') {
        statusColor = Colors.orange;
        statusText = statusText.isEmpty ? 'Fair condition' : statusText;
      } else {
        statusColor = Colors.green;
        statusText = statusText.isEmpty ? 'Operating normally' : statusText;
      }
    } else if (activeFaults.isNotEmpty) {
      // Fallback: calculate from faults
      final criticalFaults = activeFaults.where((f) => f['severity'] == 'Critical').length;
      final highFaults = activeFaults.where((f) => f['severity'] == 'High').length;
      if (criticalFaults > 0) {
        healthPercentage = 30.0;
        statusText = 'Critical fault detected';
        statusColor = Colors.red;
      } else if (highFaults > 0) {
        healthPercentage = 60.0;
        statusText = 'Warning: High severity fault';
        statusColor = Colors.orange;
      } else {
        healthPercentage = 75.0;
        statusText = 'Minor issues detected';
        statusColor = Colors.orange;
      }
    } else if (latestReading != null) {
      // Fallback: calculate from RSSI
      final rssi = latestReading.wifiRssi ?? -100;
      healthPercentage = ((rssi + 100) / 50 * 100).clamp(0.0, 100.0);
    }

    final icon = _getDeviceIcon(deviceType);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _toggleDevice(deviceId),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 32, color: statusColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle, size: 6, color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Active',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (moduleId != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Module: $moduleId',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                        if (hasInsights) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.insights, size: 12, color: Colors.blue[300]),
                              const SizedBox(width: 4),
                              Text(
                                'Insights ready',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${healthPercentage.toInt()}%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        _getHealthLabel(healthPercentage),
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
            // Health progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: LinearProgressIndicator(
                value: healthPercentage / 100,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 4,
              ),
            ),
            // Expanded content
            if (isExpanded) _buildExpandedContent(deviceId, device, readings, faults),
          ],
        ),
      ),
    );
  }

  String _getHealthLabel(double percentage) {
    if (percentage >= 80) return 'Good';
    if (percentage >= 60) return 'Fair';
    if (percentage >= 40) return 'Warning';
    return 'Critical';
  }

  Widget _buildExpandedContent(
    String deviceId,
    Map<String, dynamic> device,
    List<EnergyReading> readings,
    List<dynamic> faults,
  ) {
    final isLoading = _loadingReadings[deviceId] == true;
    final error = _readingErrors[deviceId];
    final lastUpdated = _lastUpdated[deviceId];
    final timeRange = _timeRanges[deviceId] ?? TimeRange.hours24;
    final activeFaults = faults.where((f) => f['status'] == 'active').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time range selector and refresh
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<TimeRange>(
                      segments: const [
                        ButtonSegment(value: TimeRange.hours6, label: Text('6h')),
                        ButtonSegment(value: TimeRange.hours24, label: Text('24h')),
                        ButtonSegment(value: TimeRange.days7, label: Text('7d')),
                      ],
                      selected: {timeRange},
                      onSelectionChanged: (Set<TimeRange> selected) {
                        if (selected.isNotEmpty) {
                          _onTimeRangeChanged(deviceId, selected.first);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => _loadDeviceData(deviceId),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Last updated timestamp
              if (lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'Last refreshed: ${_formatTime(lastUpdated)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (isLoading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ),

              // Error state
              if (error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _loadDeviceReadings(deviceId),
                        child: const Text('Retry', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),

              // Fault Detection Section
              if (activeFaults.isNotEmpty) _buildFaultSection(deviceId, activeFaults, faults),

              // 24h Insights
              if (readings.isEmpty && !isLoading && error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.data_usage, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No data in last ${_getHoursForRange(timeRange)}h',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _loadDeviceReadings(deviceId),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (readings.isNotEmpty && error == null)
                _buildInsightsSection(readings, timeRange),

              // Fault History Link
              if (faults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => _showFaultHistory(deviceId, device['device_name'] as String? ?? deviceId),
                    icon: const Icon(Icons.history, size: 18),
                    label: Text('View Fault History (${faults.length})'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 36),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFaultSection(String deviceId, List<dynamic> activeFaults, List<dynamic> allFaults) {
    final criticalCount = activeFaults.where((f) => f['severity'] == 'Critical').length;
    final highCount = activeFaults.where((f) => f['severity'] == 'High').length;
    final mediumCount = activeFaults.where((f) => f['severity'] == 'Medium').length;
    final lowCount = activeFaults.where((f) => f['severity'] == 'Low').length;

    // Get latest fault
    final latestFault = activeFaults.isNotEmpty
        ? activeFaults.reduce((a, b) {
            final aTime = _parseDateTime(a['detected_at']);
            final bTime = _parseDateTime(b['detected_at']);
            return aTime.isAfter(bTime) ? a : b;
          })
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Active Faults: ${activeFaults.length}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (latestFault != null) ...[
            Text(
              latestFault['issue'] as String? ?? 'Unknown issue',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Severity: ${latestFault['severity']} • Detected: ${_formatTime(_parseDateTime(latestFault['detected_at']).toLocal())}',
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (criticalCount > 0)
                _buildFaultBadge('Critical: $criticalCount', Colors.red),
              if (highCount > 0)
                _buildFaultBadge('High: $highCount', Colors.orange),
              if (mediumCount > 0)
                _buildFaultBadge('Medium: $mediumCount', Colors.amber),
              if (lowCount > 0)
                _buildFaultBadge('Low: $lowCount', Colors.blue),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Suggested: Check device connections and review fault history for details.',
            style: TextStyle(fontSize: 11, color: Colors.grey[700], fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildFaultBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildInsightsSection(List<EnergyReading> readings, TimeRange timeRange) {
    if (readings.isEmpty) return const SizedBox.shrink();

    // Calculate statistics
    final currents = readings.map((r) => r.currentA).toList();

    final minCurrent = currents.reduce((a, b) => a < b ? a : b);
    final maxCurrent = currents.reduce((a, b) => a > b ? a : b);
    final avgCurrent = currents.reduce((a, b) => a + b) / currents.length;

    // Calculate power consumption in kW (assuming 230V standard voltage)
    // Power (kW) = Current (A) × Voltage (V) / 1000
    const double standardVoltage = 230.0; // Standard voltage in V
    final maxPowerKw = (maxCurrent * standardVoltage) / 1000;
    final avgPowerKw = (avgCurrent * standardVoltage) / 1000;

    // Calculate total usage (energy consumption in kWh) from all readings
    // Sort readings chronologically (oldest first) for accurate calculation
    final sortedReadings = List<EnergyReading>.from(readings)
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    
    double totalUsageKwh = 0.0;
    if (sortedReadings.length > 1) {
      // Calculate energy for each time interval between consecutive readings
      // Using trapezoidal rule: average power between two readings × time interval
      for (int i = 0; i < sortedReadings.length - 1; i++) {
        final reading1 = sortedReadings[i];
        final reading2 = sortedReadings[i + 1];
        
        // Calculate power at each reading point
        final power1Kw = (reading1.currentA * standardVoltage) / 1000;
        final power2Kw = (reading2.currentA * standardVoltage) / 1000;
        final avgPowerKw = (power1Kw + power2Kw) / 2.0;
        
        // Calculate time interval in hours
        final timeDiff = reading2.receivedAt.difference(reading1.receivedAt);
        final hoursInterval = timeDiff.inSeconds / 3600.0;
        
        // Energy = Average Power × Time Interval
        totalUsageKwh += avgPowerKw * hoursInterval;
      }
      
      // For the last reading, calculate energy from last reading to end of time range
      // or to now if the last reading is recent (within 1 hour)
      final lastReading = sortedReadings.last;
      final now = DateTime.now();
      final timeSinceLastReading = now.difference(lastReading.receivedAt);
      
      // Only extrapolate if last reading is recent (within 1 hour)
      // Otherwise, use the last reading's power for the average interval period
      if (timeSinceLastReading.inHours < 1) {
        // Recent reading: extrapolate to now
        final lastPowerKw = (lastReading.currentA * standardVoltage) / 1000;
        final hoursSinceLast = timeSinceLastReading.inSeconds / 3600.0;
        totalUsageKwh += lastPowerKw * hoursSinceLast;
      } else {
        // Old reading: use average interval between readings
        if (sortedReadings.length >= 2) {
          final totalTimeSpan = sortedReadings.last.receivedAt
              .difference(sortedReadings.first.receivedAt)
              .inSeconds /
              3600.0;
          final avgInterval = totalTimeSpan / (sortedReadings.length - 1);
          final lastPowerKw = (lastReading.currentA * standardVoltage) / 1000;
          totalUsageKwh += lastPowerKw * avgInterval;
        }
      }
    } else if (sortedReadings.length == 1) {
      // Single reading: estimate based on time since reading or time range
      final reading = sortedReadings.first;
      final now = DateTime.now();
      final timeSinceReading = now.difference(reading.receivedAt);
      
      final powerKw = (reading.currentA * standardVoltage) / 1000;
      final hoursInterval = timeSinceReading.inHours < 1
          ? timeSinceReading.inSeconds / 3600.0
          : _getHoursForRange(timeRange).toDouble();
      totalUsageKwh = powerKw * hoursInterval;
    }

    // Calculate uptime/coverage
    final expectedReadings = _getHoursForRange(timeRange) * 3600; // Assuming 1 reading per second
    final coverage = (readings.length / expectedReadings * 100).clamp(0.0, 100.0);

    final latestReading = readings.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getTimeRangeLabel(timeRange),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Sparkline
        _buildSparkline(readings),
        const SizedBox(height: 16),

        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.power, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Power Consumption',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPowerStat('Max', '${maxPowerKw.toStringAsFixed(3)} kW', Colors.red),
                    _buildPowerStat('Avg', '${avgPowerKw.toStringAsFixed(3)} kW', Colors.blue),
                    _buildPowerStat('Total Usage', '${totalUsageKwh.toStringAsFixed(3)} kWh', Colors.orange),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Calculated at ${standardVoltage}V standard voltage',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Statistics Grid - 6 cards matching screenshot
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: [
            _buildStatCard('Min Current', '${minCurrent.toStringAsFixed(3)} A', Icons.trending_down),
            _buildStatCard('Max Current', '${maxCurrent.toStringAsFixed(3)} A', Icons.trending_up),
            _buildStatCard('Avg Current', '${avgCurrent.toStringAsFixed(3)} A', Icons.show_chart),
            _buildStatCard('Samples', '${readings.length}', Icons.data_usage),
            _buildStatCard('Coverage', '${coverage.toStringAsFixed(1)}%', Icons.signal_cellular_alt),
            _buildStatCard('Latest', _formatTime(latestReading.receivedAt.toLocal()), Icons.access_time),
          ],
        ),
        const SizedBox(height: 16),
        
      ],
    );
  }

  Widget _buildPowerStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.blue[700]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSparkline(List<EnergyReading> readings) {
    // Sample readings for sparkline (max 100 points)
    final sampleSize = readings.length > 100 ? 100 : readings.length;
    final step = readings.length > 100 ? (readings.length / 100).ceil() : 1;
    final sampledReadings = <EnergyReading>[];
    for (int i = 0; i < readings.length; i += step) {
      sampledReadings.add(readings[i]);
      if (sampledReadings.length >= sampleSize) break;
    }
    final displayReadings = sampledReadings.reversed.toList();
    if (displayReadings.isEmpty) return const SizedBox.shrink();

    final maxCurrent = displayReadings.map((r) => r.currentA).reduce((a, b) => a > b ? a : b);
    final minCurrent = displayReadings.map((r) => r.currentA).reduce((a, b) => a < b ? a : b);
    final range = (maxCurrent - minCurrent).abs();
    final padding = range * 0.1;

    final spots = displayReadings.asMap().entries.map((entry) {
      final index = entry.key;
      final reading = entry.value;
      final normalized = range > 0
          ? ((reading.currentA - minCurrent + padding) / (range + padding * 2))
          : 0.5;
      return FlSpot(index.toDouble(), 1 - normalized);
    }).toList();

    return Container(
      height: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.green,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.green.withOpacity(0.1),
              ),
            ),
          ],
          minY: 0,
          maxY: 1,
        ),
      ),
    );
  }

  void _showFaultHistory(String deviceId, String deviceName) {
    final faults = _deviceFaults[deviceId] ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Fault History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    deviceName,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: faults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 64, color: Colors.green[300]),
                          const SizedBox(height: 16),
                          Text(
                            'No faults recorded',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: faults.length,
                      itemBuilder: (context, index) {
                        final fault = faults[index];
                        final severity = fault['severity'] as String? ?? 'Low';
                        final status = fault['status'] as String? ?? 'resolved';
                        final detectedAt = _parseDateTime(fault['detected_at']);

                        Color severityColor;
                        switch (severity) {
                          case 'Critical':
                            severityColor = Colors.red;
                            break;
                          case 'High':
                            severityColor = Colors.orange;
                            break;
                          case 'Medium':
                            severityColor = Colors.amber;
                            break;
                          default:
                            severityColor = Colors.blue;
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: severityColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                status == 'active' ? Icons.warning : Icons.check_circle,
                                color: severityColor,
                                size: 24,
                              ),
                            ),
                            title: Text(
                              fault['issue'] as String? ?? 'Unknown issue',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Severity: $severity • Status: ${status.toUpperCase()}'),
                                Text('Detected: ${_formatTime(detectedAt.toLocal())}'),
                                if (fault['description'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      fault['description'] as String,
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: severityColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                severity,
                                style: TextStyle(
                                  color: severityColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed ?? DateTime.now();
    }
    return DateTime.now();
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$month/$day $hour:$minute';
    }
  }

  void _showAddDeviceDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final deviceIdController = TextEditingController();
    final deviceNameController = TextEditingController();
    final deviceTypeController = TextEditingController();
    final locationController = TextEditingController();
    final ratedPowerController = TextEditingController();
    final moduleIdController = TextEditingController();
    final installedDateController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Device'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: deviceIdController,
                    decoration: const InputDecoration(
                      labelText: 'Device ID *',
                      hintText: 'e.g., AC_01',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Device ID is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: deviceNameController,
                    decoration: const InputDecoration(
                      labelText: 'Device Name *',
                      hintText: 'e.g., Conference Room AC',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Device name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: deviceTypeController,
                    decoration: const InputDecoration(
                      labelText: 'Device Type *',
                      hintText: 'e.g., AC, PC, Lab',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Device type is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location *',
                      hintText: 'e.g., Conference Room, Lab 1',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Location is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: ratedPowerController,
                    decoration: const InputDecoration(
                      labelText: 'Rated Power (Watts) *',
                      hintText: 'e.g., 1200',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Rated power is required';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Please enter a valid number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: moduleIdController,
                    decoration: const InputDecoration(
                      labelText: 'Module ID (Optional)',
                      hintText: 'e.g., MOD001',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: installedDateController,
                    decoration: const InputDecoration(
                      labelText: 'Installed Date (Optional)',
                      hintText: 'YYYY-MM-DD',
                      border: OutlineInputBorder(),
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        installedDateController.text =
                            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() {
                          isSubmitting = true;
                        });

                        try {
                          final deviceData = <String, dynamic>{
                            'device_id': deviceIdController.text.trim(),
                            'device_name': deviceNameController.text.trim(),
                            'device_type': deviceTypeController.text.trim(),
                            'location': locationController.text.trim(),
                            'rated_power_watts': int.parse(ratedPowerController.text.trim()),
                          };

                          if (moduleIdController.text.trim().isNotEmpty) {
                            deviceData['module_id'] = moduleIdController.text.trim();
                          }

                          if (installedDateController.text.trim().isNotEmpty) {
                            deviceData['installed_date'] = installedDateController.text.trim();
                          }

                          await _deviceService.addDevice(deviceData);

                          if (!context.mounted) return;
                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Device added successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );

                          // Reload devices list
                          _loadDevices();
                        } catch (e) {
                          if (!context.mounted) return;
                          setDialogState(() {
                            isSubmitting = false;
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to add device: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add Device'),
            ),
          ],
        ),
      ),
    );
  }
}
