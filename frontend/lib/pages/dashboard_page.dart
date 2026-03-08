import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volt_guard/providers/theme_provider.dart';
import 'package:volt_guard/services/dashboard_service.dart';
import 'package:volt_guard/pages/anomalies_page.dart';
import 'package:volt_guard/pages/notifications_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;
  String? _error;

  Map<String, dynamic> _todayEnergy = {};
  Map<String, dynamic> _prediction = {};
  List<dynamic> _anomalies = [];
  List<dynamic> _recommendations = [];
  List<dynamic> _devices = [];
  Map<String, dynamic>? _topDevice;
  String? _selectedDeviceId;

  // Chart & savings state
  String _chartPeriod = 'day';
  bool _isChartLoading = false;
  Map<String, dynamic> _chartData = {};
  Map<String, dynamic> _savingsData = {};

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await DashboardService.getSummary();
      setState(() {
        _todayEnergy = data['today_energy'] as Map<String, dynamic>? ?? {};
        _prediction = data['prediction'] as Map<String, dynamic>? ?? {};
        _anomalies = data['anomalies'] as List<dynamic>? ?? [];
        _recommendations = data['recommendations'] as List<dynamic>? ?? [];
        _devices = data['devices'] as List<dynamic>? ?? [];
        _topDevice = data['top_anomaly_device'] as Map<String, dynamic>?;
        _isLoading = false;
      });
      _loadChartData();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadChartData() async {
    setState(() => _isChartLoading = true);
    try {
      final results = await Future.wait([
        DashboardService.getEnergyChart(_chartPeriod),
        DashboardService.getSavings(_chartPeriod),
      ]);
      setState(() {
        _chartData = results[0];
        _savingsData = results[1];
        _isChartLoading = false;
      });
    } catch (_) {
      setState(() => _isChartLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Energy Dashboard'),
        actions: [
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
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          NotificationsPage(anomalies: _anomalies),
                    ),
                  );
                },
              ),
              if (_anomalies.isNotEmpty)
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
                      '${_anomalies.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
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
              Text('Failed to load dashboard',
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
                onPressed: _loadDashboard,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, 'Today\'s Energy'),
            const SizedBox(height: 12),
            _buildTodayEnergyCard(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Tomorrow\'s Prediction'),
            const SizedBox(height: 12),
            _buildTomorrowPredictionCard(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Active Anomalies'),
            const SizedBox(height: 12),
            _buildAnomaliesSection(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Energy Consumption'),
            const SizedBox(height: 12),
            _buildEnergyChartSection(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Energy Savings'),
            const SizedBox(height: 12),
            _buildSavingsCard(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Device Power Distribution'),
            const SizedBox(height: 12),
            _buildDeviceDistributionChart(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Recommendations'),
            const SizedBox(height: 12),
            _buildRecommendationsCard(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Real-Time Device Usage'),
            const SizedBox(height: 12),
            _buildDeviceUsageList(context),
            if (_topDevice != null) ...[
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Device Behavior Comparison'),
              const SizedBox(height: 12),
              _buildDeviceBehaviorCard(context),
            ],
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  String _formatPower(double watts) {
    if (watts >= 1000) {
      return '${(watts / 1000).toStringAsFixed(1)} kW';
    }
    return '${watts.toStringAsFixed(0)} W';
  }

  String _convertUtcHourRangeToSriLanka(String value) {
    if (value.trim().isEmpty || value == 'N/A') return value;

    final regex = RegExp(
      r'^\s*(\d{1,2})\s*(AM|PM)\s*-\s*(\d{1,2})\s*(AM|PM)\s*$',
      caseSensitive: false,
    );
    final match = regex.firstMatch(value);
    if (match == null) return value;

    int toMinutes(String hourText, String amPmText) {
      int hour = int.tryParse(hourText) ?? 0;
      final amPm = amPmText.toUpperCase();
      if (hour == 12) {
        hour = 0;
      }
      if (amPm == 'PM') {
        hour += 12;
      }
      return hour * 60;
    }

    String to12HourLabel(int totalMinutes) {
      final normalized = ((totalMinutes % 1440) + 1440) % 1440;
      final hour24 = normalized ~/ 60;
      final minute = normalized % 60;
      final isPm = hour24 >= 12;
      final hour12Raw = hour24 % 12;
      final hour12 = hour12Raw == 0 ? 12 : hour12Raw;
      final amPm = isPm ? 'PM' : 'AM';

      if (minute == 0) {
        return '$hour12 $amPm';
      }
      return '$hour12:${minute.toString().padLeft(2, '0')} $amPm';
    }

    final startUtcMins = toMinutes(match.group(1)!, match.group(2)!);
    final endUtcMins = toMinutes(match.group(3)!, match.group(4)!);

    const sriLankaOffsetMinutes = 5 * 60 + 30;
    final startLkMins = startUtcMins + sriLankaOffsetMinutes;
    final endLkMins = endUtcMins + sriLankaOffsetMinutes;

    return '${to12HourLabel(startLkMins)} - ${to12HourLabel(endLkMins)}';
  }

  double _calculateTariffCostLkr(double kwh, {double billingDays = 30}) {
    if (kwh <= 0 || billingDays <= 0) return 0.0;

    final factor = billingDays / 30.0;

    // Domestic low users (<= 60 units/month, prorated by billing days)
    final low30Limit = 30.0 * factor;
    final low60Limit = 60.0 * factor;

    if (kwh <= low60Limit) {
      final units0to30 = min(kwh, low30Limit);
      final units31to60 = max(kwh - low30Limit, 0.0);

      final energyCost = (units0to30 * 4.50) + (units31to60 * 8.00);
      final fixedCharge = (kwh <= low30Limit ? 80.0 : 210.0) * factor;
      return energyCost + fixedCharge;
    }

    // Domestic users > 60 units/month (prorated blocks)
    double remaining = kwh;
    double energyCost = 0.0;

    final highBlocks = <(double, double)>[
      (60.0 * factor, 12.75),
      (30.0 * factor, 18.50),
      (30.0 * factor, 24.00),
      (60.0 * factor, 41.00),
    ];

    for (final (blockSize, rate) in highBlocks) {
      if (remaining <= 0) break;
      final units = min(remaining, blockSize);
      energyCost += units * rate;
      remaining -= units;
    }

    if (remaining > 0) {
      energyCost += remaining * 61.00;
    }

    final high60Limit = 60.0 * factor;
    final high90Limit = 90.0 * factor;
    final high180Limit = 180.0 * factor;
    final fixedCharge = kwh <= high60Limit
        ? 0.0 * factor
        : kwh <= high90Limit
            ? 400.0 * factor
            : kwh <= high180Limit
                ? (kwh <= 120.0 * factor ? 1000.0 * factor : 1500.0 * factor)
                : 2100.0 * factor;

    return energyCost + fixedCharge;
  }

  String _simpleTariffCalculation(double kwh, {double billingDays = 30}) {
    if (kwh <= 0 || billingDays <= 0) {
      return 'For 0.00 kWh\nEnergy: Rs. 0.00\nFixed: Rs. 0.00\nTotal Bill: Rs. 0.00';
    }

    final factor = billingDays / 30.0;
    final low30Limit = 30.0 * factor;
    final low60Limit = 60.0 * factor;

    double energyCost = 0.0;
    double fixedCharge = 0.0;
    double fixedBase = 0.0;
    final energyTerms = <String>[];

    if (kwh <= low60Limit) {
      final units0to30 = min(kwh, low30Limit);
      final units31to60 = max(kwh - low30Limit, 0.0);

      if (units0to30 > 0) {
        energyTerms.add('${units0to30.toStringAsFixed(2)}×4.50');
      }
      if (units31to60 > 0) {
        energyTerms.add('${units31to60.toStringAsFixed(2)}×8.00');
      }

      energyCost = (units0to30 * 4.50) + (units31to60 * 8.00);
      fixedBase = kwh <= low30Limit ? 80.0 : 210.0;
      fixedCharge = fixedBase * factor;
    } else {
      double remaining = kwh;
      final b1 = min(remaining, 60.0 * factor);
      energyCost += b1 * 12.75;
      if (b1 > 0) {
        energyTerms.add('${b1.toStringAsFixed(2)}×12.75');
      }
      remaining -= b1;

      final b2 = min(max(remaining, 0.0), 30.0 * factor);
      energyCost += b2 * 18.50;
      if (b2 > 0) {
        energyTerms.add('${b2.toStringAsFixed(2)}×18.50');
      }
      remaining -= b2;

      final b3 = min(max(remaining, 0.0), 30.0 * factor);
      energyCost += b3 * 24.00;
      if (b3 > 0) {
        energyTerms.add('${b3.toStringAsFixed(2)}×24.00');
      }
      remaining -= b3;

      final b4 = min(max(remaining, 0.0), 60.0 * factor);
      energyCost += b4 * 41.00;
      if (b4 > 0) {
        energyTerms.add('${b4.toStringAsFixed(2)}×41.00');
      }
      remaining -= b4;

      if (remaining > 0) {
        energyCost += remaining * 61.00;
        energyTerms.add('${remaining.toStringAsFixed(2)}×61.00');
      }

      if (kwh <= 90.0 * factor) {
        fixedBase = 400.0;
      } else if (kwh <= 120.0 * factor) {
        fixedBase = 1000.0;
      } else if (kwh <= 180.0 * factor) {
        fixedBase = 1500.0;
      } else {
        fixedBase = 2100.0;
      }

      fixedCharge = fixedBase * factor;
    }

    final total = energyCost + fixedCharge;
    final energyExpr =
        energyTerms.isNotEmpty ? energyTerms.join(' + ') : '0.00';

    return 'For ${kwh.toStringAsFixed(2)} kWh\n'
        'Energy: $energyExpr = Rs. ${energyCost.toStringAsFixed(2)}\n'
        'Fixed: Rs. ${fixedBase.toStringAsFixed(0)} × (${billingDays.toStringAsFixed(0)}/30) = Rs. ${fixedCharge.toStringAsFixed(2)}\n'
        'Total Bill: Rs. ${total.toStringAsFixed(2)}';
  }

  String _tariffTierLabel(double kwh, {double billingDays = 30}) {
    final factor = billingDays > 0 ? (billingDays / 30.0) : 1.0;

    if (kwh <= 30.0 * factor) return '0-30';
    if (kwh <= 60.0 * factor) return '31-60';
    if (kwh <= 90.0 * factor) return '61-90';
    if (kwh <= 120.0 * factor) return '91-120';
    if (kwh <= 180.0 * factor) return '121-180';
    return '>180';
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

  Color _deviceColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'ac':
      case 'air conditioner':
        return Colors.blue;
      case 'refrigerator':
      case 'fridge':
        return Colors.green;
      case 'water heater':
      case 'heater':
        return Colors.orange;
      case 'washing machine':
        return Colors.teal;
      case 'light':
      case 'lighting':
        return Colors.amber;
      case 'fan':
        return Colors.cyan;
      default:
        return Colors.purple;
    }
  }

  Color _statusColor(String status) {
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

  // ── Today's Energy Card ──────────────────────────────────────────────

  Widget _buildTodayEnergyCard(BuildContext context) {
    final totalKwh = (_todayEnergy['total_kwh'] as num?)?.toDouble() ?? 0.0;
    final cost = _calculateTariffCostLkr(totalKwh, billingDays: 1);
    final peakHourUtc = _todayEnergy['peak_hour'] as String? ?? 'N/A';
    final peakHour = _convertUtcHourRangeToSriLanka(peakHourUtc);
    final avgPower = (_todayEnergy['avg_power_w'] as num?)?.toDouble() ?? 0.0;
    final billFormula = _simpleTariffCalculation(totalKwh, billingDays: 1);

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
                    Text(
                      '${totalKwh.toStringAsFixed(2)} kWh',
                      style: const TextStyle(
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
                  context,
                  'Estimated Cost',
                  'Rs. ${cost.toStringAsFixed(2)}',
                  Colors.green,
                ),
                Container(
                  height: 40,
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                _buildQuickStat(
                  context,
                  'Peak Hour',
                  peakHour,
                  Colors.orange,
                  flex: 1,
                  valueFontSize: 17,
                  valueMaxLines: 2,
                ),
                Container(
                  height: 40,
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                _buildQuickStat(
                  context,
                  'Avg. Power',
                  _formatPower(avgPower),
                  Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                billFormula,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(
    BuildContext context,
    String label,
    String value,
    Color color, {
    int flex = 1,
    double valueFontSize = 18,
    int valueMaxLines = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: valueMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: valueFontSize,
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

  // ── Tomorrow's Prediction Card ───────────────────────────────────────

  Widget _buildTomorrowPredictionCard(BuildContext context) {
    final predictedKwh =
        (_prediction['total_predicted_kwh'] as num?)?.toDouble() ?? 0.0;
    final cost = _calculateTariffCostLkr(predictedKwh, billingDays: 1);
    final changePercent =
        (_prediction['change_percent'] as num?)?.toDouble() ?? 0.0;
    final confidence =
        (_prediction['avg_confidence'] as num?)?.toDouble() ?? 0.0;

    final isIncrease = changePercent > 0;
    final changeColor =
        isIncrease ? Theme.of(context).colorScheme.error : Colors.green;
    final changeIcon = isIncrease ? Icons.trending_up : Icons.trending_down;
    final changeText = isIncrease
        ? '+${changePercent.toStringAsFixed(1)}% from today'
        : '${changePercent.toStringAsFixed(1)}% from today';

    if (predictedKwh == 0 && confidence == 0) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  color: Theme.of(context).colorScheme.tertiary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('No predictions available yet.'),
              ),
            ],
          ),
        ),
      );
    }

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
                    Text(
                      '${predictedKwh.toStringAsFixed(1)} kWh',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(changeIcon, size: 16, color: changeColor),
                        const SizedBox(width: 4),
                        Text(
                          changeText,
                          style: TextStyle(
                            fontSize: 12,
                            color: changeColor,
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
                    Text(
                      'Rs. ${cost.toStringAsFixed(2)}',
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
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

  // ── Active Anomalies ─────────────────────────────────────────────────

  Widget _buildAnomaliesSection(BuildContext context) {
    final count = _anomalies.length;

    // Count by severity
    int high = 0, medium = 0, low = 0;
    for (final a in _anomalies) {
      final map = a as Map<String, dynamic>;
      switch ((map['severity'] as String? ?? '').toLowerCase()) {
        case 'critical':
        case 'high':
          high++;
          break;
        case 'medium':
          medium++;
          break;
        default:
          low++;
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AnomaliesPage()),
        );
      },
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: count > 0
                      ? Colors.red.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  count > 0 ? Icons.warning_amber_rounded : Icons.check_circle,
                  color: count > 0 ? Colors.red : Colors.green,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0
                          ? 'No Active Anomalies'
                          : '$count Active Anomal${count == 1 ? 'y' : 'ies'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (high > 0)
                            _buildSeverityChip('High', high, Colors.red),
                          if (high > 0 && medium > 0) const SizedBox(width: 8),
                          if (medium > 0)
                            _buildSeverityChip('Medium', medium, Colors.orange),
                          if ((high > 0 || medium > 0) && low > 0)
                            const SizedBox(width: 8),
                          if (low > 0)
                            _buildSeverityChip(
                                'Low', low, Colors.yellow.shade700),
                        ],
                      ),
                    ] else
                      Text(
                        'All devices operating normally.',
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
              Icon(Icons.chevron_right,
                  color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeverityChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Energy Consumption Chart (Gradient Area) ────────────────────────

  Widget _buildEnergyChartSection(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.show_chart,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Consumption',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Period chips
                Container(
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: ['day', 'week', 'month'].map((p) {
                      final selected = _chartPeriod == p;
                      final label =
                          p[0].toUpperCase() + p.substring(1); // Day/Week/Month
                      return GestureDetector(
                        onTap: () {
                          setState(() => _chartPeriod = p);
                          _loadChartData();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.6),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Chart
            _isChartLoading
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _buildAreaChart(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaChart(BuildContext context) {
    final points = _chartData['points'] as List<dynamic>? ?? [];
    if (points.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No data available for this period.')),
      );
    }

    final totalActual =
        (_chartData['total_actual_kwh'] as num?)?.toDouble() ?? 0.0;
    final totalBaseline =
        (_chartData['total_baseline_kwh'] as num?)?.toDouble() ?? 0.0;

    // Build spots
    final actualSpots = <FlSpot>[];
    final baselineSpots = <FlSpot>[];
    double maxY = 0;
    for (int i = 0; i < points.length; i++) {
      final p = points[i] as Map<String, dynamic>;
      final actual = (p['actual_kwh'] as num?)?.toDouble() ?? 0.0;
      final baseline = (p['baseline_kwh'] as num?)?.toDouble() ?? 0.0;
      maxY = max(maxY, max(actual, baseline));
      actualSpots.add(FlSpot(i.toDouble(), actual));
      baselineSpots.add(FlSpot(i.toDouble(), baseline));
    }
    maxY = maxY > 0 ? maxY * 1.25 : 1.0;

    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // Summary chips
        Row(
          children: [
            _buildChartSummaryChip(
              context,
              'Actual',
              '${totalActual.toStringAsFixed(2)} kWh',
              primaryColor,
            ),
            const SizedBox(width: 8),
            _buildChartSummaryChip(
              context,
              'Baseline',
              '${totalBaseline.toStringAsFixed(2)} kWh',
              Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              maxY: maxY,
              minY: 0,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withOpacity(0.3),
                  strokeWidth: 1,
                  dashArray: [5, 5],
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.max || value == meta.min) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        value.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= points.length) {
                        return const SizedBox.shrink();
                      }
                      final step = _chartPeriod == 'day'
                          ? 4
                          : (_chartPeriod == 'month' ? 5 : 1);
                      if (idx % step != 0) return const SizedBox.shrink();
                      final p = points[idx] as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          p['label'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 9,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipRoundedRadius: 12,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final isActual = spot.barIndex == 0;
                      return LineTooltipItem(
                        '${isActual ? "Actual" : "Baseline"}\n${spot.y.toStringAsFixed(3)} kWh',
                        TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      );
                    }).toList();
                  },
                ),
                handleBuiltInTouches: true,
              ),
              lineBarsData: [
                // Actual — gradient area
                LineChartBarData(
                  spots: actualSpots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: primaryColor,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: _chartPeriod != 'day',
                    getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                      radius: 3,
                      color: primaryColor,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        primaryColor.withOpacity(0.3),
                        primaryColor.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
                // Baseline — dashed line
                LineChartBarData(
                  spots: baselineSpots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: Colors.orange.shade400,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dashArray: [8, 4],
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartSummaryChip(
      BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5))),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Energy Savings Card (with radial gauge) ─────────────────────────

  Widget _buildSavingsCard(BuildContext context) {
    if (_isChartLoading) {
      return const Card(
        elevation: 2,
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final baselineKwh =
        (_savingsData['baseline_kwh'] as num?)?.toDouble() ?? 0.0;
    final actualKwh = (_savingsData['actual_kwh'] as num?)?.toDouble() ?? 0.0;
    final days = (_savingsData['days'] as num?)?.toDouble() ??
        (_chartPeriod == 'week'
            ? 7.0
            : _chartPeriod == 'month'
                ? 30.0
                : 1.0);
    final savedKwh = (_savingsData['saved_kwh'] as num?)?.toDouble() ??
        max(baselineKwh - actualKwh, 0.0);
    final savingsPct =
        (_savingsData['savings_percent'] as num?)?.toDouble() ?? 0.0;
    final baselineLkr = _calculateTariffCostLkr(baselineKwh, billingDays: days);
    final actualLkr = _calculateTariffCostLkr(actualKwh, billingDays: days);
    final savedLkr = max(baselineLkr - actualLkr, 0.0);
    final tariffTier = _tariffTierLabel(actualKwh, billingDays: days);

    final hasSavings = savedKwh > 0;
    final gaugeColor = hasSavings ? Colors.green : Colors.orange;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Radial gauge + money saved
            Row(
              children: [
                // Gauge
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 110,
                        height: 110,
                        child: CircularProgressIndicator(
                          value: (savingsPct / 100).clamp(0.0, 1.0),
                          strokeWidth: 10,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${savingsPct.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: gaugeColor,
                            ),
                          ),
                          Text(
                            'saved',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // Savings details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasSavings ? 'Great job!' : 'Savings Overview',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSavingsRow(
                        context,
                        Icons.bolt,
                        'Energy saved',
                        '${savedKwh.toStringAsFixed(2)} kWh',
                        gaugeColor,
                      ),
                      const SizedBox(height: 8),
                      _buildSavingsRow(
                        context,
                        Icons.account_balance_wallet,
                        'Money saved',
                        'Rs. ${savedLkr.toStringAsFixed(0)}',
                        gaugeColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Baseline vs actual horizontal bar comparison
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildComparisonBar(
                    context,
                    'Without Volt Guard',
                    baselineKwh,
                    baselineKwh,
                    Colors.red.shade400,
                    'Rs. ${baselineLkr.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 12),
                  _buildComparisonBar(
                    context,
                    'With Volt Guard',
                    actualKwh,
                    baselineKwh,
                    Colors.green,
                    'Rs. ${actualLkr.toStringAsFixed(0)}',
                  ),
                ],
              ),
            ),
            if (tariffTier.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long,
                        size: 16,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      'CEB Tariff Tier: $tariffTier units/month',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            Theme.of(context).colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSavingsRow(BuildContext context, IconData icon, String label,
      String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildComparisonBar(BuildContext context, String label, double value,
      double maxVal, Color color, String costLabel) {
    final pct = maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7))),
            Text(costLabel,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            FractionallySizedBox(
              widthFactor: pct,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.7), color],
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text('${value.toStringAsFixed(2)} kWh',
            style: TextStyle(
                fontSize: 10,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.4))),
      ],
    );
  }

  // ── Device Power Distribution (Donut Chart) ─────────────────────────

  static const List<Color> _donutColors = [
    Color(0xFF2196F3), // blue
    Color(0xFF4CAF50), // green
    Color(0xFFFF9800), // orange
    Color(0xFF9C27B0), // purple
    Color(0xFF00BCD4), // cyan
    Color(0xFFF44336), // red
    Color(0xFFFFEB3B), // yellow
    Color(0xFF795548), // brown
  ];

  Widget _buildDeviceDistributionChart(BuildContext context) {
    // Filter devices with power > 0
    final activeDevices = _devices
        .map((d) => d as Map<String, dynamic>)
        .where((d) => ((d['current_power_w'] as num?)?.toDouble() ?? 0.0) > 0)
        .toList();

    if (activeDevices.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: SizedBox(
            height: 80,
            child: Center(child: Text('No active devices to display.')),
          ),
        ),
      );
    }

    final totalPower = activeDevices.fold<double>(
        0, (sum, d) => sum + ((d['current_power_w'] as num?)?.toDouble() ?? 0));

    // Build pie sections
    final sections = <PieChartSectionData>[];
    for (int i = 0; i < activeDevices.length; i++) {
      final d = activeDevices[i];
      final power = (d['current_power_w'] as num?)?.toDouble() ?? 0.0;
      final pct = totalPower > 0 ? (power / totalPower * 100) : 0.0;
      final color = _donutColors[i % _donutColors.length];
      sections.add(
        PieChartSectionData(
          value: power,
          color: color,
          radius: 28,
          title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Donut
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 38,
                      sectionsSpace: 2,
                      startDegreeOffset: -90,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatPower(totalPower),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Legend
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                  activeDevices.length > 5 ? 5 : activeDevices.length,
                  (i) {
                    final d = activeDevices[i];
                    final name = d['device_name'] as String? ?? 'Unknown';
                    final power =
                        (d['current_power_w'] as num?)?.toDouble() ?? 0.0;
                    final color = _donutColors[i % _donutColors.length];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _formatPower(power),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recommendations ──────────────────────────────────────────────────

  Widget _buildRecommendationsCard(BuildContext context) {
    if (_recommendations.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.eco, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'No recommendations at this time.',
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
            ...List.generate(_recommendations.length, (i) {
              final rec = _recommendations[i] as Map<String, dynamic>;
              final title = rec['title'] as String? ?? '';
              final detail = rec['detail'] as String? ?? '';
              final severity = rec['severity'] as String? ?? 'low';

              IconData icon;
              switch (severity) {
                case 'high':
                  icon = Icons.warning_amber;
                  break;
                case 'medium':
                  icon = Icons.info_outline;
                  break;
                default:
                  icon = Icons.lightbulb_outline;
              }

              return Column(
                children: [
                  if (i > 0) const Divider(height: 24),
                  _buildRecommendationRow(context, title, detail, icon),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationRow(
      BuildContext context, String title, String detail, IconData icon) {
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
                detail,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
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

  // ── Real-Time Device Usage ───────────────────────────────────────────

  Widget _buildDeviceUsageList(BuildContext context) {
    if (_devices.isEmpty) {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.devices,
                  color: Theme.of(context).colorScheme.outline, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'No devices registered.',
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Find selected device map (or null)
    Map<String, dynamic>? selected;
    if (_selectedDeviceId != null) {
      for (final d in _devices) {
        final map = d as Map<String, dynamic>;
        if (map['device_id'] == _selectedDeviceId) {
          selected = map;
          break;
        }
      }
    }

    return Column(
      children: [
        // Dropdown selector
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDeviceId,
                isExpanded: true,
                hint: const Text('Select a device'),
                icon: const Icon(Icons.arrow_drop_down),
                items: _devices.map<DropdownMenuItem<String>>((d) {
                  final map = d as Map<String, dynamic>;
                  final id = map['device_id'] as String? ?? '';
                  final name = map['device_name'] as String? ?? 'Unknown';
                  final type = map['device_type'] as String? ?? '';
                  final status = map['status'] as String? ?? 'Off';
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Row(
                      children: [
                        Icon(_deviceIcon(type),
                            color: _deviceColor(type), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              color: _statusColor(status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDeviceId = value;
                  });
                },
              ),
            ),
          ),
        ),

        // Selected device detail card
        if (selected != null) ...[
          const SizedBox(height: 12),
          _buildDeviceUsageItem(
            context,
            selected['device_name'] as String? ?? 'Unknown',
            _formatPower(
                (selected['current_power_w'] as num?)?.toDouble() ?? 0.0),
            _deviceIcon(selected['device_type'] as String? ?? ''),
            _deviceColor(selected['device_type'] as String? ?? ''),
            (selected['usage_percentage'] as num?)?.toDouble() ?? 0.0,
            selected['status'] as String? ?? 'Off',
            selected['rated_power_watts'] as int? ?? 0,
            selected['location'] as String? ?? '',
          ),
        ],
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
    int ratedWatts,
    String location,
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
                    color: _statusColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: _statusColor(status),
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
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDeviceDetailChip(context, Icons.speed, 'Rated',
                    _formatPower(ratedWatts.toDouble())),
                _buildDeviceDetailChip(
                    context, Icons.location_on, 'Location', location),
                _buildDeviceDetailChip(context, Icons.pie_chart, 'Usage',
                    '${(percentage * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceDetailChip(
      BuildContext context, IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  // ── Device Behavior Comparison ───────────────────────────────────────

  Widget _buildDeviceBehaviorCard(BuildContext context) {
    if (_topDevice == null) return const SizedBox.shrink();

    final deviceName = _topDevice!['device_name'] as String? ?? 'Device';
    final ratedW = (_topDevice!['rated_power_w'] as num?)?.toDouble() ?? 0.0;
    final currentW =
        (_topDevice!['current_power_w'] as num?)?.toDouble() ?? 0.0;
    final diffPct =
        (_topDevice!['difference_percent'] as num?)?.toDouble() ?? 0.0;

    final isOverCapacity = currentW > ratedW;
    final diffColor = isOverCapacity ? Colors.red : Colors.green;
    final diffIcon = isOverCapacity ? Icons.warning : Icons.check_circle;
    final infoText = isOverCapacity
        ? 'Device consuming ${diffPct.toStringAsFixed(0)}% of rated capacity. Check for issues.'
        : 'Device operating at ${diffPct.toStringAsFixed(0)}% of rated capacity.';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$deviceName Usage Pattern',
              style: const TextStyle(
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
                  'Rated',
                  _formatPower(ratedW),
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
                  _formatPower(currentW),
                  isOverCapacity ? Colors.red : Colors.blue,
                  Icons.trending_up,
                ),
                Container(
                  height: 80,
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                _buildBehaviorColumn(
                  context,
                  'Usage',
                  '${diffPct.toStringAsFixed(0)}%',
                  diffColor,
                  diffIcon,
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
                      infoText,
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
