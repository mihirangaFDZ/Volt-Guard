class EnergyReading {
  const EnergyReading({
    required this.module,
    required this.location,
    required this.sensor,
    required this.currentMa,
    required this.currentA,
    this.rmsA,
    this.adcSamples,
    this.vref,
    this.wifiRssi,
    required this.receivedAt,
    this.source,
    this.type,
  });

  final String module;
  final String location;
  final String sensor;
  final double currentMa;
  final double currentA;
  final double? rmsA;
  final int? adcSamples;
  final double? vref;
  final int? wifiRssi;
  final DateTime receivedAt;
  final String? source;
  final String? type;

  factory EnergyReading.fromJson(Map<String, dynamic> json) {
    DateTime parsedTimestamp = DateTime.now().toUtc();
    // API returns received_at in UTC; parse and keep as UTC (Sri Lanka display handled in UI)
    final String? tsString =
        json['received_at'] as String? ?? json['receivedAt'] as String?;
    if (tsString != null) {
      // If no timezone in string, treat as UTC (backend sends UTC; ISO without Z is ambiguous in Dart)
      final String normalized =
          tsString.trim().endsWith('Z') ||
                  RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(tsString)
              ? tsString
              : '${tsString.trim()}Z';
      final DateTime? parsed = DateTime.tryParse(normalized);
      if (parsed != null) {
        parsedTimestamp = parsed.toUtc();
      }
    }

    return EnergyReading(
      module: (json['module'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      sensor: (json['sensor'] ?? '').toString(),
      currentMa: (json['current_ma'] as num?)?.toDouble() ?? 0.0,
      currentA: (json['current_a'] as num?)?.toDouble() ?? 0.0,
      rmsA: (json['rms_a'] as num?)?.toDouble(),
      adcSamples: (json['adc_samples'] as num?)?.toInt(),
      vref: (json['vref'] as num?)?.toDouble(),
      wifiRssi: (json['wifi_rssi'] as num?)?.toInt(),
      receivedAt: parsedTimestamp,
      source: json['source'] as String?,
      type: json['type'] as String?,
    );
  }
}

