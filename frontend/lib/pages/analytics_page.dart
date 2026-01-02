import 'package:flutter/material.dart';

/// Component-focused analytics page for occupancy, comfort, sensor health, and recommendations
/// using the provided IoT fields (pir/rcwl, temperature, humidity, rssi, uptime, timestamps).
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final List<SensorReading> _readings = _sampleReadings;

  @override
  Widget build(BuildContext context) {
    final SensorReading latest = _readings.last;
    final _DerivedStats stats = _deriveStats(_readings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Occupancy & Comfort Analytics'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(milliseconds: 500));
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(latest, stats),
              const SizedBox(height: 16),
              _buildPeopleEstimate(stats),
              const SizedBox(height: 16),
              _buildComfortCard(stats),
              const SizedBox(height: 16),
              _buildSensorHealth(latest, stats),
              const SizedBox(height: 16),
              _buildRecommendations(stats),
              const SizedBox(height: 16),
              _buildRecentReadings(_readings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(SensorReading latest, _DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  stats.isOccupied ? Icons.sensor_occupied : Icons.sensor_door,
                  color: stats.isOccupied ? Colors.green : Colors.amber,
                ),
                const SizedBox(width: 8),
                Text(
                  stats.isOccupied ? 'Occupied' : 'Vacant',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'Last seen: ${_friendlyTime(latest.receivedAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('${latest.location} • ${latest.module}'),
                _pill('Vacancy: ${stats.vacancyMinutes} min'),
                _pill('Avg temp: ${stats.avgTemp.toStringAsFixed(1)}°C'),
                _pill('Avg humidity: ${stats.avgHumidity.toStringAsFixed(0)}%'),
                _pill('Est people: ${stats.estimatedPeople} • ${stats.occupancyConfidenceLabel}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeopleEstimate(_DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: stats.occupancyConfidenceColor),
                const SizedBox(width: 8),
                const Text('People Count (estimated)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: stats.occupancyConfidenceColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(stats.occupancyConfidenceLabel,
                      style: TextStyle(
                        color: stats.occupancyConfidenceColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('${stats.estimatedPeople}',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Based on last ${stats.motionWindow} readings',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    Text('${stats.motionHits} motion hits (PIR/RCWL)',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Note: PIR/RCWL are binary presence sensors; count is inferred (0 or 1) from recent motion intensity.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComfortCard(_DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.thermostat, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text('Comfort & Drift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _valueTile('Temp', '${stats.latestTemp.toStringAsFixed(1)}°C', stats.tempStatusColor),
                const SizedBox(width: 10),
                _valueTile('Humidity', '${stats.latestHumidity.toStringAsFixed(0)}%', stats.humidityStatusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stats.comfortNote, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: stats.tempBandProgress,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(stats.tempStatusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorHealth(SensorReading latest, _DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.wifi_tethering, color: Colors.blueGrey),
                SizedBox(width: 8),
                Text('Sensor Health', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _healthTile('RSSI', '${latest.rssi ?? -80} dBm', stats.signalColor, stats.signalLabel),
                _healthTile('Uptime', latest.uptime != null ? '${latest.uptime}s' : 'n/a', Colors.indigo, 'since boot'),
                _healthTile('Heap', latest.heap != null ? '${latest.heap} B' : 'n/a', Colors.teal, 'free mem'),
                _healthTile('IP', latest.ip ?? 'n/a', Colors.grey, 'module'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations(_DerivedStats stats) {
    final List<_Recommendation> recs = _buildRecList(stats);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.lightbulb, color: Colors.amber),
                SizedBox(width: 8),
                Text('Actionable Recommendations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...recs.map(_recTile).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentReadings(List<SensorReading> readings) {
    final List<SensorReading> latestFive = readings.reversed.take(5).toList();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.list_alt, color: Colors.indigo),
                SizedBox(width: 8),
                Text('Recent Readings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...latestFive.map((r) => _readingRow(r)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _recTile(_Recommendation rec) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(rec.icon, color: rec.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rec.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(rec.detail, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: rec.color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(rec.cta, style: TextStyle(color: rec.color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _readingRow(SensorReading reading) {
    final bool occupied = reading.occupied;
    final Color color = occupied ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(occupied ? Icons.sensor_occupied : Icons.sensor_door, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${reading.location} • ${_friendlyTime(reading.receivedAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Temp ${reading.temperature.toStringAsFixed(1)}°C, Hum ${reading.humidity.toStringAsFixed(0)}%, PIR ${reading.pir}, RCWL ${reading.rcwl}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(occupied ? 'Occupied' : 'Vacant',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(18)),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _valueTile(String label, String value, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _healthTile(String label, String value, Color color, String hint) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(hint, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        ],
      ),
    );
  }

  String _friendlyTime(DateTime time) {
    final Duration diff = DateTime.now().difference(time.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class SensorReading {
  SensorReading({
    required this.module,
    required this.location,
    required this.rcwl,
    required this.pir,
    required this.temperature,
    required this.humidity,
    required this.receivedAt,
    this.rssi,
    this.uptime,
    this.heap,
    this.ip,
    this.mac,
  });

  final String module;
  final String location;
  final int rcwl;
  final int pir;
  final double temperature;
  final double humidity;
  final DateTime receivedAt;
  final int? rssi;
  final int? uptime;
  final int? heap;
  final String? ip;
  final String? mac;

  bool get occupied => rcwl == 1 || pir == 1;
}

class _DerivedStats {
  _DerivedStats({
    required this.avgTemp,
    required this.avgHumidity,
    required this.latestTemp,
    required this.latestHumidity,
    required this.isOccupied,
    required this.vacancyMinutes,
    required this.signalLabel,
    required this.signalColor,
    required this.tempStatusColor,
    required this.humidityStatusColor,
    required this.comfortNote,
    required this.tempBandProgress,
    required this.estimatedPeople,
    required this.motionHits,
    required this.motionWindow,
    required this.occupancyConfidenceLabel,
    required this.occupancyConfidenceColor,
  });

  final double avgTemp;
  final double avgHumidity;
  final double latestTemp;
  final double latestHumidity;
  final bool isOccupied;
  final int vacancyMinutes;
  final String signalLabel;
  final Color signalColor;
  final Color tempStatusColor;
  final Color humidityStatusColor;
  final String comfortNote;
  final double tempBandProgress;
  final int estimatedPeople;
  final int motionHits;
  final int motionWindow;
  final String occupancyConfidenceLabel;
  final Color occupancyConfidenceColor;
}

class _Recommendation {
  _Recommendation({
    required this.title,
    required this.detail,
    required this.cta,
    required this.color,
    required this.icon,
  });

  final String title;
  final String detail;
  final String cta;
  final Color color;
  final IconData icon;
}

_DerivedStats _deriveStats(List<SensorReading> readings) {
  final List<SensorReading> sorted = List.of(readings)..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  final SensorReading latest = sorted.last;

  final double avgTemp = sorted.map((r) => r.temperature).reduce((a, b) => a + b) / sorted.length;
  final double avgHumidity = sorted.map((r) => r.humidity).reduce((a, b) => a + b) / sorted.length;

  final SensorReading lastOccupied = sorted.reversed.firstWhere((r) => r.occupied, orElse: () => latest);
  final int vacancyMinutes = lastOccupied == latest
      ? 0
      : latest.receivedAt.difference(lastOccupied.receivedAt).inMinutes.clamp(0, 1 << 16).toInt();

  final int rssi = latest.rssi ?? -80;
  final String signalLabel;
  final Color signalColor;
  if (rssi >= -60) {
    signalLabel = 'Strong';
    signalColor = Colors.green;
  } else if (rssi >= -75) {
    signalLabel = 'Fair';
    signalColor = Colors.amber;
  } else {
    signalLabel = 'Weak';
    signalColor = Colors.red;
  }

  final double tempBandProgress = (((latest.temperature - 20) / 10).clamp(0, 1)).toDouble();
  final Color tempColor = latest.temperature > 30
      ? Colors.red
      : (latest.temperature >= 27 ? Colors.orange : Colors.green);
  final Color humidityColor = latest.humidity > 70
      ? Colors.orange
      : (latest.humidity < 40 ? Colors.amber : Colors.green);
  final String comfortNote = latest.temperature > 30
      ? 'Hot drift: lower setpoint or turn off if vacant.'
      : latest.temperature < 23
          ? 'Cooler than typical. Check setpoint.'
          : 'Within comfort band.';

  // Estimate people count (binary sensors -> inferred 0/1) using recent motion hits.
  const int windowSize = 10;
  final List<SensorReading> window = sorted.reversed.take(windowSize).toList();
  final int motionHits = window.where((r) => r.occupied).length;
  final int motionWindow = window.length;
  final int estimatedPeople = motionHits > 0 ? 1 : 0;
  final double confidence = motionWindow == 0 ? 0 : motionHits / motionWindow;
  final String occupancyConfidenceLabel;
  final Color occupancyConfidenceColor;
  if (confidence >= 0.7) {
    occupancyConfidenceLabel = 'High confidence';
    occupancyConfidenceColor = Colors.green;
  } else if (confidence >= 0.4) {
    occupancyConfidenceLabel = 'Medium confidence';
    occupancyConfidenceColor = Colors.amber;
  } else {
    occupancyConfidenceLabel = 'Low confidence';
    occupancyConfidenceColor = Colors.red;
  }

  return _DerivedStats(
    avgTemp: avgTemp,
    avgHumidity: avgHumidity,
    latestTemp: latest.temperature,
    latestHumidity: latest.humidity,
    isOccupied: latest.occupied,
    vacancyMinutes: vacancyMinutes,
    signalLabel: signalLabel,
    signalColor: signalColor,
    tempStatusColor: tempColor,
    humidityStatusColor: humidityColor,
    comfortNote: comfortNote,
    tempBandProgress: tempBandProgress,
    estimatedPeople: estimatedPeople,
    motionHits: motionHits,
    motionWindow: motionWindow,
    occupancyConfidenceLabel: occupancyConfidenceLabel,
    occupancyConfidenceColor: occupancyConfidenceColor,
  );
}

List<_Recommendation> _buildRecList(_DerivedStats stats) {
  final List<_Recommendation> recs = [];
  if (!stats.isOccupied && stats.latestTemp > 31 && stats.vacancyMinutes >= 30) {
    recs.add(_Recommendation(
      title: 'Turn off AC in vacant room',
      detail: 'Vacant for ${stats.vacancyMinutes} min at ${stats.latestTemp.toStringAsFixed(1)}°C.',
      cta: 'Send Alert',
      color: Colors.red,
      icon: Icons.ac_unit,
    ));
  }
  recs.add(_Recommendation(
    title: 'Align motion sensing',
    detail: 'RCWL often 1 while PIR 0. Reposition sensor to reduce false motion.',
    cta: 'Inspect',
    color: Colors.indigo,
    icon: Icons.sensors,
  ));
  recs.add(_Recommendation(
    title: 'Check link quality',
    detail: 'RSSI ${stats.signalLabel}. Move gateway or adjust antenna.',
    cta: 'Check Link',
    color: stats.signalColor,
    icon: Icons.network_check,
  ));
  recs.add(_Recommendation(
    title: 'Comfort guardrails',
    detail: 'Keep 24-27°C occupied; allow 29-30°C when vacant to save energy.',
    cta: 'Apply',
    color: Colors.teal,
    icon: Icons.rule,
  ));
  return recs;
}

final List<SensorReading> _sampleReadings = [
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 0,
    temperature: 29.2,
    humidity: 60.1,
    receivedAt: DateTime.parse('2025-12-29T15:38:38.770Z'),
    rssi: -57,
    uptime: 60,
    heap: 39336,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 0,
    temperature: 29.2,
    humidity: 60.1,
    receivedAt: DateTime.parse('2025-12-29T16:10:16.842Z'),
    rssi: -75,
    uptime: 120,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 0,
    temperature: 32.9,
    humidity: 69,
    receivedAt: DateTime.parse('2025-12-31T09:47:02.976Z'),
    rssi: -57,
    uptime: 60,
    heap: 39336,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 1,
    temperature: 31.8,
    humidity: 70,
    receivedAt: DateTime.parse('2025-12-31T09:51:49.442Z'),
    rssi: -61,
    uptime: 360,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 1,
    temperature: 32.6,
    humidity: 70,
    receivedAt: DateTime.parse('2025-12-31T09:59:49.868Z'),
    rssi: -75,
    uptime: 840,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 0,
    temperature: 31.5,
    humidity: 70,
    receivedAt: DateTime.parse('2025-12-31T10:03:51.028Z'),
    rssi: -58,
    uptime: 1080,
    heap: 16680,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 0,
    temperature: 31.9,
    humidity: 70,
    receivedAt: DateTime.parse('2025-12-31T10:17:50.205Z'),
    rssi: -76,
    uptime: 1921,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 1,
    temperature: 31.4,
    humidity: 70,
    receivedAt: DateTime.parse('2025-12-31T10:19:50.216Z'),
    rssi: -75,
    uptime: 2041,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 0,
    temperature: 31.5,
    humidity: 70,
    receivedAt: DateTime.parse('2025-12-31T10:21:50.338Z'),
    rssi: -75,
    uptime: 2161,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 0,
    temperature: 31.9,
    humidity: 71,
    receivedAt: DateTime.parse('2025-12-31T10:22:50.331Z'),
    rssi: -80,
    uptime: 2221,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 0,
    temperature: 31.6,
    humidity: 71,
    receivedAt: DateTime.parse('2025-12-31T10:23:50.342Z'),
    rssi: -75,
    uptime: 2281,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 1,
    temperature: 31.3,
    humidity: 73,
    receivedAt: DateTime.parse('2025-12-31T10:49:50.735Z'),
    rssi: -73,
    uptime: 3841,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 1,
    temperature: 31.8,
    humidity: 73,
    receivedAt: DateTime.parse('2025-12-31T10:51:51.031Z'),
    rssi: -72,
    uptime: 3961,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
  SensorReading(
    module: 'MOD001',
    location: 'Room1_North',
    rcwl: 1,
    pir: 1,
    temperature: 31.8,
    humidity: 72,
    receivedAt: DateTime.parse('2025-12-31T11:01:51.199Z'),
    rssi: -74,
    uptime: 4562,
    heap: 17976,
    ip: '10.176.179.193',
    mac: '60:01:94:36:A2:F4',
  ),
];
