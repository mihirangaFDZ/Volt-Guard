import 'package:flutter/material.dart';

class NotificationsPage extends StatelessWidget {
  final List<dynamic> anomalies;

  const NotificationsPage({super.key, required this.anomalies});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: anomalies.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'No new notifications',
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16.0),
              itemCount: anomalies.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final map = anomalies[index] as Map<String, dynamic>;
                final deviceName = map['device_name'] as String? ?? 'Device';
                final deviceType = map['device_type'] as String? ?? '';
                final desc = map['description'] as String? ?? '';
                final severity = map['severity'] as String? ?? 'Low';
                final anomalyType = map['anomaly_type'] as String? ?? '';
                
                final color = _severityColor(severity);

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _deviceIcon(deviceType),
                        color: color,
                      ),
                    ),
                    title: Text(
                      deviceName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(desc),
                        if (anomalyType.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            anomalyType,
                            style: TextStyle(
                              fontSize: 12,
                              color: color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ]
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        severity,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}