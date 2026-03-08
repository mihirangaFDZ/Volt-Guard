import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/energy_reading.dart';
import '../models/sensor_reading.dart';
import '../services/analytics_service.dart';
import '../services/energy_service.dart';

/// Component-focused analytics page for occupancy, comfort, sensor health, and recommendations
/// using the provided IoT fields (pir/rcwl, temperature, humidity, rssi, uptime, timestamps).
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final AnalyticsService _analyticsService = AnalyticsService();

  static const int _maxActiveRecs = 3;
  List<SensorReading> _readings = [];
  List<EnergyReading> _energyReadings = [];
  Map<String, dynamic>? _energyUsage;
  bool _loading = true;
  String? _error;
  List<_RecItem> _activeRecItems = [];
  List<_Recommendation> _backlogRecs = [];
  List<_CompletedEntry> _history = [];

  // Filter state
  String? _selectedLocation;
  String? _selectedModule;
  String? _selectedDeviceId;
  List<String> _availableLocations = [];
  List<String> _availableModules = [];
  List<Map<String, dynamic>> _availableDevices = [];
  bool _filtersLoading = false;

  // Page tab state
  _AnalyticsTab _selectedTab = _AnalyticsTab.environment;

  // Occupancy stats
  Map<String, dynamic>? _occupancyStats;

  // Auto-refresh timer for live updates
  Timer? _autoRefreshTimer;
  static const Duration _autoRefreshInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadReadings();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (timer) {
      if (mounted) {
        _loadReadings();
      }
    });
  }

  Future<void> _reloadAllData() async {
    await _loadReadings();
  }

  Future<void> _loadFilters() async {
    try {
      final filters = await _analyticsService.fetchAvailableFilters();
      final devices = await _analyticsService.fetchDevices();
      if (!mounted) return;
      setState(() {
        _availableLocations = filters['locations'] ?? [];
        _availableModules = filters['modules'] ?? [];
        _availableDevices = devices;
      });
    } catch (e) {
      if (!mounted) return;
      // Don't show error for filters, just continue without them
    }
  }

  Future<void> _loadReadings() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final dataFuture = _analyticsService.fetchLatestReadings(
        limit: 50,
        location: _selectedLocation,
        module: _selectedModule,
        deviceId: _selectedDeviceId,
      );
      final occupancyFuture = _analyticsService.fetchOccupancyStats(
        limit: 50,
        location: _selectedLocation,
        module: _selectedModule,
        deviceId: _selectedDeviceId,
      );

      // Use new analytics endpoint for current energy data
      final energyStatsFuture = _analyticsService.fetchCurrentEnergyStats(
        limit: 120,
        location: _selectedLocation,
        module: _selectedModule,
        deviceId: _selectedDeviceId,
      );

      final data = await dataFuture;

      Map<String, dynamic>? occupancyStats;
      try {
        occupancyStats = await occupancyFuture;
      } catch (_) {
        // Occupancy stats are optional and should not block the view.
      }

      Map<String, dynamic>? energyStats;
      List<EnergyReading> energyReadings = [];
      try {
        energyStats = await energyStatsFuture;
        // Extract readings from the latest data if available
        if (energyStats != null && energyStats['latest'] != null) {
          energyReadings = [
            EnergyReading.fromJson(
                Map<String, dynamic>.from(energyStats['latest'] as Map))
          ];
        }
      } catch (_) {
        // Current energy data is optional for the environment tab.
      }

      _DerivedStats? stats;
      if (data.isNotEmpty) {
        stats = _deriveStats(data);
      }

      if (!mounted) return;
      setState(() {
        _readings = data;
        _energyReadings = energyReadings;
        _energyUsage = energyStats; // Store the full stats object
        _occupancyStats = occupancyStats;

        if (stats != null) {
          final recs = _buildRecList(stats);
          _activeRecItems =
              recs.take(_maxActiveRecs).map((r) => _RecItem(rec: r)).toList();
          _backlogRecs = recs.skip(_maxActiveRecs).toList();
          _history = [];
        } else {
          _activeRecItems = [];
          _backlogRecs = [];
          _history = [];
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load analytics data: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics & Recommendations'),
      ),
      body: RefreshIndicator(
        onRefresh: _reloadAllData,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final bool hasActiveFilters = _selectedLocation != null ||
        _selectedModule != null ||
        _selectedDeviceId != null;

    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _errorCard(_error!),
        ],
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilters(),
          const SizedBox(height: 16),
          _buildAnalyticsTabs(),
          const SizedBox(height: 16),
          if (_selectedTab == _AnalyticsTab.environment)
            ..._buildEnvironmentAnalytics(hasActiveFilters)
          else
            ..._buildCurrentEnergyAnalytics(hasActiveFilters),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTabs() {
    return SegmentedButton<_AnalyticsTab>(
      segments: const [
        ButtonSegment<_AnalyticsTab>(
          value: _AnalyticsTab.environment,
          icon: Icon(Icons.analytics_outlined),
          label: Text('Environment'),
        ),
        ButtonSegment<_AnalyticsTab>(
          value: _AnalyticsTab.currentEnergy,
          icon: Icon(Icons.electric_bolt),
          label: Text('Current Energy'),
        ),
      ],
      selected: <_AnalyticsTab>{_selectedTab},
      showSelectedIcon: false,
      onSelectionChanged: (selected) {
        if (selected.isEmpty) return;
        setState(() {
          _selectedTab = selected.first;
        });
      },
    );
  }

  List<Widget> _buildEnvironmentAnalytics(bool hasActiveFilters) {
    if (_readings.isEmpty) {
      return [
        _emptyState(hasActiveFilters: hasActiveFilters),
      ];
    }

    final SensorReading latest = _latestReading(_readings);
    final _DerivedStats stats = _deriveStats(_readings);

    return [
      _buildHeader(latest, stats),
      const SizedBox(height: 16),
      if (_occupancyStats != null) ...[
        _buildOccupancyStats(),
        const SizedBox(height: 16),
      ],
      _buildComfortCard(stats),
      const SizedBox(height: 16),
      _buildSensorHealth(latest, stats),
      const SizedBox(height: 16),
      _buildRecommendations(),
      const SizedBox(height: 16),
      _buildRecentReadings(_readings),
    ];
  }

  List<Widget> _buildCurrentEnergyAnalytics(bool hasActiveFilters) {
    if (_energyReadings.isEmpty) {
      return [
        _currentEnergyEmptyState(hasActiveFilters: hasActiveFilters),
      ];
    }

    final _CurrentEnergyStats stats = _deriveCurrentEnergyStats(
      _energyReadings,
      usageResponse: _energyUsage,
      selectedLocation: _selectedLocation,
    );

    return [
      _buildCurrentEnergyHeader(stats),
      const SizedBox(height: 16),
      _buildCurrentEnergyMetrics(stats),
      const SizedBox(height: 16),
      _buildCurrentEnergyReadings(_energyReadings),
    ];
  }

  SensorReading _latestReading(List<SensorReading> readings) {
    return readings
        .reduce((a, b) => a.receivedAt.isAfter(b.receivedAt) ? a : b);
  }

  Widget _errorCard(String message) {
    return Card(
      color: Colors.red.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Unable to load analytics',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(message,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadReadings,
              tooltip: 'Retry',
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required bool hasActiveFilters}) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors_off, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasActiveFilters
                        ? 'No analytics data found for the selected location/module.'
                        : 'No sensor readings yet. Pull to refresh or wait for devices to send data.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedLocation = null;
                      _selectedModule = null;
                      _selectedDeviceId = null;
                    });
                    _loadReadings();
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Analytics'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _currentEnergyEmptyState({required bool hasActiveFilters}) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_outlined, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasActiveFilters
                        ? 'No current-energy readings found for the selected location/module.'
                        : 'No current-energy readings yet. Wait for ESP32 energy data and refresh.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedLocation = null;
                      _selectedModule = null;
                      _selectedDeviceId = null;
                    });
                    _loadReadings();
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Analytics'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentEnergyHeader(_CurrentEnergyStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.electric_bolt, color: stats.trendColor),
                const SizedBox(width: 8),
                const Text(
                  'Current Energy Analysis',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (stats.latest != null)
                  Text(
                    'Last seen: ${_friendlyTime(stats.latest!.receivedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (stats.latest != null) ...[
                  _pill('${stats.latest!.location} • ${stats.latest!.module}'),
                  _pill('Sensor: ${stats.latest!.sensor}'),
                  _pill('Type: ${stats.latest!.type ?? 'current'}'),
                ],
                _pill(
                    'Trend: ${stats.trendLabel} (${stats.deltaPercent.toStringAsFixed(1)}%)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentEnergyMetrics(_CurrentEnergyStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.insights, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Current Metrics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _energyMetricTile(
                    'Latest Current',
                    '${stats.latestCurrentA.toStringAsFixed(3)} A',
                    Colors.blue),
                _energyMetricTile(
                    'Latest Current',
                    '${stats.latestCurrentMa.toStringAsFixed(0)} mA',
                    Colors.indigo),
                _energyMetricTile('Avg Current',
                    '${stats.avgCurrentA.toStringAsFixed(3)} A', Colors.teal),
                _energyMetricTile('Peak Current',
                    '${stats.maxCurrentA.toStringAsFixed(3)} A', Colors.orange),
                _energyMetricTile(
                    'Estimated Power',
                    '${stats.latestPowerW.toStringAsFixed(1)} W',
                    Colors.deepOrange),
                _energyMetricTile('Avg Power',
                    '${stats.avgPowerW.toStringAsFixed(1)} W', Colors.purple),
                _energyMetricTile('Signal', '${stats.latestRssi ?? 'n/a'} dBm',
                    stats.signalColor),
                _energyMetricTile('Energy (kWh)',
                    stats.estimatedEnergyKwh.toStringAsFixed(4), Colors.green),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Samples: ${stats.sampleCount} | Window: ${stats.windowMinutes} min',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentEnergyReadings(List<EnergyReading> readings) {
    final List<EnergyReading> sorted = List.of(readings)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final List<EnergyReading> latestTen = sorted.take(10).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.tune, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'Latest Current Readings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...latestTen.map(_energyReadingRow),
          ],
        ),
      ),
    );
  }

  Widget _energyReadingRow(EnergyReading reading) {
    final double powerW = reading.currentA * 230.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reading.location} • ${reading.module}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${reading.currentA.toStringAsFixed(3)} A | ${reading.currentMa.toStringAsFixed(0)} mA | ${powerW.toStringAsFixed(1)} W',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _friendlyTime(reading.receivedAt),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _energyMetricTile(String label, String value, Color color) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final bool hasActiveFilters = _selectedLocation != null ||
        _selectedModule != null ||
        _selectedDeviceId != null;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (hasActiveFilters)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedLocation = null;
                        _selectedModule = null;
                        _selectedDeviceId = null;
                      });
                      _loadReadings();
                    },
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedLocation,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Locations'),
                ),
                ..._availableLocations
                    .map((location) => DropdownMenuItem<String>(
                          value: location,
                          child:
                              Text(location, overflow: TextOverflow.ellipsis),
                        )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedLocation = value;
                });
                _loadReadings();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedModule,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Module ID',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Modules'),
                ),
                ..._availableModules.map((module) => DropdownMenuItem<String>(
                      value: module,
                      child: Text(module, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedModule = value;
                });
                _loadReadings();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedDeviceId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Device',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Devices'),
                ),
                ..._availableDevices.map((device) {
                  final id = (device['device_id'] ?? '').toString();
                  final name = (device['device_name'] ?? '').toString();
                  final label = name.isNotEmpty ? '$name ($id)' : id;
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedDeviceId = value;
                });
                _loadReadings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SensorReading latest, _DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  stats.isOccupied ? Icons.sensor_occupied : Icons.sensor_door,
                  color: stats.isOccupied ? Colors.green : Colors.amber,
                ),
                const SizedBox(width: 8),
                Text(
                  stats.isOccupied ? 'Occupied' : 'Vacant',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'Last seen: ${_friendlyTime(latest.receivedAt)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('${latest.location} • ${latest.module}'),
                _pill('Vacancy: ${stats.vacancyMinutes} min'),
                _pill('Avg temp: ${stats.avgTemp.toStringAsFixed(1)}°C'),
                _pill('Avg humidity: ${stats.avgHumidity.toStringAsFixed(0)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOccupancyStats() {
    if (_occupancyStats == null) {
      return const SizedBox.shrink();
    }

    final stats = _occupancyStats!;
    final isOccupied = stats['is_currently_occupied'] as bool? ?? false;
    final totalReadings = stats['total_readings'] as int? ?? 0;
    final occupiedCount = stats['occupied_count'] as int? ?? 0;
    final vacantCount = stats['vacant_count'] as int? ?? 0;
    final occupiedPercentage = stats['occupied_percentage'] as double? ?? 0.0;
    final vacantPercentage = stats['vacant_percentage'] as double? ?? 0.0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOccupied ? Icons.sensor_occupied : Icons.sensor_door,
                  color: isOccupied ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Occupancy Statistics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOccupied
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isOccupied ? 'Currently Occupied' : 'Currently Vacant',
                    style: TextStyle(
                      color:
                          isOccupied ? Colors.green[700] : Colors.orange[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    'Occupied',
                    '$occupiedCount',
                    '${occupiedPercentage.toStringAsFixed(1)}%',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statTile(
                    'Vacant',
                    '$vacantCount',
                    '${vacantPercentage.toStringAsFixed(1)}%',
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: occupiedPercentage / 100,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.green),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: vacantPercentage / 100,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.orange),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Based on last $totalReadings readings',
              style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String count, String percentage, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                count,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(width: 4),
              Text(
                percentage,
                style: TextStyle(
                    fontSize: 14, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComfortCard(_DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.thermostat, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text('Comfort & Drift',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _valueTile('Temp', '${stats.latestTemp.toStringAsFixed(1)}°C',
                    stats.tempStatusColor),
                const SizedBox(width: 10),
                _valueTile(
                    'Humidity',
                    '${stats.latestHumidity.toStringAsFixed(0)}%',
                    stats.humidityStatusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stats.comfortNote,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: stats.tempBandProgress,
                        minHeight: 8,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            stats.tempStatusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorHealth(SensorReading latest, _DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.wifi_tethering, color: Colors.blueGrey),
                SizedBox(width: 8),
                Text('Sensor Health',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _healthTile('RSSI', '${latest.rssi ?? -80} dBm',
                    stats.signalColor, stats.signalLabel),
                _healthTile(
                    'Uptime',
                    latest.uptime != null ? '${latest.uptime}s' : 'n/a',
                    Colors.indigo,
                    'since boot'),
                _healthTile(
                    'Heap',
                    latest.heap != null ? '${latest.heap} B' : 'n/a',
                    Colors.teal,
                    'free mem'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations() {
    final List<_RecItem> recs = _activeRecItems;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.lightbulb, color: Colors.amber),
                SizedBox(width: 8),
                Text('Actionable Recommendations',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (recs.isEmpty)
              Text('No recommendations right now.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7)))
            else
              ...List.generate(
                  recs.length,
                  (index) =>
                      _recTile(recs[index], () => _handleRecAction(index))),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 8),
              Text('History',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.8))),
              const SizedBox(height: 8),
              ..._history.take(5).map((entry) => _historyTile(entry)).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentReadings(List<SensorReading> readings) {
    final List<SensorReading> latestFive = List.of(readings)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final List<SensorReading> topFive = latestFive.take(5).toList();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.list_alt, color: Colors.indigo),
                SizedBox(width: 8),
                Text('Recent Readings',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...topFive.map((r) => _readingRow(r)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _recTile(_RecItem item, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.rec.icon, color: item.rec.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.rec.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: item.completed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    )),
                const SizedBox(height: 4),
                Text(item.rec.detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.completed
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                    )),
                if (item.completed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text('Completed',
                            style:
                                TextStyle(color: Colors.green, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: item.completed ? Colors.grey : item.rec.color,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(64, 36),
            ),
            onPressed: item.completed ? null : onPressed,
            child: Text(item.completed ? 'Done' : item.rec.cta,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(_CompletedEntry entry) {
    final _RecItem item = entry.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.rec.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(item.rec.detail,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7))),
                Text(_friendlyTime(entry.completedAt),
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleRecAction(int index) {
    if (index < 0 || index >= _activeRecItems.length) return;
    final _RecItem item = _activeRecItems[index];
    if (item.completed) return;

    // Sri Lankan timezone (UTC+5:30)
    const Duration sriLankaOffset = Duration(hours: 5, minutes: 30);
    final DateTime nowSriLanka = DateTime.now().toUtc().add(sriLankaOffset);

    setState(() {
      item.completed = true;
      _history.insert(0, _CompletedEntry(item: item, completedAt: nowSriLanka));
      _activeRecItems.removeAt(index);
      _appendNextRecLocked();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Completed: ${item.rec.title}')),
    );
  }

  Widget _readingRow(SensorReading reading) {
    final bool occupied = reading.occupied;
    final Color color = occupied ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showReadingDetails(reading),
        child: Row(
          children: [
            Icon(occupied ? Icons.sensor_occupied : Icons.sensor_door,
                color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${reading.location} • ${_friendlyTime(reading.receivedAt)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Temp ${reading.temperature.toStringAsFixed(1)}\u00b0C, Hum ${reading.humidity.toStringAsFixed(0)}%, PIR ${reading.pir}, RCWL ${reading.rcwl}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(occupied ? 'Occupied' : 'Vacant',
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showReadingDetails(SensorReading reading) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${reading.location} • ${reading.module}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Seen ${_friendlyTime(reading.receivedAt)}'),
              const SizedBox(height: 12),
              Text('PIR: ${reading.pir}, RCWL: ${reading.rcwl}'),
              Text(
                  'Temp: ${reading.temperature.toStringAsFixed(1)}°C, Hum: ${reading.humidity.toStringAsFixed(0)}%'),
              Text(
                  'RSSI: ${reading.rssi ?? 'n/a'} dBm, Uptime: ${reading.uptime ?? 0}s'),
              if (reading.heap != null) Text('Heap: ${reading.heap} B'),
              if (reading.ip != null) Text('IP: ${reading.ip}'),
              if (reading.mac != null) Text('MAC: ${reading.mac}'),
              if (reading.source != null) Text('Source: ${reading.source}'),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18)),
      child: Text(text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _valueTile(String label, String value, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.7))),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _healthTile(String label, String value, Color color, String hint) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.7))),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(hint,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6))),
          if (label == 'IP' && value != 'n/a')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _handleCopy(value),
                child: const Text('Copy', style: TextStyle(fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }

  String _friendlyTime(DateTime time) {
    // Sri Lankan timezone (UTC+5:30)
    const Duration sriLankaOffset = Duration(hours: 5, minutes: 30);

    // Convert current time to Sri Lankan time
    final DateTime nowSriLanka = DateTime.now().toUtc().add(sriLankaOffset);

    // Ensure time is in Sri Lankan timezone (already converted in fromJson)
    // If time is UTC, convert it; otherwise assume it's already in Sri Lankan time
    DateTime timeSriLanka = time.isUtc ? time.add(sriLankaOffset) : time;

    final Duration diff = nowSriLanka.difference(timeSriLanka);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _handleCopy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $value')),
    );
  }

  void _appendNextRecLocked() {
    if (_backlogRecs.isEmpty) return;

    while (_activeRecItems.length < _maxActiveRecs && _backlogRecs.isNotEmpty) {
      final _Recommendation next = _backlogRecs.removeAt(0);
      _activeRecItems.add(_RecItem(rec: next));
    }
  }
}

enum _AnalyticsTab {
  environment,
  currentEnergy,
}

class _CurrentEnergyStats {
  _CurrentEnergyStats({
    required this.latest,
    required this.latestCurrentA,
    required this.latestCurrentMa,
    required this.avgCurrentA,
    required this.minCurrentA,
    required this.maxCurrentA,
    required this.latestPowerW,
    required this.avgPowerW,
    required this.sampleCount,
    required this.windowMinutes,
    required this.deltaPercent,
    required this.trendLabel,
    required this.trendColor,
    required this.latestRssi,
    required this.signalColor,
    required this.estimatedEnergyKwh,
  });

  final EnergyReading? latest;
  final double latestCurrentA;
  final double latestCurrentMa;
  final double avgCurrentA;
  final double minCurrentA;
  final double maxCurrentA;
  final double latestPowerW;
  final double avgPowerW;
  final int sampleCount;
  final int windowMinutes;
  final double deltaPercent;
  final String trendLabel;
  final Color trendColor;
  final int? latestRssi;
  final Color signalColor;
  final double estimatedEnergyKwh;
}

class _DerivedStats {
  _DerivedStats({
    required this.avgTemp,
    required this.avgHumidity,
    required this.latestTemp,
    required this.latestHumidity,
    required this.isOccupied,
    required this.vacancyMinutes,
    required this.signalLabel,
    required this.signalColor,
    required this.tempStatusColor,
    required this.humidityStatusColor,
    required this.comfortNote,
    required this.tempBandProgress,
  });

  final double avgTemp;
  final double avgHumidity;
  final double latestTemp;
  final double latestHumidity;
  final bool isOccupied;
  final int vacancyMinutes;
  final String signalLabel;
  final Color signalColor;
  final Color tempStatusColor;
  final Color humidityStatusColor;
  final String comfortNote;
  final double tempBandProgress;
}

class _Recommendation {
  _Recommendation({
    required this.title,
    required this.detail,
    required this.cta,
    required this.color,
    required this.icon,
  });

  final String title;
  final String detail;
  final String cta;
  final Color color;
  final IconData icon;
}

class _RecItem {
  _RecItem({required this.rec});

  final _Recommendation rec;
  bool completed = false;
}

class _CompletedEntry {
  _CompletedEntry({required this.item, required this.completedAt});

  final _RecItem item;
  final DateTime completedAt;
}

_CurrentEnergyStats _deriveCurrentEnergyStats(
  List<EnergyReading> readings, {
  Map<String, dynamic>? usageResponse,
  String? selectedLocation,
}) {
  // If we have backend stats, use them directly
  if (usageResponse != null && usageResponse.containsKey('current_a')) {
    final currentAData =
        usageResponse['current_a'] as Map<String, dynamic>? ?? {};
    final currentMaData =
        usageResponse['current_ma'] as Map<String, dynamic>? ?? {};
    final powerWData = usageResponse['power_w'] as Map<String, dynamic>? ?? {};
    final trendData = usageResponse['trend'] as Map<String, dynamic>? ?? {};
    final signalData = usageResponse['signal'] as Map<String, dynamic>? ?? {};

    final double latestCurrentA =
        (currentAData['latest'] as num?)?.toDouble() ?? 0;
    final double latestCurrentMa =
        (currentMaData['latest'] as num?)?.toDouble() ?? 0;
    final double avgCurrentA = (currentAData['avg'] as num?)?.toDouble() ?? 0;
    final double minCurrentA = (currentAData['min'] as num?)?.toDouble() ?? 0;
    final double maxCurrentA = (currentAData['max'] as num?)?.toDouble() ?? 0;

    final double latestPowerW = (powerWData['latest'] as num?)?.toDouble() ?? 0;
    final double avgPowerW = (powerWData['avg'] as num?)?.toDouble() ?? 0;

    final double deltaPercent =
        (trendData['percent_change'] as num?)?.toDouble() ?? 0;
    final String trendDirection =
        trendData['direction']?.toString() ?? 'stable';

    final String trendLabel;
    final Color trendColor;
    if (trendDirection == 'stable') {
      trendLabel = 'Stable';
      trendColor = Colors.blue;
    } else if (trendDirection == 'rising') {
      trendLabel = 'Rising';
      trendColor = Colors.orange;
    } else {
      trendLabel = 'Falling';
      trendColor = Colors.green;
    }

    final int? latestRssi = signalData['latest_rssi'] as int?;
    final String signalQuality = signalData['quality']?.toString() ?? 'unknown';

    final Color signalColor;
    if (signalQuality == 'strong') {
      signalColor = Colors.green;
    } else if (signalQuality == 'fair') {
      signalColor = Colors.orange;
    } else if (signalQuality == 'weak') {
      signalColor = Colors.red;
    } else {
      signalColor = Colors.grey;
    }

    final double estimatedEnergyKwh =
        (usageResponse['estimated_energy_kwh'] as num?)?.toDouble() ?? 0;
    final int sampleCount = usageResponse['total_readings'] as int? ?? 0;
    final int windowMinutes = usageResponse['time_window_minutes'] as int? ?? 0;

    // Parse the latest reading if available
    EnergyReading? latest;
    if (usageResponse['latest'] != null) {
      try {
        latest = EnergyReading.fromJson(
            Map<String, dynamic>.from(usageResponse['latest'] as Map));
      } catch (_) {
        // Use first reading as fallback
        latest = readings.isNotEmpty ? readings.first : null;
      }
    } else {
      latest = readings.isNotEmpty ? readings.first : null;
    }

    return _CurrentEnergyStats(
      latest: latest,
      latestCurrentA: latestCurrentA,
      latestCurrentMa: latestCurrentMa,
      avgCurrentA: avgCurrentA,
      minCurrentA: minCurrentA,
      maxCurrentA: maxCurrentA,
      latestPowerW: latestPowerW,
      avgPowerW: avgPowerW,
      sampleCount: sampleCount,
      windowMinutes: windowMinutes,
      deltaPercent: deltaPercent,
      trendLabel: trendLabel,
      trendColor: trendColor,
      latestRssi: latestRssi,
      signalColor: signalColor,
      estimatedEnergyKwh: estimatedEnergyKwh,
    );
  }

  // Fallback to client-side computation if backend data not available
  if (readings.isEmpty) {
    return _CurrentEnergyStats(
      latest: null,
      latestCurrentA: 0,
      latestCurrentMa: 0,
      avgCurrentA: 0,
      minCurrentA: 0,
      maxCurrentA: 0,
      latestPowerW: 0,
      avgPowerW: 0,
      sampleCount: 0,
      windowMinutes: 0,
      deltaPercent: 0,
      trendLabel: 'Stable',
      trendColor: Colors.blue,
      latestRssi: null,
      signalColor: Colors.grey,
      estimatedEnergyKwh: 0,
    );
  }

  final List<EnergyReading> sorted = List.of(readings)
    ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

  final EnergyReading latest = sorted.last;
  final List<double> currentValues =
      sorted.map((r) => r.currentA).where((v) => v >= 0).toList();

  final double avgCurrentA = currentValues.isEmpty
      ? 0
      : currentValues.reduce((a, b) => a + b) / currentValues.length;
  final double minCurrentA =
      currentValues.isEmpty ? 0 : currentValues.reduce((a, b) => a < b ? a : b);
  final double maxCurrentA =
      currentValues.isEmpty ? 0 : currentValues.reduce((a, b) => a > b ? a : b);

  final double latestPowerW = latest.currentA * 230.0;
  final double avgPowerW = avgCurrentA * 230.0;

  final List<EnergyReading> recentSlice =
      sorted.length >= 6 ? sorted.sublist(sorted.length - 3) : sorted;
  final List<EnergyReading> baselineSlice = sorted.length >= 6
      ? sorted.sublist(sorted.length - 6, sorted.length - 3)
      : sorted;

  final double recentAvg = recentSlice.isEmpty
      ? 0
      : recentSlice.map((r) => r.currentA).reduce((a, b) => a + b) /
          recentSlice.length;
  final double baselineAvg = baselineSlice.isEmpty
      ? 0
      : baselineSlice.map((r) => r.currentA).reduce((a, b) => a + b) /
          baselineSlice.length;

  final double deltaPercent =
      baselineAvg == 0 ? 0 : ((recentAvg - baselineAvg) / baselineAvg) * 100;

  final String trendLabel;
  final Color trendColor;
  if (deltaPercent.abs() < 5) {
    trendLabel = 'Stable';
    trendColor = Colors.blue;
  } else if (deltaPercent > 0) {
    trendLabel = 'Rising';
    trendColor = Colors.orange;
  } else {
    trendLabel = 'Falling';
    trendColor = Colors.green;
  }

  final int? latestRssi = latest.wifiRssi;
  final Color signalColor;
  if (latestRssi == null) {
    signalColor = Colors.grey;
  } else if (latestRssi >= -60) {
    signalColor = Colors.green;
  } else if (latestRssi >= -75) {
    signalColor = Colors.orange;
  } else {
    signalColor = Colors.red;
  }

  double estimatedEnergyKwh = 0;
  final dynamic usageList = usageResponse?['usage'];
  if (usageList is List) {
    final Iterable<Map<String, dynamic>> rows =
        usageList.whereType<Map>().map((e) => Map<String, dynamic>.from(e));
    for (final row in rows) {
      final String rowLocation = (row['location'] ?? '').toString();
      if (selectedLocation != null &&
          selectedLocation.isNotEmpty &&
          rowLocation != selectedLocation) {
        continue;
      }
      final double kwh = (row['energy_kwh'] as num?)?.toDouble() ?? 0;
      estimatedEnergyKwh += kwh;
    }
  }

  final DateTime firstTime = sorted.first.receivedAt;
  final DateTime lastTime = sorted.last.receivedAt;
  final int windowMinutes =
      lastTime.difference(firstTime).inMinutes.clamp(0, 1 << 16).toInt();

  return _CurrentEnergyStats(
    latest: latest,
    latestCurrentA: latest.currentA,
    latestCurrentMa: latest.currentMa,
    avgCurrentA: avgCurrentA,
    minCurrentA: minCurrentA,
    maxCurrentA: maxCurrentA,
    latestPowerW: latestPowerW,
    avgPowerW: avgPowerW,
    sampleCount: sorted.length,
    windowMinutes: windowMinutes,
    deltaPercent: deltaPercent,
    trendLabel: trendLabel,
    trendColor: trendColor,
    latestRssi: latestRssi,
    signalColor: signalColor,
    estimatedEnergyKwh: estimatedEnergyKwh,
  );
}

_DerivedStats _deriveStats(List<SensorReading> readings) {
  final List<SensorReading> sorted = List.of(readings)
    ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  final SensorReading latest = sorted.last;

  final double avgTemp =
      sorted.map((r) => r.temperature).reduce((a, b) => a + b) / sorted.length;
  final double avgHumidity =
      sorted.map((r) => r.humidity).reduce((a, b) => a + b) / sorted.length;

  final SensorReading lastOccupied =
      sorted.reversed.firstWhere((r) => r.occupied, orElse: () => latest);
  final int vacancyMinutes = lastOccupied == latest
      ? 0
      : latest.receivedAt
          .difference(lastOccupied.receivedAt)
          .inMinutes
          .clamp(0, 1 << 16)
          .toInt();

  final int rssi = latest.rssi ?? -80;
  final String signalLabel;
  final Color signalColor;
  if (rssi >= -60) {
    signalLabel = 'Strong';
    signalColor = Colors.green;
  } else if (rssi >= -75) {
    signalLabel = 'Fair';
    signalColor = Colors.amber;
  } else {
    signalLabel = 'Weak';
    signalColor = Colors.red;
  }

  final double tempBandProgress =
      (((latest.temperature - 20) / 10).clamp(0, 1)).toDouble();
  final Color tempColor = latest.temperature > 30
      ? Colors.red
      : (latest.temperature >= 27 ? Colors.orange : Colors.green);
  final Color humidityColor = latest.humidity > 70
      ? Colors.orange
      : (latest.humidity < 40 ? Colors.amber : Colors.green);
  final String comfortNote = latest.temperature > 30
      ? 'Hot drift: lower setpoint or turn off if vacant.'
      : latest.temperature < 23
          ? 'Cooler than typical. Check setpoint.'
          : 'Within comfort band.';

  return _DerivedStats(
    avgTemp: avgTemp,
    avgHumidity: avgHumidity,
    latestTemp: latest.temperature,
    latestHumidity: latest.humidity,
    isOccupied: latest.occupied,
    vacancyMinutes: vacancyMinutes,
    signalLabel: signalLabel,
    signalColor: signalColor,
    tempStatusColor: tempColor,
    humidityStatusColor: humidityColor,
    comfortNote: comfortNote,
    tempBandProgress: tempBandProgress,
  );
}

List<_Recommendation> _buildRecList(_DerivedStats stats) {
  final List<_Recommendation> recs = [];
  if (!stats.isOccupied &&
      stats.latestTemp > 31 &&
      stats.vacancyMinutes >= 30) {
    recs.add(_Recommendation(
      title: 'Turn off AC in vacant room',
      detail:
          'Vacant for ${stats.vacancyMinutes} min at ${stats.latestTemp.toStringAsFixed(1)}°C.',
      cta: 'Send Alert',
      color: Colors.red,
      icon: Icons.ac_unit,
    ));
  }
  recs.add(_Recommendation(
    title: 'Align motion sensing',
    detail:
        'RCWL often 1 while PIR 0. Reposition sensor to reduce false motion.',
    cta: 'Inspect',
    color: Colors.indigo,
    icon: Icons.sensors,
  ));
  recs.add(_Recommendation(
    title: 'Check link quality',
    detail: 'RSSI ${stats.signalLabel}. Move gateway or adjust antenna.',
    cta: 'Check Link',
    color: stats.signalColor,
    icon: Icons.network_check,
  ));
  recs.add(_Recommendation(
    title: 'Comfort guardrails',
    detail: 'Keep 24-27°C occupied; allow 29-30°C when vacant to save energy.',
    cta: 'Apply',
    color: Colors.teal,
    icon: Icons.rule,
  ));
  return recs;
}
