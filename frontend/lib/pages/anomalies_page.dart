import 'package:flutter/material.dart';
import 'package:volt_guard/services/anomaly_alert_service.dart';

class AnomaliesPage extends StatefulWidget {
  const AnomaliesPage({super.key});

  @override
  State<AnomaliesPage> createState() => _AnomaliesPageState();
}

class _AnomaliesPageState extends State<AnomaliesPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _anomalies = [];
  bool _isDetecting = false;
  final AnomalyAlertService _anomalyService = AnomalyAlertService();

  @override
  void initState() {
    super.initState();
    _loadAnomalies();
  }

  /// Run anomaly detection on real energy readings from DB; saves results to anomalies table, then refresh list.
  Future<void> _runDetectionOnRealData() async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);
    try {
      await _anomalyService.detectAnomalies(hoursBack: 24, minScore: 0.5, method: 'both');
      if (!mounted) return;
      await _loadAnomalies();
      if (!mounted) return;
      setState(() => _isDetecting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isDetecting = false;
      });
    }
  }

  /// Load active anomalies from the anomalies API (real data from DB only).
  Future<void> _loadAnomalies() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await _anomalyService.fetchActiveAlerts(
        limit: 50,
        hoursBack: 168,
      );
      if (!mounted) return;
      setState(() {
        _anomalies = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Anomalies'),
        actions: [
          IconButton(
            tooltip: 'Detect from real data',
            icon: _isDetecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            onPressed: _isDetecting ? null : _runDetectionOnRealData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off,
                  size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Failed to load anomalies',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  )),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadAnomalies,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_anomalies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 64, color: Colors.green.shade400),
              const SizedBox(height: 16),
              Text('No active anomalies',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Anomalies are created from your real energy readings and saved to the database. Tap the play button to run detection on the latest data.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isDetecting ? null : _runDetectionOnRealData,
                icon: _isDetecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 20),
                label: Text(_isDetecting ? 'Detecting...' : 'Detect from real data'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnomalies,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _anomalies.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final map = _anomalies[index] as Map<String, dynamic>;
          final deviceName = map['device_name'] as String? ?? 'Unknown';
          final deviceType = map['device_type'] as String? ?? '';
          final description = map['description'] as String? ?? '';
          final severity = map['severity'] as String? ?? 'Low';
          final anomalyType = map['anomaly_type'] as String? ?? '';
          final detectedAt = map['detected_at']?.toString();
          final score = (map['anomaly_score'] as num?)?.toDouble();

          return Card(
            elevation: 1,
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _severityColor(severity).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_deviceIcon(deviceType),
                    color: _severityColor(severity), size: 24),
              ),
              title: Text(deviceName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(description),
                  if (anomalyType.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      anomalyType,
                      style: TextStyle(
                        fontSize: 12,
                        color: _severityColor(severity),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (detectedAt != null && detectedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDetectedAt(detectedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                  if (score != null && score > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Score: ${score.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ],
              ),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _severityColor(severity),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  severity,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }

  String _formatDetectedAt(String detectedAt) {
    try {
      final dt = DateTime.parse(detectedAt);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return detectedAt;
    }
  }

  Color _severityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return Colors.red.shade900;
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.yellow.shade700;
      default:
        return Colors.grey;
    }
  }

  IconData _deviceIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'ac':
      case 'air conditioner':
        return Icons.ac_unit;
      case 'refrigerator':
      case 'fridge':
        return Icons.kitchen;
      case 'water heater':
      case 'heater':
        return Icons.water_drop;
      case 'washing machine':
        return Icons.local_laundry_service;
      case 'light':
      case 'lighting':
        return Icons.lightbulb;
      case 'fan':
        return Icons.air;
      default:
        return Icons.electrical_services;
    }
  }
}
