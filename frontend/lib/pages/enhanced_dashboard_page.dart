import 'package:flutter/material.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import '../services/energy_service.dart';
import '../services/device_service.dart';
import '../services/anomaly_service.dart';
import '../services/prediction_service.dart';

/// Enhanced dashboard page with real-time visualization and customizable widgets
class EnhancedDashboardPage extends StatefulWidget {
  const EnhancedDashboardPage({super.key});

  @override
  State<EnhancedDashboardPage> createState() => _EnhancedDashboardPageState();
}

class _EnhancedDashboardPageState extends State<EnhancedDashboardPage> {
  final EnergyService _energyService = EnergyService();
  final DeviceService _deviceService = DeviceService();
  final AnomalyService _anomalyService = AnomalyService();
  final PredictionService _predictionService = PredictionService();

  Timer? _refreshTimer;
  bool _isLoading = true;
  String _errorMessage = '';

  // Dashboard data
  Map<String, dynamic>? _todaySummary;
  Map<String, dynamic>? _tomorrowPrediction;
  List<Map<String, dynamic>> _activeAnomalies = [];
  List<Map<String, dynamic>> _deviceStatus = [];
  List<Map<String, dynamic>> _recommendations = [];
  Map<String, dynamic>? _realTimeData;

  // Widget visibility (customizable)
  bool _showEnergyWidget = true;
  bool _showPredictionWidget = true;
  bool _showAnomaliesWidget = true;
  bool _showDevicesWidget = true;
  bool _showRecommendationsWidget = true;
  bool _showChartWidget = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startRealTimeUpdates();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRealTimeUpdates() {
    // Refresh data every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadDashboardData(silent: true);
      }
    });
  }

  Future<void> _loadDashboardData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      // Load all data in parallel
      final results = await Future.wait([
        _energyService.getTodaySummary(),
        _predictionService.getTomorrowPrediction(),
        _anomalyService.getActiveAnomalies(),
        _deviceService.getRealTimeDeviceStatus(),
        _predictionService.getRecommendations(),
        _energyService.getRealTimeConsumption(),
      ]);

      if (mounted) {
        setState(() {
          _todaySummary = results[0] as Map<String, dynamic>;
          _tomorrowPrediction = results[1] as Map<String, dynamic>;
          _activeAnomalies = results[2] as List<Map<String, dynamic>>;
          _deviceStatus = results[3] as List<Map<String, dynamic>>;
          _recommendations = results[4] as List<Map<String, dynamic>>;
          _realTimeData = results[5] as Map<String, dynamic>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _toggleWidget(String widgetName, bool value) {
    setState(() {
      switch (widgetName) {
        case 'energy':
          _showEnergyWidget = value;
          break;
        case 'prediction':
          _showPredictionWidget = value;
          break;
        case 'anomalies':
          _showAnomaliesWidget = value;
          break;
        case 'devices':
          _showDevicesWidget = value;
          break;
        case 'recommendations':
          _showRecommendationsWidget = value;
          break;
        case 'chart':
          _showChartWidget = value;
          break;
      }
    });
  }

  void _showCustomizationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customize Dashboard'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Energy Summary'),
                value: _showEnergyWidget,
                onChanged: (value) {
                  _toggleWidget('energy', value);
                  Navigator.pop(context);
                  _showCustomizationDialog();
                },
              ),
              SwitchListTile(
                title: const Text('Predictions'),
                value: _showPredictionWidget,
                onChanged: (value) {
                  _toggleWidget('prediction', value);
                  Navigator.pop(context);
                  _showCustomizationDialog();
                },
              ),
              SwitchListTile(
                title: const Text('Active Anomalies'),
                value: _showAnomaliesWidget,
                onChanged: (value) {
                  _toggleWidget('anomalies', value);
                  Navigator.pop(context);
                  _showCustomizationDialog();
                },
              ),
              SwitchListTile(
                title: const Text('Device Status'),
                value: _showDevicesWidget,
                onChanged: (value) {
                  _toggleWidget('devices', value);
                  Navigator.pop(context);
                  _showCustomizationDialog();
                },
              ),
              SwitchListTile(
                title: const Text('Recommendations'),
                value: _showRecommendationsWidget,
                onChanged: (value) {
                  _toggleWidget('recommendations', value);
                  Navigator.pop(context);
                  _showCustomizationDialog();
                },
              ),
              SwitchListTile(
                title: const Text('Real-Time Chart'),
                value: _showChartWidget,
                onChanged: (value) {
                  _toggleWidget('chart', value);
                  Navigator.pop(context);
                  _showCustomizationDialog();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Energy Dashboard'),
            const SizedBox(width: 8),
            if (_realTimeData != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          if (_activeAnomalies.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {
                    _showAnomaliesDialog();
                  },
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _activeAnomalies.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () {},
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showCustomizationDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: () => _loadDashboardData(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_showEnergyWidget) ...[
                          _buildTodayEnergyWidget(),
                          const SizedBox(height: 16),
                        ],
                        if (_showChartWidget) ...[
                          _buildRealTimeChart(),
                          const SizedBox(height: 16),
                        ],
                        if (_showPredictionWidget) ...[
                          _buildTomorrowPredictionWidget(),
                          const SizedBox(height: 16),
                        ],
                        if (_showAnomaliesWidget && _activeAnomalies.isNotEmpty) ...[
                          _buildAnomaliesWidget(),
                          const SizedBox(height: 16),
                        ],
                        if (_showRecommendationsWidget &&
                            _recommendations.isNotEmpty) ...[
                          _buildRecommendationsWidget(),
                          const SizedBox(height: 16),
                        ],
                        if (_showDevicesWidget) ...[
                          _buildDeviceStatusWidget(),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'Error loading dashboard',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _loadDashboardData(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayEnergyWidget() {
    final totalConsumption = _todaySummary?['total_consumption'] ?? 0.0;
    final estimatedCost = _todaySummary?['estimated_cost'] ?? 0.0;
    final peakHour = _todaySummary?['peak_hour'] ?? 'N/A';
    final avgPower = _todaySummary?['avg_power'] ?? 0.0;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Consumption',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${totalConsumption.toStringAsFixed(1)} kWh',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.bolt,
                    color: Colors.blue,
                    size: 40,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildQuickStat(
                  'Cost',
                  '\$${estimatedCost.toStringAsFixed(2)}',
                  Icons.attach_money,
                  Colors.green,
                ),
                _buildQuickStat(
                  'Peak Hour',
                  peakHour,
                  Icons.trending_up,
                  Colors.orange,
                ),
                _buildQuickStat(
                  'Avg Power',
                  '${avgPower.toStringAsFixed(1)} kW',
                  Icons.speed,
                  Colors.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildRealTimeChart() {
    // Sample data - replace with real-time data from your API
    final List<FlSpot> spots = List.generate(
      20,
      (index) => FlSpot(
        index.toDouble(),
        (_realTimeData?['values']?[index] ?? (20 + (index % 10) * 5)).toDouble(),
      ),
    );

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Real-Time Power Usage',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.blue[700]),
                      const SizedBox(width: 6),
                      const Text(
                        'Live',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 10,
                    getDrawingHorizontalLine: (value) {
                      return const FlLine(
                        color: Color.fromARGB(255, 107, 51, 51),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}W',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                  minY: 0,
                  maxY: 60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTomorrowPredictionWidget() {
    final predictedUsage = _tomorrowPrediction?['predicted_usage'] ?? 0.0;
    final estimatedCost = _tomorrowPrediction?['estimated_cost'] ?? 0.0;
    final percentageChange = _tomorrowPrediction?['percentage_change'] ?? 0.0;
    final peakHours = _tomorrowPrediction?['peak_hours'] ?? 'N/A';

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber[700], size: 28),
                const SizedBox(width: 12),
                const Text(
                  'AI-Powered Forecast',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tomorrow\'s Prediction',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${predictedUsage.toStringAsFixed(1)} kWh',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            percentageChange >= 0
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 18,
                            color: percentageChange >= 0 ? Colors.red : Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${percentageChange >= 0 ? '+' : ''}${percentageChange.toStringAsFixed(1)}% from today',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  percentageChange >= 0 ? Colors.red : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Est. Cost',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${estimatedCost.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.orange[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Peak hours expected: $peakHours',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnomaliesWidget() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Active Anomalies',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_activeAnomalies.length} Active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _activeAnomalies.length > 3 ? 3 : _activeAnomalies.length,
              itemBuilder: (context, index) {
                final anomaly = _activeAnomalies[index];
                return _buildAnomalyItem(anomaly);
              },
            ),
            if (_activeAnomalies.length > 3)
              TextButton(
                onPressed: _showAnomaliesDialog,
                child: const Text('View All Anomalies'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnomalyItem(Map<String, dynamic> anomaly) {
    final deviceName = anomaly['device_name'] ?? 'Unknown Device';
    final description = anomaly['description'] ?? 'No description';
    final severity = anomaly['severity'] ?? 'Medium';
    
    Color severityColor;
    switch (severity.toLowerCase()) {
      case 'high':
      case 'critical':
        severityColor = Colors.red;
        break;
      case 'medium':
        severityColor = Colors.orange;
        break;
      default:
        severityColor = Colors.yellow;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: severityColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: severityColor, size: 28),
          const SizedBox(width: 12),
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
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: severityColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              severity,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsWidget() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tips_and_updates, color: Colors.green[700], size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Energy-Saving Tips',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount:
                  _recommendations.length > 3 ? 3 : _recommendations.length,
              itemBuilder: (context, index) {
                final recommendation = _recommendations[index];
                return _buildRecommendationItem(recommendation);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationItem(Map<String, dynamic> recommendation) {
    final title = recommendation['title'] ?? 'Recommendation';
    final description = recommendation['description'] ?? '';
    final savings = recommendation['estimated_savings_kwh'] ?? 0.0;
    final costSavings = recommendation['estimated_cost_savings'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Save ${savings.toStringAsFixed(1)} kWh',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Estimated savings: \$${costSavings.toStringAsFixed(2)}/month',
            style: TextStyle(
              fontSize: 12,
              color: Colors.green[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusWidget() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _deviceStatus.length > 5 ? 5 : _deviceStatus.length,
              itemBuilder: (context, index) {
                final device = _deviceStatus[index];
                return _buildDeviceStatusItem(device);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusItem(Map<String, dynamic> device) {
    final name = device['name'] ?? 'Unknown';
    final power = device['current_power'] ?? 0.0;
    final status = device['status'] ?? 'unknown';

    Color statusColor;
    switch (status.toLowerCase()) {
      case 'on':
      case 'active':
        statusColor = Colors.green;
        break;
      case 'off':
      case 'inactive':
        statusColor = Colors.grey;
        break;
      case 'warning':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.blue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${power.toStringAsFixed(1)}W',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showAnomaliesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('All Active Anomalies'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _activeAnomalies.length,
            itemBuilder: (context, index) {
              return _buildAnomalyItem(_activeAnomalies[index]);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
