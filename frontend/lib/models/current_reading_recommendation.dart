import 'package:flutter/material.dart';
import 'energy_reading.dart';

/// User-understandable recommendation from current energy reading analysis.
/// Provides: advice (how to use devices), savings, waste estimate, and mitigation.
class CurrentReadingRecommendation {
  const CurrentReadingRecommendation({
    required this.title,
    required this.message,
    required this.severity,
    required this.icon,
    required this.color,
    this.estimatedSavingsKwhPerDay,
    this.energyWastedKwhPerDay,
    this.advice,
    this.mitigation,
  });

  final String title;
  final String message;
  final String severity;
  final IconData icon;
  final Color color;
  final double? estimatedSavingsKwhPerDay;
  /// Estimated energy currently being wasted (kWh per day) so user understands impact.
  final double? energyWastedKwhPerDay;
  /// Plain-language advice: how to use devices correctly.
  final String? advice;
  /// How to mitigate the issue.
  final String? mitigation;

  /// From API response (trained current energy recommendation model).
  static CurrentReadingRecommendation fromApiMap(Map<String, dynamic> map) {
    final severity = (map['severity'] as String?) ?? 'low';
    IconData icon;
    Color color;
    switch (severity.toLowerCase()) {
      case 'high':
        icon = Icons.power_off;
        color = Colors.red;
        break;
      case 'medium':
        icon = Icons.info_outline;
        color = Colors.orange;
        break;
      default:
        icon = Icons.eco;
        color = Colors.green;
    }
    return CurrentReadingRecommendation(
      title: (map['title'] as String?) ?? '',
      message: (map['message'] as String?) ?? '',
      severity: severity,
      icon: icon,
      color: color,
      estimatedSavingsKwhPerDay: (map['estimated_savings_kwh_per_day'] as num?)?.toDouble(),
      energyWastedKwhPerDay: (map['energy_wasted_kwh_per_day'] as num?)?.toDouble(),
      advice: map['advice'] as String?,
      mitigation: map['mitigation'] as String?,
    );
  }

  /// Build accurate, user-understandable recommendations from current readings and stats.
  static List<CurrentReadingRecommendation> fromReadingsAndStats({
    required List<EnergyReading> readings,
    Map<String, dynamic>? usageStats,
  }) {
    final List<CurrentReadingRecommendation> recs = [];
    if (readings.isEmpty) return recs;

    final EnergyReading latest = readings.first;
    final double currentA = latest.currentA;
    final double currentMa = latest.currentMa;
    final double powerW = currentA * 230.0;

    const double highPowerW = 800.0;
    const double mediumPowerW = 400.0;
    const double highCurrentA = 4.0;
    const double mediumCurrentA = 2.0;

    // --- High load: clear advice, waste, and mitigation ---
    if (powerW >= highPowerW || currentA >= highCurrentA) {
      final double wastedKwhDay = (powerW * 24) / 1000;
      final double savingsIfReduced = wastedKwhDay * 0.35; // ~35% reducible
      recs.add(CurrentReadingRecommendation(
        title: 'High power use — devices may be overloaded',
        message: 'Your circuit is drawing ${currentA.toStringAsFixed(2)} A (${powerW.toStringAsFixed(0)} W). This can overload wiring and increase bills.',
        severity: 'high',
        icon: Icons.power_off,
        color: Colors.red,
        estimatedSavingsKwhPerDay: savingsIfReduced,
        energyWastedKwhPerDay: wastedKwhDay,
        advice: 'Use devices one at a time where possible. Switch off AC, heaters, or heavy appliances when not needed. Do not plug too many high-wattage devices on the same circuit.',
        mitigation: 'Unplug unused appliances, turn off AC when leaving the room, and use power strips to switch off standby devices. Retake a reading after 30 minutes to see the drop.',
      ));
    } else if (powerW >= mediumPowerW || currentA >= mediumCurrentA) {
      final double wastedKwhDay = (powerW * 24) / 1000;
      recs.add(CurrentReadingRecommendation(
        title: 'Moderate load — room for improvement',
        message: 'Current draw is ${currentA.toStringAsFixed(2)} A (${powerW.toStringAsFixed(0)} W). You can save energy by turning off devices you are not using.',
        severity: 'medium',
        icon: Icons.info_outline,
        color: Colors.orange,
        estimatedSavingsKwhPerDay: wastedKwhDay * 0.2,
        energyWastedKwhPerDay: wastedKwhDay * 0.15,
        advice: 'Turn off lights and fans when leaving the room. Unplug chargers and set-top boxes when not in use. Use sleep mode on computers and monitors.',
        mitigation: 'Identify which appliance uses the most (e.g. AC, heater) and reduce its usage or set a timer. Check the reading again after making changes.',
      ));
    }

    if (usageStats != null) {
      final trend = usageStats['trend'] as Map<String, dynamic>?;
      if (trend != null) {
        final direction = trend['direction'] as String? ?? 'stable';
        final percentChange = (trend['percent_change'] as num?)?.toDouble() ?? 0.0;
        if (direction == 'rising' && percentChange > 10 && powerW > 100) {
          final double extraKwh = (powerW * (percentChange / 100) * 24) / 1000;
          recs.add(CurrentReadingRecommendation(
            title: 'Consumption is rising',
            message: 'Usage has gone up by ${percentChange.toStringAsFixed(1)}% recently. This usually means new devices are on or something was left running.',
            severity: 'medium',
            icon: Icons.trending_up,
            color: Colors.orange,
            energyWastedKwhPerDay: extraKwh,
            advice: 'Check for devices that were recently turned on or left on (AC, heater, water heater, extra lights). Compare with your usual usage pattern.',
            mitigation: 'Switch off or unplug any device you are not using right now. If the rise continues, list all connected devices and turn them off one by one while watching the reading to find the main consumer.',
          ));
        }
      }

      final signal = usageStats['signal'] as Map<String, dynamic>?;
      if (signal != null) {
        final quality = signal['quality'] as String?;
        if (quality == 'weak') {
          recs.add(CurrentReadingRecommendation(
            title: 'Weak WiFi signal',
            message: 'The monitoring device has a weak WiFi signal. Readings may be delayed or missing.',
            severity: 'low',
            icon: Icons.signal_wifi_off,
            color: Colors.blue,
            advice: 'Keep the energy monitor within range of your router. Avoid thick walls or metal between the device and the router.',
            mitigation: 'Move the device closer to the router or add a WiFi extender. This does not reduce energy use but ensures accurate data.',
          ));
        }
      }
    }

    if (powerW < mediumPowerW && powerW > 0 && recs.every((r) => r.severity != 'low')) {
      recs.add(CurrentReadingRecommendation(
        title: 'Efficient usage',
        message: 'Current consumption (${powerW.toStringAsFixed(0)} W) is in a good range. Keep up the good habits.',
        severity: 'low',
        icon: Icons.eco,
        color: Colors.green,
        advice: 'Continue turning off devices when not in use and using efficient settings on AC and appliances.',
        mitigation: 'No action needed. Keep monitoring to catch any sudden increases.',
      ));
    }

    return recs;
  }
}
