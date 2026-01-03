import 'package:flutter/material.dart';

/// Dashboard page showing real-time energy usage, predictions, and alerts
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Energy Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notifications')),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(seconds: 1));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Today's Energy Consumption
              _buildSectionTitle(context, 'Today\'s Energy'),
              const SizedBox(height: 12),
              _buildTodayEnergyCard(context),
              const SizedBox(height: 24),

              // Savings in Rupees
              _buildSectionTitle(context, 'Savings (Rs)'),
              const SizedBox(height: 12),
              _buildSavingsCard(context),
              const SizedBox(height: 24),

              // Tomorrow's Predictions
              _buildSectionTitle(context, 'Tomorrow\'s Prediction'),
              const SizedBox(height: 12),
              _buildTomorrowPredictionCard(context),
              const SizedBox(height: 24),

              // Active Device Anomalies
              _buildSectionTitle(context, 'Active Anomalies'),
              const SizedBox(height: 12),
              _buildAnomaliesSection(context),
              const SizedBox(height: 24),

              // Energy-Saving Insights
              _buildSectionTitle(context, 'Energy-Saving Insights'),
              const SizedBox(height: 12),
              _buildEnergySavingsCard(context),
              const SizedBox(height: 24),

              // Device-Wise Real-Time Usage
              _buildSectionTitle(context, 'Real-Time Device Usage'),
              const SizedBox(height: 12),
              _buildDeviceUsageList(context),
              const SizedBox(height: 24),

              // Device Behavior Comparison
              _buildSectionTitle(context, 'Device Behavior Comparison'),
              const SizedBox(height: 12),
              _buildDeviceBehaviorCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _buildTodayEnergyCard(BuildContext context) {
    return Card(
      elevation: 2,
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
                      'Total Consumption',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '24.8 kWh',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bolt,
                    color: Colors.blue,
                    size: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey[300]),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildQuickStat('Estimated Cost', 'Rs 6.82', Colors.green),
                Container(
                  height: 40,
                  width: 1,
                  color: Colors.grey[300],
                ),
                _buildQuickStat('Peak Hour', '7-9 PM', Colors.orange),
                Container(
                  height: 40,
                  width: 1,
                  color: Colors.grey[300],
                ),
                _buildQuickStat('Avg. Power', '2.8 kW', Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
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
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSavingsCard(BuildContext context) {
    // Demo numbers; replace with API-driven values later
    const double baselineCost = 2200; // Rs baseline for period
    const double currentCost = 1850; // Rs current forecast
    final double savings = baselineCost - currentCost;
    final double savingsPct = (savings / baselineCost) * 100;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text(
                  'Rupee Savings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Projected Spend',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Rs 1,850',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Saved vs baseline',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rs ${savings.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${savingsPct.toStringAsFixed(1)}% lower',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (currentCost / baselineCost).clamp(0, 1),
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade400),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            const Text(
              'Baseline: Rs 2,200  •  Forecast: Rs 1,850  •  Savings: Rs 350',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTomorrowPredictionCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber[700]),
                const SizedBox(width: 8),
                const Text(
                  'AI-Powered Forecast',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Predicted Usage',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '26.3 kWh',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.trending_up,
                            size: 16, color: Colors.red[400]),
                        const SizedBox(width: 4),
                        Text(
                          '+6% from today',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[400],
                          ),
                        ),
                      ],
                    ),
                  ],
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
                    const SizedBox(height: 4),
                    const Text(
                      '\$7.24',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Peak hours expected: 6 PM - 10 PM',
                      style: TextStyle(
                        fontSize: 13,
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

  Widget _buildAnomaliesSection(BuildContext context) {
    return Column(
      children: [
        _buildAnomalyCard(
          'Air Conditioner',
          'Unusual high consumption detected',
          'High',
          Colors.red,
          Icons.ac_unit,
          '45% above normal',
        ),
        const SizedBox(height: 12),
        _buildAnomalyCard(
          'Refrigerator',
          'Temperature fluctuation detected',
          'Medium',
          Colors.orange,
          Icons.kitchen,
          '12% above normal',
        ),
        const SizedBox(height: 12),
        _buildAnomalyCard(
          'Water Heater',
          'Extended heating cycle',
          'Low',
          Colors.yellow[700]!,
          Icons.water_drop,
          '8% above normal',
        ),
      ],
    );
  }

  Widget _buildAnomalyCard(
    String device,
    String issue,
    String severity,
    Color severityColor,
    IconData icon,
    String impact,
  ) {
    return Card(
      elevation: 1,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: severityColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: severityColor, size: 24),
        ),
        title: Text(
          device,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(issue),
            const SizedBox(height: 4),
            Text(
              impact,
              style: TextStyle(
                fontSize: 12,
                color: severityColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: severityColor,
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
  }

  Widget _buildEnergySavingsCard(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.eco, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  'Optimization Opportunities',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSavingsInsight(
              'Reduce AC usage by 2°C',
              'Save up to \$1.20/day',
              Icons.ac_unit,
            ),
            const Divider(height: 24),
            _buildSavingsInsight(
              'Schedule water heater to off-peak',
              'Save up to \$0.80/day',
              Icons.water_drop,
            ),
            const Divider(height: 24),
            _buildSavingsInsight(
              'Enable smart standby mode',
              'Save up to \$0.50/day',
              Icons.power_settings_new,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Potential Savings',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '\$2.50/day',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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

  Widget _buildSavingsInsight(String title, String saving, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.green[700], size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                saving,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: Colors.grey[400]),
      ],
    );
  }

  Widget _buildDeviceUsageList(BuildContext context) {
    return Column(
      children: [
        _buildDeviceUsageItem(
          'Air Conditioner',
          '2.8 kW',
          Icons.ac_unit,
          Colors.blue,
          0.75,
          'High',
        ),
        const SizedBox(height: 12),
        _buildDeviceUsageItem(
          'Water Heater',
          '1.5 kW',
          Icons.water_drop,
          Colors.orange,
          0.45,
          'Medium',
        ),
        const SizedBox(height: 12),
        _buildDeviceUsageItem(
          'Refrigerator',
          '0.6 kW',
          Icons.kitchen,
          Colors.green,
          0.25,
          'Normal',
        ),
        const SizedBox(height: 12),
        _buildDeviceUsageItem(
          'Washing Machine',
          '0.4 kW',
          Icons.local_laundry_service,
          Colors.teal,
          0.15,
          'Low',
        ),
        const SizedBox(height: 12),
        _buildDeviceUsageItem(
          'Lighting',
          '0.3 kW',
          Icons.lightbulb,
          Colors.amber,
          0.10,
          'Low',
        ),
      ],
    );
  }

  Widget _buildDeviceUsageItem(
    String device,
    String power,
    IconData icon,
    Color color,
    double percentage,
    String status,
  ) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Current: $power',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: _getStatusColor(status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Normal':
        return Colors.green;
      case 'Low':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDeviceBehaviorCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Air Conditioner Usage Pattern',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBehaviorColumn(
                  'Normal',
                  '2.2 kWh',
                  Colors.green,
                  Icons.check_circle,
                ),
                Container(
                  height: 80,
                  width: 1,
                  color: Colors.grey[300],
                ),
                _buildBehaviorColumn(
                  'Current',
                  '3.2 kWh',
                  Colors.red,
                  Icons.trending_up,
                ),
                Container(
                  height: 80,
                  width: 1,
                  color: Colors.grey[300],
                ),
                _buildBehaviorColumn(
                  'Difference',
                  '+45%',
                  Colors.orange,
                  Icons.warning,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Device consuming 45% more than usual. Check for issues.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[900],
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

  Widget _buildBehaviorColumn(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
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
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

Widget _buildActivityCard(
  BuildContext context,
  String device,
  String status,
  IconData icon,
  Color color,
  String power,
) {
  return Card(
    elevation: 1,
    child: ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        device,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(status),
      trailing: Text(
        power,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}
