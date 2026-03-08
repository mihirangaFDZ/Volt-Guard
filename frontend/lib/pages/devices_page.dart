import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/device_service.dart';
import '../services/fault_detection_service.dart';
import '../services/behavioral_profile_service.dart';
import '../services/prediction_service.dart';
import '../services/anomaly_alert_service.dart';
import '../services/ml_training_manager.dart';
import '../services/model_evaluation_service.dart';
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
  final BehavioralProfileService _profileService = BehavioralProfileService();
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
  Map<String, Map<String, dynamic>> _deviceHealth =
      {}; // Store device health data

  // Relay control state
  final Map<String, bool> _relayStates = {};
  final Map<String, bool> _relayLoading = {};

  // Summary statistics
  int _totalDevices = 0;
  int _activeDevices = 0;
  int _totalFaults = 0;
  bool _loadingSummary = false;
  final Map<String, DateTime?> _deviceLastReadings =
      {}; // Track last reading time per device

  // Energy vampire / behavioral profiles
  List<dynamic> _energyVampires = [];
  bool _vampiresLoading = false;
  String? _vampiresError;
  double _totalEnergyWaste = 0.0;
  final Map<String, Map<String, dynamic>> _deviceProfiles = {};

  // Energy Forecast state
  final PredictionService _predictionService = PredictionService();
  String? _forecastSelectedDeviceId;
  Map<String, dynamic>? _deviceForecast;
  bool _forecastLoading = false;
  String? _forecastError;
  // Device comparison state
  Map<String, dynamic>? _deviceComparison;
  bool _comparisonLoading = false;
  String? _comparisonError;

  // Anomaly detection state
  final AnomalyAlertService _anomalyService = AnomalyAlertService();
  final ModelEvaluationService _evalService = ModelEvaluationService();
  Map<String, Map<String, dynamic>> _deviceAnomalies = {};
  bool _anomalyLoading = false;
  String? _anomalyError;

  @override
  void initState() {
    super.initState();
    _loadDevices(); // Energy vampires load in background after list is shown
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
        _loading = false; // Show list immediately
        // Initialize time ranges to 24h and relay states
        for (final device in devices) {
          final deviceId = device['device_id'] as String? ?? '';
          _timeRanges[deviceId] = TimeRange.hours24;
          final relayState = device['relay_state'] as String? ?? 'OFF';
          _relayStates[deviceId] = relayState == 'ON';
        }
      });

      // Load summary (faults only) and anomaly in background — don't block list
      _loadSummaryStatistics().then((_) {
        if (mounted) setState(() => _loadingSummary = false);
      });
      _loadAnomalyDetection();

      // Forecast, comparison, and energy vampires in background
      final devicesWithModule = _devices
          .where((d) =>
              d['module_id'] != null && (d['module_id'] as String).isNotEmpty)
          .toList();
      if (devicesWithModule.isNotEmpty) {
        final firstId = devicesWithModule.first['device_id'] as String? ?? '';
        if (firstId.isNotEmpty) {
          setState(() => _forecastSelectedDeviceId = firstId);
          _loadDeviceForecast(firstId);
        }
        _loadDeviceComparison();
      }
      _loadEnergyVampires();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load devices: $e';
        _loading = false;
        _loadingSummary = false;
      });
    }
  }

  Future<void> _loadDeviceForecast(String deviceId) async {
    setState(() {
      _forecastLoading = true;
      _forecastError = null;
      _deviceForecast = null;
    });
    try {
      final forecast = await _predictionService.fetchDeviceForecast(deviceId);
      if (!mounted) return;
      setState(() {
        _deviceForecast = forecast;
        _forecastLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('503')) {
        msg = 'LSTM model is still loading. Please try again in a moment.';
      } else if (msg.contains('400')) {
        msg = 'Not enough energy data for this device to generate a forecast.';
      } else if (msg.contains('TimeoutException') ||
          msg.contains('timed out')) {
        msg = 'Forecast request timed out. The LSTM model may be busy.';
      }
      setState(() {
        _forecastError = msg;
        _forecastLoading = false;
      });
    }
  }

  Future<void> _loadDeviceComparison() async {
    setState(() {
      _comparisonLoading = true;
      _comparisonError = null;
    });
    try {
      final comparison = await _predictionService.fetchDeviceComparison();
      if (!mounted) return;
      setState(() {
        _deviceComparison = comparison;
        _comparisonLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('503')) {
        msg = 'LSTM model is still loading. Please pull to refresh.';
      } else if (msg.contains('TimeoutException') ||
          msg.contains('timed out')) {
        msg = 'Comparison request timed out. Try refreshing.';
      }
      setState(() {
        _comparisonError = msg;
        _comparisonLoading = false;
      });
    }
  }

  Future<void> _loadEnergyVampires() async {
    try {
      setState(() {
        _vampiresLoading = true;
        _vampiresError = null;
      });
      final data = await _profileService.fetchEnergyVampires(hoursBack: 168);
      if (!mounted) return;

      final vampires = data['vampires'] as List<dynamic>? ?? [];
      final totalWaste =
          (data['total_energy_waste_kwh'] as num?)?.toDouble() ?? 0.0;

      // Also cache profiles by device_id
      final profileMap = <String, Map<String, dynamic>>{};
      for (final v in vampires) {
        final id = v['device_id'] as String?;
        if (id != null) profileMap[id] = Map<String, dynamic>.from(v as Map);
      }

      setState(() {
        _energyVampires = vampires;
        _totalEnergyWaste = totalWaste;
        _deviceProfiles.addAll(profileMap);
        _vampiresLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final String message = e.toString().contains('TimeoutException') ||
              e.toString().contains('timed out')
          ? 'Request timed out. Tap refresh to try again.'
          : 'Unable to load energy vampires: $e';
      setState(() {
        _vampiresError = message;
        _vampiresLoading = false;
      });
    }
  }

  Future<void> _loadDeviceProfile(String deviceId) async {
    if (_deviceProfiles.containsKey(deviceId)) return;
    try {
      final profile =
          await _profileService.fetchDeviceProfile(deviceId, hoursBack: 168);
      if (!mounted) return;
      setState(() {
        _deviceProfiles[deviceId] = profile;
      });
    } catch (_) {
      // Profile not available — not critical
    }
  }

  Future<void> _loadAnomalyDetection() async {
    setState(() {
      _anomalyLoading = true;
      _anomalyError = null;
    });
    try {
      // Check if model is ready first
      final manager = MLTrainingManager.instance;
      await manager.refreshStatus();

      if (manager.isTraining) {
        setState(() {
          _anomalyLoading = false;
          _anomalyError = 'model_training';
        });
        return;
      }

      final result = await _anomalyService.detectAnomalies(
        hoursBack: 24,
        minScore: 0.3,
        method: 'isolation_forest',
      );
      if (!mounted) return;

      final anomalies = result['anomalies'] as List<dynamic>? ?? [];

      // Group anomalies by device_id, keeping the highest score per device
      final anomalyMap = <String, Map<String, dynamic>>{};
      for (final a in anomalies) {
        final deviceId =
            a['device_id'] as String? ?? a['location'] as String? ?? '';
        if (deviceId.isEmpty) continue;

        final score = (a['anomaly_score'] as num?)?.toDouble() ?? 0.0;
        final existing = anomalyMap[deviceId];
        if (existing == null ||
            score > ((existing['anomaly_score'] as num?)?.toDouble() ?? 0.0)) {
          anomalyMap[deviceId] = Map<String, dynamic>.from(a as Map);
        }
      }

      setState(() {
        _deviceAnomalies = anomalyMap;
        _anomalyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _anomalyError = e.toString();
        _anomalyLoading = false;
      });
    }
  }

  Future<void> _loadSummaryStatistics() async {
    try {
      // Single API call: fetch active faults only (no per-device energy calls on load)
      final activeFaults = await _faultService.fetchActive(limit: 100);
      if (!mounted) return;
      setState(() {
        _totalFaults = activeFaults.length;
        // Active count stays 0 until user expands devices (_recalculateActiveDevices)
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeDevices = 0;
          _totalFaults = 0;
        });
      }
    }
  }

  void _toggleDevice(String deviceId) {
    final isExpanded = _expandedDevices[deviceId] ?? false;
    setState(() {
      _expandedDevices[deviceId] = !isExpanded;
    });

    if (!isExpanded) {
      // Expanding: load readings first, then only load behavioral profile
      // (ML-heavy call) if the device actually has energy data
      _loadDeviceData(deviceId).then((_) {
        if (!mounted) return;
        final readings = _deviceReadings[deviceId] ?? [];
        if (readings.isNotEmpty) {
          _loadDeviceProfile(deviceId);
        }
      });
    }
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

  /// Format kWh for display; clamp to reasonable range to avoid absurd values.
  String _formatReasonableKwh(double value, {double maxKwh = 9999}) {
    if (value < 0) return '0 kWh';
    if (value > maxKwh) return '${maxKwh.toInt()}+ kWh';
    return '${value.toStringAsFixed(2)} kWh';
  }

  /// Format cost in LKR for display; clamp to reasonable range.
  String _formatReasonableCost(double value, {double maxLkr = 999999}) {
    if (value < 0) return '0';
    if (value > maxLkr) return '${maxLkr.toInt()}+';
    return value.toStringAsFixed(0);
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
    if (!mounted) return;
    // If model detected abnormal power, backend may have turned relay OFF
    try {
      final result = await _deviceService.checkAnomalyShutoff(deviceId);
      if (result['auto_shutoff'] == true && mounted) {
        setState(() => _relayStates[deviceId] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['reason'] as String? ??
                  'Device turned off due to abnormal power consumption.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {
      // Non-critical: ignore if endpoint fails
    }
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
      final faults =
          await _faultService.fetchDeviceFaultHistory(deviceId, limit: 50);
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
      if (lastReading != null && now.difference(lastReading).inSeconds <= 30) {
        activeCount++;
      }
    }
    setState(() {
      _activeDevices = activeCount;
    });
  }

  Future<void> _toggleRelay(String deviceId) async {
    final currentState = _relayStates[deviceId] ?? false;
    final newState = !currentState;

    // Optimistic update
    setState(() {
      _relayStates[deviceId] = newState;
      _relayLoading[deviceId] = true;
    });

    try {
      await _deviceService.updateRelayState(deviceId, newState);
      if (!mounted) return;
      setState(() {
        _relayLoading[deviceId] = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Revert on failure
      setState(() {
        _relayStates[deviceId] = currentState;
        _relayLoading[deviceId] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update relay: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildRelayControl(String deviceId) {
    final isOn = _relayStates[deviceId] ?? false;
    final isLoading = _relayLoading[deviceId] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Icon(
            Icons.power_settings_new,
            size: 20,
            color: isOn ? const Color(0xFF00C853) : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            'Power Control',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          if (isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isOn
                  ? const Color(0xFF00C853).withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isOn ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isOn ? const Color(0xFF00C853) : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: isOn,
            onChanged: isLoading ? null : (_) => _toggleRelay(deviceId),
            activeColor: const Color(0xFF00C853),
            activeTrackColor: const Color(0xFF00C853).withOpacity(0.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 2,
      color: Theme.of(context).colorScheme.primaryContainer,
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

  Widget _buildSummaryItem(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
            _loadEnergyVampires(),
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
              style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
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
        _buildEnergyForecastPanel(),
        const SizedBox(height: 16),
        _buildDeviceComparisonCard(),
        const SizedBox(height: 16),
        _buildEnergyVampiresCard(),
        const SizedBox(height: 16),
        ..._devices.map((device) => _buildDeviceCard(device)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Energy Forecast Panel
  // ---------------------------------------------------------------------------

  Widget _buildEnergyForecastPanel() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.auto_graph,
                      color: Colors.indigo.shade700, size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Next 7-Day Energy Forecast',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_forecastLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Device dropdown
            _buildForecastDeviceDropdown(),
            const SizedBox(height: 16),

            // Error state
            if (_forecastError != null && !_forecastLoading)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _forecastError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (_forecastSelectedDeviceId != null) {
                          _loadDeviceForecast(_forecastSelectedDeviceId!);
                        }
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),

            // Loading placeholder
            if (_forecastLoading && _deviceForecast == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Running LSTM forecast...',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

            // Content when loaded
            if (_deviceForecast != null) ...[
              _buildWeeklySnapshot(),
              const SizedBox(height: 16),
              _buildForecastChart(),
              const SizedBox(height: 16),
              _buildCostProjection(),
            ],

            // Empty state
            if (_forecastSelectedDeviceId == null &&
                !_forecastLoading &&
                _deviceForecast == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Select a device to see its energy forecast',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastDeviceDropdown() {
    final devicesWithModule = _devices
        .where((d) =>
            d['module_id'] != null && (d['module_id'] as String).isNotEmpty)
        .toList();

    // Deduplicate by device_id to prevent DropdownButton assertion errors
    final seen = <String>{};
    final uniqueDevices = devicesWithModule.where((d) {
      final id = d['device_id'] as String? ?? '';
      return id.isNotEmpty && seen.add(id);
    }).toList();

    // Ensure selected value exists in the items list
    final validIds =
        uniqueDevices.map((d) => d['device_id'] as String? ?? '').toSet();
    final selectedId = (_forecastSelectedDeviceId != null &&
            validIds.contains(_forecastSelectedDeviceId))
        ? _forecastSelectedDeviceId
        : null;

    return DropdownButtonFormField<String>(
      value: selectedId,
      decoration: InputDecoration(
        labelText: 'Select Device',
        prefixIcon: const Icon(Icons.devices, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      isExpanded: true,
      items: uniqueDevices.map((d) {
        final id = d['device_id'] as String? ?? '';
        final name = d['device_name'] as String? ?? id;
        final loc = d['location'] as String? ?? '';
        return DropdownMenuItem(
          value: id,
          child: Text('$name${loc.isNotEmpty ? " ($loc)" : ""}',
              overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (newId) {
        if (newId != null && newId != _forecastSelectedDeviceId) {
          setState(() => _forecastSelectedDeviceId = newId);
          _loadDeviceForecast(newId);
        }
      },
    );
  }

  Widget _buildWeeklySnapshot() {
    final forecast = _deviceForecast!;
    final weeklyKwh = (forecast['weekly_total_kwh'] as num).toDouble();
    final comparison = forecast['comparison'] as Map<String, dynamic>;
    final percentChange = (comparison['percent_change'] as num).toDouble();
    final trend = comparison['trend'] as String;
    final riskLevel = comparison['risk_level'] as String;
    final riskReason = comparison['risk_reason'] as String? ?? '';
    final deviceName = forecast['device_name'] as String? ?? '';

    Color riskColor;
    String riskLabel;
    switch (riskLevel) {
      case 'red':
        riskColor = Colors.red;
        riskLabel = 'HIGH';
        break;
      case 'orange':
        riskColor = Colors.orange;
        riskLabel = 'MEDIUM';
        break;
      default:
        riskColor = Colors.green;
        riskLabel = 'NORMAL';
    }

    IconData trendIcon;
    Color trendColor;
    switch (trend) {
      case 'rising':
        trendIcon = Icons.trending_up;
        trendColor = Colors.red;
        break;
      case 'falling':
        trendIcon = Icons.trending_down;
        trendColor = Colors.green;
        break;
      default:
        trendIcon = Icons.trending_flat;
        trendColor = Colors.blue;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Device name + risk badge row
        Row(
          children: [
            Expanded(
              child: Text(
                deviceName,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: riskColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    riskLevel == 'red'
                        ? Icons.warning_amber
                        : riskLevel == 'orange'
                            ? Icons.info_outline
                            : Icons.check_circle_outline,
                    color: riskColor,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    riskLabel,
                    style: TextStyle(
                      color: riskColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Stats row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              // Predicted kWh
              Expanded(
                child: Column(
                  children: [
                    Icon(Icons.bolt, color: Colors.indigo.shade600, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      '${weeklyKwh.toStringAsFixed(1)} kWh',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade800,
                      ),
                    ),
                    Text(
                      'Next 7 Days',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 48, color: Colors.grey.shade200),
              // Percent change
              Expanded(
                child: Column(
                  children: [
                    Icon(trendIcon, color: trendColor, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      '${percentChange >= 0 ? "+" : ""}${percentChange.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: trendColor,
                      ),
                    ),
                    Text(
                      'vs Last Week',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 48, color: Colors.grey.shade200),
              // Risk level
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        riskLevel.toUpperCase(),
                        style: TextStyle(
                          color: riskColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Risk Level',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Risk explanation
        if (riskLevel != 'green' && riskReason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: riskColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: riskColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    riskReason,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildForecastChart() {
    final forecast = _deviceForecast!;
    final dailyHistorical =
        forecast['daily_historical'] as List<dynamic>? ?? [];
    final dailyForecast = forecast['daily_forecast'] as List<dynamic>? ?? [];

    if (dailyHistorical.isEmpty && dailyForecast.isEmpty) {
      return const SizedBox.shrink();
    }

    // Build historical spots
    final historicalSpots = <FlSpot>[];
    for (int i = 0; i < dailyHistorical.length; i++) {
      final day = dailyHistorical[i] as Map<String, dynamic>;
      historicalSpots
          .add(FlSpot(i.toDouble(), (day['actual_kwh'] as num).toDouble()));
    }

    // Build forecast spots with bridge point
    final forecastSpots = <FlSpot>[];
    if (historicalSpots.isNotEmpty) {
      forecastSpots.add(FlSpot(
        (dailyHistorical.length - 1).toDouble(),
        historicalSpots.last.y,
      ));
    }
    for (int i = 0; i < dailyForecast.length; i++) {
      final day = dailyForecast[i] as Map<String, dynamic>;
      final kwh = (day['predicted_kwh'] as num).toDouble();
      forecastSpots.add(FlSpot((dailyHistorical.length + i).toDouble(), kwh));
    }

    // Confidence band spots (for shading)
    final confLowSpots = <FlSpot>[];
    final confHighSpots = <FlSpot>[];
    for (int i = 0; i < dailyForecast.length; i++) {
      final day = dailyForecast[i] as Map<String, dynamic>;
      final low = (day['confidence_low_kwh'] as num).toDouble();
      final high = (day['confidence_high_kwh'] as num).toDouble();
      final x = (dailyHistorical.length + i).toDouble();
      confLowSpots.add(FlSpot(x, low));
      confHighSpots.add(FlSpot(x, high));
    }

    final allValues = [
      ...historicalSpots.map((s) => s.y),
      ...forecastSpots.map((s) => s.y),
      ...confHighSpots.map((s) => s.y),
    ];
    final rawMax = allValues.isEmpty
        ? 0.0
        : allValues.reduce((a, b) => a > b ? a : b);
    final maxY = (rawMax * 1.2).clamp(1.0, double.infinity);

    // No meaningful energy data — all values are zero
    if (rawMax == 0.0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.show_chart, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                'No energy data available for forecast',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6)),
              ),
            ],
          ),
        ),
      );
    }

    final totalDays = dailyHistorical.length + dailyForecast.length;

    // Build day labels
    final dayLabels = <String>[];
    for (final d in dailyHistorical) {
      final day = d as Map<String, dynamic>;
      final dayName = (day['day'] as String?) ?? '';
      dayLabels.add(dayName.length >= 3 ? dayName.substring(0, 3) : dayName);
    }
    for (final d in dailyForecast) {
      final day = d as Map<String, dynamic>;
      final dayName = (day['day'] as String?) ?? '';
      dayLabels.add(dayName.length >= 3 ? dayName.substring(0, 3) : dayName);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '7-Day Forecast Chart',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 2, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text('Actual',
                      style:
                          TextStyle(fontSize: 9, color: Colors.blue.shade700)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDottedLine(),
                  const SizedBox(width: 4),
                  Text('Predicted',
                      style: TextStyle(
                          fontSize: 9, color: Colors.indigo.shade700)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 210,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (totalDays - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: maxY / 4,
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.grey.shade200,
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (value) {
                  // Vertical divider between historical and forecast
                  if (value.toInt() == dailyHistorical.length - 1) {
                    return FlLine(
                      color: Colors.grey.shade400,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    );
                  }
                  return FlLine(color: Colors.grey.shade100, strokeWidth: 0.5);
                },
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= dayLabels.length) {
                        return const SizedBox.shrink();
                      }
                      final isForecast = idx >= dailyHistorical.length;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          dayLabels[idx],
                          style: TextStyle(
                            fontSize: 9,
                            color: isForecast
                                ? Colors.indigo.shade600
                                : Colors.grey.shade600,
                            fontWeight: isForecast
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: maxY / 4,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toStringAsFixed(1),
                        style:
                            TextStyle(fontSize: 9, color: Colors.grey.shade500),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: Colors.grey.shade800,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final dayIndex = spot.x.toInt();
                      if (dayIndex >= dailyHistorical.length) {
                        final fIdx = dayIndex - dailyHistorical.length;
                        if (fIdx >= 0 && fIdx < dailyForecast.length) {
                          final day =
                              dailyForecast[fIdx] as Map<String, dynamic>;
                          final peakHour = day['peak_hour'] ?? 0;
                          final confLow =
                              (day['confidence_low_kwh'] as num).toDouble();
                          final confHigh =
                              (day['confidence_high_kwh'] as num).toDouble();
                          return LineTooltipItem(
                            '${spot.y.toStringAsFixed(1)} kWh\n'
                            'Peak: ${peakHour.toString().padLeft(2, "0")}:00\n'
                            'Range: ${confLow.toStringAsFixed(1)}-${confHigh.toStringAsFixed(1)}',
                            const TextStyle(color: Colors.white, fontSize: 11),
                          );
                        }
                      }
                      return LineTooltipItem(
                        '${spot.y.toStringAsFixed(1)} kWh (actual)',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                // Confidence band - high
                if (confHighSpots.isNotEmpty)
                  LineChartBarData(
                    spots: confHighSpots,
                    isCurved: true,
                    color: Colors.transparent,
                    barWidth: 0,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.indigo.withValues(alpha: 0.06),
                    ),
                  ),
                // Historical line (solid blue)
                if (historicalSpots.isNotEmpty)
                  LineChartBarData(
                    spots: historicalSpots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: Colors.blue,
                        strokeWidth: 1.5,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withValues(alpha: 0.08),
                    ),
                  ),
                // Forecast line (dotted indigo)
                if (forecastSpots.isNotEmpty)
                  LineChartBarData(
                    spots: forecastSpots,
                    isCurved: true,
                    color: Colors.indigo,
                    barWidth: 2.5,
                    dashArray: [8, 4],
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: Colors.indigo,
                        strokeWidth: 1.5,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.indigo.withValues(alpha: 0.08),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDottedLine() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
          3,
          (i) => Container(
                width: 3,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                color: Colors.indigo,
              )),
    );
  }

  Widget _buildCostProjection() {
    final cost = _deviceForecast!['cost'] as Map<String, dynamic>;
    final weeklyLkr = (cost['weekly_cost_lkr'] as num).toDouble();
    final monthlyLkr = (cost['monthly_projection_lkr'] as num).toDouble();
    final lastWeekLkr = (cost['last_week_cost_lkr'] as num).toDouble();
    // Determine monthly change message
    final monthlyChange = lastWeekLkr > 0
        ? ((weeklyLkr - lastWeekLkr) / lastWeekLkr * 100)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.paid, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Cost Projection (LECO Tariff)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Based on LECO domestic block tariff (revised June 2025)',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCostItem(
                  'Weekly Estimate',
                  'Rs. ${weeklyLkr.toStringAsFixed(0)}',
                  Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCostItem(
                  'Monthly Bill',
                  'Rs. ${monthlyLkr.toStringAsFixed(0)}',
                  Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCostItem(
                  'Last Week',
                  'Rs. ${lastWeekLkr.toStringAsFixed(0)}',
                  Colors.grey.shade600,
                ),
              ),
            ],
          ),
          if (monthlyChange.abs() > 1) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: monthlyChange > 0
                    ? Theme.of(context).colorScheme.tertiaryContainer
                    : Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    monthlyChange > 0 ? Icons.trending_up : Icons.trending_down,
                    color: monthlyChange > 0
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      monthlyChange > 0
                          ? 'If current trend continues, monthly bill may increase by ${monthlyChange.toStringAsFixed(0)}%.'
                          : 'Projected monthly bill may decrease by ${monthlyChange.abs().toStringAsFixed(0)}%.',
                      style: TextStyle(
                        fontSize: 11,
                        color: monthlyChange > 0
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCostItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Device Comparison / Ranking Card
  // ---------------------------------------------------------------------------

  Widget _buildDeviceComparisonCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.leaderboard,
                      color: Colors.teal.shade700, size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Forecast Ranking',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_comparisonLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (!_comparisonLoading)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadDeviceComparison,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Refresh rankings',
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Devices ranked by predicted weekly consumption',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),

            // Error
            if (_comparisonError != null && !_comparisonLoading)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _comparisonError!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),

            // Loading
            if (_comparisonLoading && _deviceComparison == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),

            // Content
            if (_deviceComparison != null && !_comparisonLoading) ...[
              // Total summary (clamp to reasonable display range)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          _formatReasonableKwh((_deviceComparison!['total_predicted_kwh'] as num).toDouble(), maxKwh: 9999),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        Text(
                          'Weekly kWh',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    Container(
                        width: 1, height: 30, color: Colors.teal.shade200),
                    Column(
                      children: [
                        Text(
                          'Rs. ${_formatReasonableCost((_deviceComparison!['total_weekly_cost_lkr'] as num).toDouble(), maxLkr: 999999)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        Text(
                          'Weekly Cost',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    Container(
                        width: 1, height: 30, color: Colors.teal.shade200),
                    Column(
                      children: [
                        Text(
                          'Rs. ${_formatReasonableCost((_deviceComparison!['total_monthly_bill_lkr'] as num?)?.toDouble() ?? 0, maxLkr: 999999)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        Text(
                          'Monthly Bill',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    Container(
                        width: 1, height: 30, color: Colors.teal.shade200),
                    Column(
                      children: [
                        Text(
                          '${_deviceComparison!['device_count']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.teal.shade800,
                          ),
                        ),
                        Text(
                          'Devices',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Ranked device list
              ...(_deviceComparison!['devices'] as List<dynamic>)
                  .asMap()
                  .entries
                  .map((entry) {
                final rank = entry.key + 1;
                final device = entry.value as Map<String, dynamic>;
                final name = device['device_name'] as String? ??
                    device['device_id'] as String;
                // Clamp to reasonable range for display (per-device)
                final kwh = ((device['predicted_weekly_kwh'] as num).toDouble()).clamp(0.0, 500.0);
                final costLkr = ((device['weekly_cost_lkr'] as num).toDouble()).clamp(0.0, 50000.0);
                final risk = device['risk_level'] as String? ?? 'green';
                final pct = (device['percent_change'] as num?)?.toDouble() ?? 0;
                final trendStr = device['trend'] as String? ?? 'stable';

                Color riskColor;
                switch (risk) {
                  case 'red':
                    riskColor = Colors.red;
                    break;
                  case 'orange':
                    riskColor = Colors.orange;
                    break;
                  default:
                    riskColor = Colors.green;
                }

                IconData trendIcon;
                switch (trendStr) {
                  case 'rising':
                    trendIcon = Icons.trending_up;
                    break;
                  case 'falling':
                    trendIcon = Icons.trending_down;
                    break;
                  default:
                    trendIcon = Icons.trending_flat;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: riskColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      // Rank badge
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: rank <= 3
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHigh,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '#$rank',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: rank <= 3
                                  ? Colors.teal.shade700
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Device info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${kwh.toStringAsFixed(1)} kWh  |  Rs. ${costLkr.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Trend
                      Icon(trendIcon, size: 16, color: riskColor),
                      const SizedBox(width: 4),
                      Text(
                        '${pct >= 0 ? "+" : ""}${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: riskColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Risk badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: riskColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          risk.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: riskColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            // Empty state
            if (_deviceComparison == null &&
                !_comparisonLoading &&
                _comparisonError == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Loading device comparison...',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyVampiresCard() {
    return Card(
      elevation: 2,
      color: _energyVampires.isNotEmpty
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _energyVampires.isNotEmpty
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  color: _energyVampires.isNotEmpty
                      ? Colors.red[700]
                      : Colors.green[700],
                ),
                const SizedBox(width: 8),
                const Text(
                  'Energy Vampires',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_vampiresLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadEnergyVampires,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Devices drawing power when rooms are vacant',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (_vampiresError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _vampiresError!,
                  style: TextStyle(fontSize: 12, color: Colors.red[700]),
                ),
              ),
            if (!_vampiresLoading && _vampiresError == null) ...[
              const SizedBox(height: 12),
              if (_energyVampires.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.eco, color: Colors.green[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No energy vampires detected. All devices are efficient!',
                          style:
                              TextStyle(fontSize: 13, color: Colors.green[800]),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // Summary row
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${_energyVampires.length}',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                              ),
                            ),
                            Text('Vampires',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[700])),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.grey[300]),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${_totalEnergyWaste.toStringAsFixed(2)} kWh',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                              ),
                            ),
                            Text('Energy wasted (7d)',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[700])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Individual vampire entries
                ..._energyVampires.map((v) {
                  final name = v['device_name'] as String? ??
                      v['device_id'] as String? ??
                      '';
                  final idlePower =
                      (v['avg_power_vacant'] as num?)?.toDouble() ?? 0;
                  final ratio = (v['standby_ratio'] as num?)?.toDouble() ?? 0;
                  final severity = v['vampire_severity'] as String? ?? 'Medium';
                  final waste =
                      (v['energy_waste_kwh'] as num?)?.toDouble() ?? 0;
                  final sevColor =
                      severity == 'High' ? Colors.red : Colors.orange;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sevColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.power_off, color: sevColor, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(
                                'Idle: ${idlePower.toStringAsFixed(1)}W  |  '
                                'Standby: ${(ratio * 100).toStringAsFixed(0)}%  |  '
                                'Waste: ${waste.toStringAsFixed(2)} kWh',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: sevColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            severity,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: sevColor),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBehavioralProfileSection(String deviceId) {
    final profile = _deviceProfiles[deviceId];
    if (profile == null) return const SizedBox.shrink();

    final avgOccupied =
        (profile['avg_power_occupied'] as num?)?.toDouble() ?? 0;
    final avgVacant = (profile['avg_power_vacant'] as num?)?.toDouble() ?? 0;
    final standbyRatio = (profile['standby_ratio'] as num?)?.toDouble() ?? 0;
    final wasteKwh = (profile['energy_waste_kwh'] as num?)?.toDouble() ?? 0;
    final isVampire = profile['is_energy_vampire'] as bool? ?? false;
    final severity = profile['vampire_severity'] as String?;
    final totalReadings = profile['total_readings'] as int? ?? 0;
    final vacantReadings = profile['vacant_readings'] as int? ?? 0;
    final hourlyProfile = profile['hourly_profile'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Icon(Icons.psychology, color: Colors.deepPurple[400], size: 20),
            const SizedBox(width: 8),
            const Text(
              'Behavioral Profile',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            if (isVampire) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(
                  'Energy Vampire ($severity)',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Occupied vs Vacant comparison
        Row(
          children: [
            Expanded(
              child: _buildProfileStat(
                'Occupied Power',
                '${avgOccupied.toStringAsFixed(1)} W',
                Icons.person,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildProfileStat(
                'Vacant Power',
                '${avgVacant.toStringAsFixed(1)} W',
                Icons.person_off,
                avgVacant > 5 ? Colors.red : Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildProfileStat(
                'Standby Ratio',
                '${(standbyRatio * 100).toStringAsFixed(1)}%',
                Icons.battery_alert,
                standbyRatio > 0.3
                    ? Colors.red
                    : (standbyRatio > 0.1 ? Colors.orange : Colors.green),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildProfileStat(
                'Energy Wasted (7d)',
                '${wasteKwh.toStringAsFixed(2)} kWh',
                Icons.money_off,
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Readings summary
        Text(
          '$totalReadings readings analyzed  |  $vacantReadings during vacant periods',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),

        // Hourly profile chart
        if (hourlyProfile.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Hourly Power Profile (24h)',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          _buildHourlyChart(hourlyProfile),
        ],
      ],
    );
  }

  Widget _buildProfileStat(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: color)),
                Text(label,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyChart(List<dynamic> hourlyProfile) {
    final maxPower = hourlyProfile.fold<double>(0, (max, h) {
      final pw = (h['avg_power_w'] as num?)?.toDouble() ?? 0;
      return pw > max ? pw : max;
    });

    final spots = hourlyProfile.map((h) {
      final hour = (h['hour'] as num?)?.toDouble() ?? 0;
      final pw = (h['avg_power_w'] as num?)?.toDouble() ?? 0;
      return FlSpot(hour, pw);
    }).toList();

    if (spots.isEmpty || maxPower == 0) return const SizedBox.shrink();

    return Container(
      height: 120,
      padding: const EdgeInsets.only(right: 8, top: 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxPower / 3,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey[200]!,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}W',
                  style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 6,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}h',
                  style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: 23,
          minY: 0,
          maxY: maxPower * 1.1,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.deepPurple,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.deepPurple.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
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
    final hasReadings = readings.isNotEmpty;
    final latestReading = hasReadings ? readings.first : null;

    // Check if device is active (energy reading in last 30 seconds)
    final lastReadingTime = _deviceLastReadings[deviceId];
    final isActive = lastReadingTime != null &&
        DateTime.now().difference(lastReadingTime).inSeconds <= 30;

    // Determine anomaly status from ML detection results
    final anomalyData = _deviceAnomalies[deviceId];
    final bool isAnomaly;
    final double anomalyScore;
    final String severity;
    final String statusText;
    Color statusColor;
    IconData statusIcon;

    if (_anomalyLoading) {
      // Still loading anomaly data
      isAnomaly = false;
      anomalyScore = 0.0;
      severity = '';
      statusText = 'Analyzing...';
      statusColor = Colors.grey;
      statusIcon = Icons.hourglass_top;
    } else if (_anomalyError == 'model_training') {
      // Model is still training
      isAnomaly = false;
      anomalyScore = 0.0;
      severity = '';
      statusText = 'Model training...';
      statusColor = Colors.blueGrey;
      statusIcon = Icons.model_training;
    } else if (_anomalyError != null && anomalyData == null) {
      // Anomaly API error — fall back to reading-based status
      isAnomaly = false;
      anomalyScore = 0.0;
      severity = '';
      if (isActive) {
        statusText = 'Operating Normally';
        statusColor = const Color(0xFF2E7D32);
        statusIcon = Icons.check_circle_outline;
      } else if (lastReadingTime != null) {
        statusText = 'Idle';
        statusColor = Colors.blueGrey;
        statusIcon = Icons.pause_circle_outline;
      } else {
        statusText = 'No Data';
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
      }
    } else if (anomalyData != null) {
      // Anomaly detected for this device
      isAnomaly = true;
      anomalyScore = (anomalyData['anomaly_score'] as num?)?.toDouble() ?? 0.0;
      severity = anomalyData['severity'] as String? ?? 'Medium';
      if (severity == 'High') {
        statusText = 'Anomaly Detected';
        statusColor = const Color(0xFFD32F2F);
        statusIcon = Icons.warning_amber_rounded;
      } else {
        statusText = 'Anomaly Detected';
        statusColor = const Color(0xFFEF6C00);
        statusIcon = Icons.warning_amber_rounded;
      }
    } else {
      // No anomaly detected — operating normally
      isAnomaly = false;
      anomalyScore = 0.0;
      severity = '';
      statusText = 'Operating Normally';
      statusColor = const Color(0xFF2E7D32);
      statusIcon = Icons.check_circle_outline;
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
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle,
                                        size: 6, color: Colors.green),
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
                        if (hasReadings) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.insights,
                                  size: 12, color: Colors.blue[300]),
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
                  // Anomaly status indicator (replaces hardcoded percentage)
                  _buildAnomalyIndicator(
                    isAnomaly: isAnomaly,
                    anomalyScore: anomalyScore,
                    severity: severity,
                    statusColor: statusColor,
                    isLoading: _anomalyLoading,
                    hasError: _anomalyError != null && anomalyData == null,
                  ),
                  // Label button for research ground-truth collection
                  if (isAnomaly && anomalyData != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _showAnomalyLabelSheet(
                        context,
                        anomalyData['detected_at']?.toString() ?? deviceId,
                      ),
                      child: Tooltip(
                        message: 'Label this anomaly',
                        child: Icon(Icons.label_outline, size: 16, color: Colors.grey[500]),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
                ],
              ),
            ),
            _buildRelayControl(deviceId),
            if (isExpanded)
              _buildExpandedContent(deviceId, device, readings, faults),
          ],
        ),
      ),
    );
  }

  Widget _buildAnomalyIndicator({
    required bool isAnomaly,
    required double anomalyScore,
    required String severity,
    required Color statusColor,
    required bool isLoading,
    required bool hasError,
  }) {
    if (isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
        ),
      );
    }

    if (hasError) {
      return Icon(Icons.help_outline, color: Colors.grey[400], size: 28);
    }

    if (isAnomaly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  severity,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Score: ${anomalyScore.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
            ),
          ),
        ],
      );
    }

    // Normal — green check
    return Icon(
      Icons.check_circle,
      color: statusColor,
      size: 28,
    );
  }

  void _showAnomalyLabelSheet(BuildContext ctx, String anomalyKey) {
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.label, size: 18, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Label this anomaly', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              Text(
                'Your label helps improve anomaly detection precision.',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6)),
              ),
              const SizedBox(height: 16),
              _labelOption(ctx, sheetCtx, anomalyKey, 'true_positive', 'Real Anomaly', Icons.check_circle, Colors.red),
              const SizedBox(height: 8),
              _labelOption(ctx, sheetCtx, anomalyKey, 'false_positive', 'False Alarm', Icons.cancel, Colors.green),
              const SizedBox(height: 8),
              _labelOption(ctx, sheetCtx, anomalyKey, 'unsure', 'Not Sure', Icons.help_outline, Colors.grey),
            ],
          ),
        );
      },
    );
  }

  Widget _labelOption(BuildContext ctx, BuildContext sheetCtx, String anomalyKey,
      String label, String display, IconData icon, Color color) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(display),
      onTap: () async {
        Navigator.pop(sheetCtx);
        final success = await _evalService.labelAnomaly(anomalyKey, label);
        if (!mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(success ? 'Labeled as "$display"' : 'Failed to save label'),
          duration: const Duration(seconds: 2),
        ));
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: color.withOpacity(0.06),
    );
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
                        ButtonSegment(
                            value: TimeRange.hours6, label: Text('6h')),
                        ButtonSegment(
                            value: TimeRange.hours24, label: Text('24h')),
                        ButtonSegment(
                            value: TimeRange.days7, label: Text('7d')),
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
                      Icon(Icons.access_time,
                          size: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6)),
                      const SizedBox(width: 4),
                      Text(
                        'Last refreshed: ${_formatTime(lastUpdated)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
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
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _loadDeviceReadings(deviceId),
                        child:
                            const Text('Retry', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),

              // Fault Detection Section
              if (activeFaults.isNotEmpty)
                _buildFaultSection(deviceId, activeFaults, faults),

              // 24h Insights
              if (readings.isEmpty && !isLoading && error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.data_usage,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No data in last ${_getHoursForRange(timeRange)}h',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6)),
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

              // Behavioral Profile Section
              _buildBehavioralProfileSection(deviceId),

              // Fault History Link
              if (faults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => _showFaultHistory(
                        deviceId, device['device_name'] as String? ?? deviceId),
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

  Widget _buildFaultSection(
      String deviceId, List<dynamic> activeFaults, List<dynamic> allFaults) {
    final criticalCount =
        activeFaults.where((f) => f['severity'] == 'Critical').length;
    final highCount = activeFaults.where((f) => f['severity'] == 'High').length;
    final mediumCount =
        activeFaults.where((f) => f['severity'] == 'Medium').length;
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
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Theme.of(context).colorScheme.error.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  size: 20),
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
              if (lowCount > 0) _buildFaultBadge('Low: $lowCount', Colors.blue),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Suggested: Check device connections and review fault history for details.',
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
                fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 14, color: Colors.grey[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Auto shutoff: If abnormal power is detected by the model, the device may be turned off automatically to protect the circuit. This only happens when the model flags a real issue.',
                    style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
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
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildInsightsSection(
      List<EnergyReading> readings, TimeRange timeRange) {
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
    final expectedReadings =
        _getHoursForRange(timeRange) * 3600; // Assuming 1 reading per second
    final coverage =
        (readings.length / expectedReadings * 100).clamp(0.0, 100.0);

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

        // Sparkline (Device Insight chart with time and current axes)
        _buildSparkline(readings, timeRange),
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
                    _buildPowerStat('Max',
                        '${maxPowerKw.toStringAsFixed(3)} kW', Colors.red),
                    _buildPowerStat('Avg',
                        '${avgPowerKw.toStringAsFixed(3)} kW', Colors.blue),
                    _buildPowerStat(
                        'Total Usage',
                        '${totalUsageKwh.toStringAsFixed(3)} kWh',
                        Colors.orange),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Calculated at ${standardVoltage}V standard voltage',
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                        fontStyle: FontStyle.italic),
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
            _buildStatCard('Min Current', '${minCurrent.toStringAsFixed(3)} A',
                Icons.trending_down),
            _buildStatCard('Max Current', '${maxCurrent.toStringAsFixed(3)} A',
                Icons.trending_up),
            _buildStatCard('Avg Current', '${avgCurrent.toStringAsFixed(3)} A',
                Icons.show_chart),
            _buildStatCard('Samples', '${readings.length}', Icons.data_usage),
            _buildStatCard('Coverage', '${coverage.toStringAsFixed(1)}%',
                Icons.signal_cellular_alt),
            _buildStatCard(
                'Latest',
                _formatSriLankaTime(latestReading.receivedAt),
                Icons.access_time),
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
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500),
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

  Widget _buildSparkline(List<EnergyReading> readings, TimeRange timeRange) {
    if (readings.isEmpty) return const SizedBox.shrink();

    final bool is7Days = timeRange == TimeRange.days7;
    final List<FlSpot> spots;
    final double minX;
    final double maxX;
    final double verticalInterval;
    final String Function(int) bottomLabel;

    if (is7Days) {
      // Aggregate by day index (0..6): X = day, Y = average current (A)
      final sorted = List<EnergyReading>.from(readings)
        ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      final startDate = sorted.first.receivedAt.toLocal();
      final startDay = DateTime(startDate.year, startDate.month, startDate.day);

      final daySums = <int, double>{};
      final dayCounts = <int, int>{};
      for (int d = 0; d < 7; d++) {
        daySums[d] = 0.0;
        dayCounts[d] = 0;
      }
      for (final r in sorted) {
        final local = r.receivedAt.toLocal();
        final readingDay = DateTime(local.year, local.month, local.day);
        final dayIndex = readingDay.difference(startDay).inDays.clamp(0, 6);
        daySums[dayIndex] = (daySums[dayIndex] ?? 0) + r.currentA;
        dayCounts[dayIndex] = (dayCounts[dayIndex] ?? 0) + 1;
      }
      spots = [];
      for (int d = 0; d < 7; d++) {
        final count = dayCounts[d] ?? 0;
        final avg = count > 0 ? (daySums[d]! / count) : 0.0;
        spots.add(FlSpot(d.toDouble(), avg));
      }
      minX = 0;
      maxX = 6;
      verticalInterval = 1;
      bottomLabel = (v) => 'Day ${v + 1}';
    } else {
      // Aggregate by hour of day (0-23): X = time of day, Y = average current (A)
      final hourSums = <int, double>{};
      final hourCounts = <int, int>{};
      for (int h = 0; h < 24; h++) {
        hourSums[h] = 0.0;
        hourCounts[h] = 0;
      }
      for (final r in readings) {
        final local = r.receivedAt.toLocal();
        final hour = local.hour;
        hourSums[hour] = (hourSums[hour] ?? 0) + r.currentA;
        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
      }
      spots = [];
      for (int h = 0; h < 24; h++) {
        final count = hourCounts[h] ?? 0;
        final avg = count > 0 ? (hourSums[h]! / count) : 0.0;
        spots.add(FlSpot(h.toDouble(), avg));
      }
      minX = 0;
      maxX = 24;
      verticalInterval = 6;
      bottomLabel = (v) => v == 24 ? '24:00' : '${v.toString().padLeft(2, '0')}:00';
    }

    final maxCurrent = spots.isEmpty
        ? 1.0
        : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final chartMaxY = maxCurrent > 0 ? maxCurrent * 1.2 : 1.0;

    return Container(
      height: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: 0,
          maxY: chartMaxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            verticalInterval: verticalInterval,
            horizontalInterval: chartMaxY > 0 ? chartMaxY / 4 : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: chartMaxY > 0 ? chartMaxY / 4 : 1,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toStringAsFixed(2)} A',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: verticalInterval,
                getTitlesWidget: (value, meta) {
                  final v = value.round().clamp(0, is7Days ? 6 : 24);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      bottomLabel(v),
                      style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Theme.of(context).colorScheme.primary,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              ),
            ),
          ],
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
                border: Border(
                    bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant)),
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
                    style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6)),
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
                          Icon(Icons.check_circle_outline,
                              size: 64, color: Colors.green[300]),
                          const SizedBox(height: 16),
                          Text(
                            'No faults recorded',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6)),
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
                                status == 'active'
                                    ? Icons.warning
                                    : Icons.check_circle,
                                color: severityColor,
                                size: 24,
                              ),
                            ),
                            title: Text(
                              fault['issue'] as String? ?? 'Unknown issue',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                    'Severity: $severity • Status: ${status.toUpperCase()}'),
                                Text(
                                    'Detected: ${_formatTime(detectedAt.toLocal())}'),
                                if (fault['description'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      fault['description'] as String,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.6)),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
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

  /// receivedAt from backend is UTC (DateTime.utcnow()). Sri Lanka = UTC+5:30.
  /// Compute Sri Lanka date/time by adding 5h 30m to UTC components.
  String _formatSriLankaTime(DateTime dateTime) {
    final utc = dateTime.toUtc();
    // Add 5 hours 30 minutes; DateTime handles day/month rollover
    final sl = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour + 5,
      utc.minute + 30,
      utc.second,
      utc.millisecond,
    );
    final day = sl.day.toString().padLeft(2, '0');
    final month = sl.month.toString().padLeft(2, '0');
    final hour = sl.hour.toString().padLeft(2, '0');
    final minute = sl.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
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
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
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
                            'rated_power_watts':
                                int.parse(ratedPowerController.text.trim()),
                          };

                          if (moduleIdController.text.trim().isNotEmpty) {
                            deviceData['module_id'] =
                                moduleIdController.text.trim();
                          }

                          if (installedDateController.text.trim().isNotEmpty) {
                            deviceData['installed_date'] =
                                installedDateController.text.trim();
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
