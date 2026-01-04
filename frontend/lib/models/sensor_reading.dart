class SensorReading {
  const SensorReading({
    required this.module,
    required this.location,
    required this.rcwl,
    required this.pir,
    this.peopleCount,
    required this.temperature,
    required this.humidity,
    required this.receivedAt,
    this.rssi,
    this.uptime,
    this.heap,
    this.ip,
    this.mac,
    this.source,
  });

  final String module;
  final String location;
  final int rcwl;
  final int pir;
  final int? peopleCount;
  final double temperature;
  final double humidity;
  final DateTime receivedAt;
  final int? rssi;
  final int? uptime;
  final int? heap;
  final String? ip;
  final String? mac;
  final String? source;

  bool get occupied => rcwl == 1 || pir == 1;

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    DateTime parsedTimestamp = DateTime.now().toUtc();
    final String? tsString = json['received_at'] as String? ??
        json['receivedAt'] as String? ??
        json['timestamp'] as String?;
    if (tsString != null) {
      final DateTime? parsed = DateTime.tryParse(tsString);
      if (parsed != null) {
        parsedTimestamp = parsed.toUtc();
      }
    }

    return SensorReading(
      module: (json['module'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      rcwl: (json['rcwl'] as num?)?.toInt() ?? 0,
      pir: (json['pir'] as num?)?.toInt() ?? 0,
      peopleCount: (json['people_count'] as num?)?.toInt() ??
          (json['people'] as num?)?.toInt() ??
          (json['count'] as num?)?.toInt(),
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      humidity: (json['humidity'] as num?)?.toDouble() ?? 0,
      receivedAt: parsedTimestamp,
      rssi: (json['rssi'] as num?)?.toInt(),
      uptime: (json['uptime'] as num?)?.toInt(),
      heap: (json['heap'] as num?)?.toInt(),
      ip: json['ip'] as String?,
      mac: json['mac'] as String?,
      source: json['source'] as String?,
    );
  }
}
