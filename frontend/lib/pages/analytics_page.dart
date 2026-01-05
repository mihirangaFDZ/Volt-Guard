import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sensor_reading.dart';
import '../services/analytics_service.dart';
import '../services/optimization_service.dart';

/// Component-focused analytics page for occupancy, comfort, sensor health, and recommendations
/// using the provided IoT fields (pir/rcwl, temperature, humidity, rssi, uptime, timestamps).
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final AnalyticsService _analyticsService = AnalyticsService();
  final OptimizationService _optimizationService = OptimizationService();

  static const int _maxActiveRecs = 3;
  List<SensorReading> _readings = [];
  bool _loading = true;
  String? _error;
  List<_RecItem> _activeRecItems = [];
  List<_Recommendation> _backlogRecs = [];
  List<_CompletedEntry> _history = [];
  
  // Store original AI recommendations for detailed view
  Map<String, AIRecommendation> _aiRecDetailsMap = {};
  
  // Filter state
  String? _selectedLocation;
  String? _selectedModule;
  List<String> _availableLocations = [];
  List<String> _availableModules = [];
  bool _filtersLoading = false;
  
  // Occupancy stats
  Map<String, dynamic>? _occupancyStats;
  
  // AI Recommendations
  OptimizationResponse? _aiRecommendations;
  bool _loadingAIRecommendations = false;

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadReadings();
  }

  Future<void> _loadFilters() async {
    try {
      setState(() {
        _filtersLoading = true;
      });
      final filters = await _analyticsService.fetchAvailableFilters();
      if (!mounted) return;
      setState(() {
        _availableLocations = filters['locations'] ?? [];
        _availableModules = filters['modules'] ?? [];
        _filtersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _filtersLoading = false;
      });
      // Don't show error for filters, just continue without them
    }
  }

  Future<void> _loadReadings() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final data = await _analyticsService.fetchLatestReadings(
        limit: 50,
        location: _selectedLocation,
        module: _selectedModule,
      );
      
      // Fetch occupancy stats
      Map<String, dynamic>? occupancyStats;
      try {
        occupancyStats = await _analyticsService.fetchOccupancyStats(
          limit: 50,
          location: _selectedLocation,
          module: _selectedModule,
        );
      } catch (e) {
        // Ignore errors for occupancy stats
      }
      
      _DerivedStats? stats;
      if (data.isNotEmpty) {
        stats = _deriveStats(data);
      }
      if (!mounted) return;
      
      // Fetch AI recommendations
      OptimizationResponse? aiRecsResponse;
      try {
        setState(() {
          _loadingAIRecommendations = true;
        });
        aiRecsResponse = await _optimizationService.fetchRecommendations(
          days: 2,
          location: _selectedLocation,
          module: _selectedModule,
        );
      } catch (e) {
        // If AI recommendations fail, show empty list
        if (!mounted) return;
        setState(() {
          _loadingAIRecommendations = false;
          _aiRecommendations = null;
        });
      } finally {
        if (!mounted) return;
        if (_loadingAIRecommendations) {
          setState(() {
            _loadingAIRecommendations = false;
            _aiRecommendations = aiRecsResponse;
          });
        }
      }
      
      // Convert AI recommendations to _Recommendation format
      List<_Recommendation> aiRecs = [];
      if (aiRecsResponse != null && aiRecsResponse.recommendations.isNotEmpty) {
        for (final aiRec in aiRecsResponse.recommendations) {
          // Determine color and icon based on severity
          Color recColor;
          IconData recIcon;
          switch (aiRec.severity.toLowerCase()) {
            case 'high':
              recColor = Colors.red;
              recIcon = Icons.priority_high;
              break;
            case 'medium':
              recColor = Colors.orange;
              recIcon = Icons.info;
              break;
            default:
              recColor = Colors.blue;
              recIcon = Icons.lightbulb_outline;
          }
          
          // Add savings info to detail if available
          String detail = aiRec.message;
          if (aiRec.estimatedSavings > 0) {
            detail += ' (Potential savings: ${aiRec.estimatedSavings.toStringAsFixed(2)} kWh/day)';
          }
          
          // Create a unique ID for this recommendation
          final recId = '${aiRec.type}_${aiRec.title}_${DateTime.now().millisecondsSinceEpoch}_${aiRecs.length}';
          
          // Store original AI recommendation for detailed view
          _aiRecDetailsMap[recId] = aiRec;
          
          aiRecs.add(_Recommendation(
            title: aiRec.title,
            detail: detail,
            cta: 'View Details',
            color: recColor,
            icon: recIcon,
            id: recId, // Store ID for lookup
          ));
        }
      }
      
      if (!mounted) return;
      setState(() {
        _readings = data;
        _occupancyStats = occupancyStats;
        final recItems = aiRecs.map((r) => _RecItem(rec: r)).toList();
        _activeRecItems = recItems.take(_maxActiveRecs).toList();
        _backlogRecs = recItems.skip(_maxActiveRecs).map((item) => item.rec).toList();
        _history = [];
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
        onRefresh: _loadReadings,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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

    if (_readings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _emptyState(),
        ],
      );
    }

    final SensorReading latest = _latestReading(_readings);
    final _DerivedStats stats = _deriveStats(_readings);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilters(),
          const SizedBox(height: 16),
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
        ],
      ),
    );
  }

  SensorReading _latestReading(List<SensorReading> readings) {
    return readings.reduce((a, b) => a.receivedAt.isAfter(b.receivedAt) ? a : b);
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
                  Text(message, style: TextStyle(color: Colors.red[700], fontSize: 12)),
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

  Widget _emptyState() {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.sensors_off, color: Colors.grey),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No sensor readings yet. Pull to refresh or wait for devices to send data.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final bool hasActiveFilters = _selectedLocation != null || _selectedModule != null;
    
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
                      });
                      _loadReadings();
                    },
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Locations'),
                ),
                ..._availableLocations.map((location) => DropdownMenuItem<String>(
                      value: location,
                      child: Text(location, overflow: TextOverflow.ellipsis),
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
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'Last seen: ${_friendlyTime(latest.receivedAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOccupied ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isOccupied ? 'Currently Occupied' : 'Currently Vacant',
                    style: TextStyle(
                      color: isOccupied ? Colors.green[700] : Colors.orange[700],
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
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: vacantPercentage / 100,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Based on last $totalReadings readings',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
            style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                count,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(width: 4),
              Text(
                percentage,
                style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600),
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
                Text('Comfort & Drift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _valueTile('Temp', '${stats.latestTemp.toStringAsFixed(1)}°C', stats.tempStatusColor),
                const SizedBox(width: 10),
                _valueTile('Humidity', '${stats.latestHumidity.toStringAsFixed(0)}%', stats.humidityStatusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stats.comfortNote, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: stats.tempBandProgress,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(stats.tempStatusColor),
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
                Text('Sensor Health', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _healthTile('RSSI', '${latest.rssi ?? -80} dBm', stats.signalColor, stats.signalLabel),
                _healthTile('Uptime', latest.uptime != null ? '${latest.uptime}s' : 'n/a', Colors.indigo, 'since boot'),
                _healthTile('Heap', latest.heap != null ? '${latest.heap} B' : 'n/a', Colors.teal, 'free mem'),
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
                Text('Actionable Recommendations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (recs.isEmpty)
              Text('No recommendations right now.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]))
            else
              ...List.generate(recs.length, (index) => _recTile(recs[index], () => _handleRecAction(index))),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: Colors.grey[300]),
              const SizedBox(height: 8),
              Text('History', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey[800])),
              const SizedBox(height: 8),
              ..._history.take(5).map((entry) => _historyTile(entry)).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAIRecommendations() {
    if (_loadingAIRecommendations) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(
                'Loading AI recommendations...',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_aiRecommendations == null || _aiRecommendations!.recommendations.isEmpty) {
      return const SizedBox.shrink(); // Hide if no recommendations
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.psychology, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  'AI Energy Recommendations',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (_aiRecommendations!.potentialSavingsKwhPerDay > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.savings, color: Colors.green[700], size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Potential Savings',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_aiRecommendations!.potentialSavingsKwhPerDay.toStringAsFixed(2)} kWh/day',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_aiRecommendations!.currentEnergyWatts != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Current',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${_aiRecommendations!.currentEnergyWatts!.toStringAsFixed(0)} W',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            ..._aiRecommendations!.recommendations.map((rec) => _buildAIRecommendationTile(rec)),
          ],
        ),
      ),
    );
  }

  Widget _buildAIRecommendationTile(AIRecommendation rec) {
    Color severityColor;
    IconData iconData;
    
    switch (rec.severity.toLowerCase()) {
      case 'high':
        severityColor = Colors.red;
        iconData = Icons.priority_high;
        break;
      case 'medium':
        severityColor = Colors.orange;
        iconData = Icons.info;
        break;
      default:
        severityColor = Colors.blue;
        iconData = Icons.lightbulb_outline;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: severityColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconData, color: severityColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rec.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: severityColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        rec.severity.toUpperCase(),
                        style: TextStyle(
                          color: severityColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  rec.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
                if (rec.estimatedSavings > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.savings, size: 14, color: Colors.green[700]),
                      const SizedBox(width: 4),
                      Text(
                        '${rec.estimatedSavings.toStringAsFixed(2)} kWh/day',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
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
                Text('Recent Readings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      decoration: item.completed ? TextDecoration.lineThrough : TextDecoration.none,
                    )),
                const SizedBox(height: 4),
                Text(item.rec.detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.completed ? Colors.grey[500] : Colors.grey[700],
                    )),
                if (item.completed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text('Completed', style: TextStyle(color: Colors.green, fontSize: 12)),
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
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
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
                Text(item.rec.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(item.rec.detail,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                Text(_friendlyTime(entry.completedAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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

    // If this recommendation has an ID, show detailed view
    if (item.rec.id != null && _aiRecDetailsMap.containsKey(item.rec.id)) {
      _showRecommendationDetails(item.rec.id!);
      return;
    }

    // Otherwise, mark as completed (legacy behavior)
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

  void _showRecommendationDetails(String recId) {
    final aiRec = _aiRecDetailsMap[recId];
    if (aiRec == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getSeverityColor(aiRec.severity).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getSeverityIcon(aiRec.severity),
                          color: _getSeverityColor(aiRec.severity),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              aiRec.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getSeverityColor(aiRec.severity).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                aiRec.severity.toUpperCase(),
                                style: TextStyle(
                                  color: _getSeverityColor(aiRec.severity),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Message
                  Text(
                    aiRec.message,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Estimated Savings
                  if (aiRec.estimatedSavings > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.savings, color: Colors.green[700], size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Potential Savings',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${aiRec.estimatedSavings.toStringAsFixed(2)} kWh/day',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Detailed Information
                  const Text(
                    'Detailed Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Location and Module
                  if (aiRec.location != null || aiRec.module != null) ...[
                    _buildDetailRow('Location', aiRec.location ?? 'Unknown'),
                    _buildDetailRow('Module', aiRec.module ?? 'Unknown'),
                    const SizedBox(height: 8),
                  ],
                  
                  // Energy Information
                  if (aiRec.currentEnergyWatts != null)
                    _buildDetailRow('Current Energy', '${aiRec.currentEnergyWatts!.toStringAsFixed(2)} W'),
                  
                  // Occupancy Information
                  const Divider(),
                  const Text(
                    'Occupancy Status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (aiRec.isOccupied != null)
                    _buildDetailRow(
                      'Status',
                      aiRec.isOccupied! ? 'Occupied' : 'Vacant',
                      valueColor: aiRec.isOccupied! ? Colors.green : Colors.orange,
                    ),
                  if (aiRec.vacancyDurationMinutes != null && (aiRec.isOccupied == false))
                    _buildDetailRow(
                      'Vacancy Duration',
                      _formatDuration(aiRec.vacancyDurationMinutes!),
                    ),
                  if (aiRec.pir != null)
                    _buildDetailRow('PIR Sensor', aiRec.pir == 1 ? 'Motion Detected' : 'No Motion'),
                  if (aiRec.rcwl != null)
                    _buildDetailRow('RCWL Sensor', aiRec.rcwl == 1 ? 'Motion Detected' : 'No Motion'),
                  
                  // Environmental Information
                  if (aiRec.currentTemperature != null || aiRec.currentHumidity != null) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const Text(
                      'Environmental Conditions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (aiRec.currentTemperature != null)
                    _buildDetailRow(
                      'Temperature',
                      '${aiRec.currentTemperature!.toStringAsFixed(1)}°C',
                      valueColor: _getTempColor(aiRec.currentTemperature!),
                    ),
                  if (aiRec.currentHumidity != null)
                    _buildDetailRow(
                      'Humidity',
                      '${aiRec.currentHumidity!.toStringAsFixed(0)}%',
                      valueColor: _getHumidityColor(aiRec.currentHumidity!),
                    ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.grey[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes minutes';
    } else if (minutes < 1440) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '$hours hours $mins minutes' : '$hours hours';
    } else {
      final days = minutes ~/ 1440;
      final hours = (minutes % 1440) ~/ 60;
      return hours > 0 ? '$days days $hours hours' : '$days days';
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  IconData _getSeverityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Icons.priority_high;
      case 'medium':
        return Icons.info;
      default:
        return Icons.lightbulb_outline;
    }
  }

  Color _getTempColor(double temp) {
    if (temp > 30) return Colors.red;
    if (temp >= 27) return Colors.orange;
    return Colors.green;
  }

  Color _getHumidityColor(double humidity) {
    if (humidity > 70) return Colors.orange;
    if (humidity < 40) return Colors.amber;
    return Colors.green;
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
            Icon(occupied ? Icons.sensor_occupied : Icons.sensor_door, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${reading.location} • ${_friendlyTime(reading.receivedAt)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Temp ${reading.temperature.toStringAsFixed(1)}°C, Hum ${reading.humidity.toStringAsFixed(0)}%, PIR ${reading.pir}, RCWL ${reading.rcwl}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(occupied ? 'Occupied' : 'Vacant',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Seen ${_friendlyTime(reading.receivedAt)}'),
              const SizedBox(height: 12),
              Text('PIR: ${reading.pir}, RCWL: ${reading.rcwl}'),
              Text('Temp: ${reading.temperature.toStringAsFixed(1)}°C, Hum: ${reading.humidity.toStringAsFixed(0)}%'),
              Text('RSSI: ${reading.rssi ?? 'n/a'} dBm, Uptime: ${reading.uptime ?? 0}s'),
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
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(18)),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _valueTile(String label, String value, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _healthTile(String label, String value, Color color, String hint) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(hint, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
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
    this.id,
  });

  final String title;
  final String detail;
  final String cta;
  final Color color;
  final IconData icon;
  final String? id; // ID to lookup detailed AI recommendation
}

class _RecItem {
  _RecItem({required this.rec, this.completed = false});

  final _Recommendation rec;
  bool completed;
}

class _CompletedEntry {
  _CompletedEntry({required this.item, required this.completedAt});

  final _RecItem item;
  final DateTime completedAt;
}

_DerivedStats _deriveStats(List<SensorReading> readings) {
  final List<SensorReading> sorted = List.of(readings)..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  final SensorReading latest = sorted.last;

  final double avgTemp = sorted.map((r) => r.temperature).reduce((a, b) => a + b) / sorted.length;
  final double avgHumidity = sorted.map((r) => r.humidity).reduce((a, b) => a + b) / sorted.length;

  final SensorReading lastOccupied = sorted.reversed.firstWhere((r) => r.occupied, orElse: () => latest);
  final int vacancyMinutes = lastOccupied == latest
      ? 0
      : latest.receivedAt.difference(lastOccupied.receivedAt).inMinutes.clamp(0, 1 << 16).toInt();

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

  final double tempBandProgress = (((latest.temperature - 20) / 10).clamp(0, 1)).toDouble();
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


