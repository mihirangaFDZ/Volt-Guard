import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volt_guard/providers/theme_provider.dart';

/// Dashboard page showing real-time energy usage, predictions, and alerts
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Energy Dashboard'),
        actions: [
          // Dark mode toggle
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return IconButton(
                tooltip: ThemeProvider.labelFor(themeProvider.themeMode),
                icon: Icon(ThemeProvider.iconFor(themeProvider.themeMode)),
                onPressed: () {
                  final next = switch (themeProvider.themeMode) {
                    ThemeMode.system => ThemeMode.light,
                    ThemeMode.light => ThemeMode.dark,
                    ThemeMode.dark => ThemeMode.system,
                  };
                  themeProvider.setThemeMode(next);
                },
              );
            },
          ),
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
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
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
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bolt,
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildQuickStat(
                    context, 'Estimated Cost', '\$6.82', Colors.green),
                Container(
                  height: 40,
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                _buildQuickStat(context, 'Peak Hour', '7-9 PM', Colors.orange),
                Container(
                  height: 40,
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                _buildQuickStat(context, 'Avg. Power', '2.8 kW', Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(
      BuildContext context, String label, String value, Color color) {
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
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
                Icon(Icons.lightbulb_outline,
                    color: Theme.of(context).colorScheme.tertiary),
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
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
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
                            size: 16,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 4),
                        Text(
                          '+6% from today',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
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
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
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
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Peak hours expected: 6 PM - 10 PM',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer,
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
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.eco,
                    color: Theme.of(context).colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Optimization Opportunities',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSavingsInsight(
              context,
              'Reduce AC usage by 2°C',
              'Save up to \$1.20/day',
              Icons.ac_unit,
            ),
            const Divider(height: 24),
            _buildSavingsInsight(
              context,
              'Schedule water heater to off-peak',
              'Save up to \$0.80/day',
              Icons.water_drop,
            ),
            const Divider(height: 24),
            _buildSavingsInsight(
              context,
              'Enable smart standby mode',
              'Save up to \$0.50/day',
              Icons.power_settings_new,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Potential Savings',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '\$2.50/day',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondary,
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

  Widget _buildSavingsInsight(
      BuildContext context, String title, String saving, IconData icon) {
    return Row(
      children: [
        Icon(icon,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
            size: 20),
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
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right,
            color: Theme.of(context).colorScheme.outlineVariant),
      ],
    );
  }

  Widget _buildDeviceUsageList(BuildContext context) {
    return Column(
      children: [
        _buildDeviceUsageItem(
          context,
          'Air Conditioner',
          '2.8 kW',
          Icons.ac_unit,
          Colors.blue,
          0.75,
          'High',
        ),
        const SizedBox(height: 12),
        _buildDeviceUsageItem(
          context,
          'Water Heater',
          '1.5 kW',
          Icons.water_drop,
          Colors.orange,
          0.45,
          'Medium',
        ),
        const SizedBox(height: 12),
        _buildDeviceUsageItem(
          context,
          'Refrigerator',
          '0.6 kW',
          Icons.kitchen,
          Colors.green,
          0.25,
          'Normal',
        ),
        const SizedBox(height: 12),
        _buildDeviceUsageItem(
          context,
          'Washing Machine',
          '0.4 kW',
          Icons.local_laundry_service,
          Colors.teal,
          0.15,
          'Low',
        ),
        const SizedBox(height: 12),
        _buildDeviceUsageItem(
          context,
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
    BuildContext context,
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
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
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
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  context,
                  'Normal',
                  '2.2 kWh',
                  Colors.green,
                  Icons.check_circle,
                ),
                Container(
                  height: 80,
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                _buildBehaviorColumn(
                  context,
                  'Current',
                  '3.2 kWh',
                  Colors.red,
                  Icons.trending_up,
                ),
                Container(
                  height: 80,
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                _buildBehaviorColumn(
                  context,
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
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Device consuming 45% more than usual. Check for issues.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
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
    BuildContext context,
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
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}
