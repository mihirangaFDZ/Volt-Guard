import 'package:flutter/material.dart';
import 'package:volt_guard/services/dashboard_service.dart';

class AnomaliesPage extends StatefulWidget {
  const AnomaliesPage({super.key});

  @override
  State<AnomaliesPage> createState() => _AnomaliesPageState();
}

class _AnomaliesPageState extends State<AnomaliesPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _anomalies = [];

  @override
  void initState() {
    super.initState();
    _loadAnomalies();
  }

  Future<void> _loadAnomalies() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await DashboardService.getSummary();
      setState(() {
        _anomalies = data['anomalies'] as List<dynamic>? ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active Anomalies')),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green.shade400),
            const SizedBox(height: 16),
            Text('No active anomalies',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('All devices are operating normally.',
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                )),
          ],
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
