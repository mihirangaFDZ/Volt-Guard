import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/zones_service.dart';
import '../services/energy_service.dart';

class ZoneManagerPage extends StatefulWidget {
  const ZoneManagerPage({Key? key}) : super(key: key);

  @override
  State<ZoneManagerPage> createState() => _ZoneManagerPageState();
}

class _ZoneManagerPageState extends State<ZoneManagerPage> {
  late Future<List<dynamic>> _zonesFuture;
  late Future<List<dynamic>> _energyFuture;
  String _selectedLocation = '';

  int _occupiedCount(List<dynamic> zones) {
    return zones.where((z) {
      final m = z as Map<String, dynamic>;
      return (m['occupancy'] ?? false) == true || (m['rcwl'] ?? 0) == 1 || (m['pir'] ?? 0) == 1;
    }).length;
  }

  int _emptyCount(List<dynamic> zones) => zones.length - _occupiedCount(zones);

  int _peopleEstimate(Map<String, dynamic> zone) {
    // Basic presence estimate: if any motion flag is 1, treat as 1 person; otherwise 0.
    final hasMotion = (zone['rcwl'] ?? 0) == 1 || (zone['pir'] ?? 0) == 1 || (zone['occupancy'] ?? false) == true;
    // If either env reading is missing/invalid (<=0 or null), treat as empty to avoid false positives.
    final temp = _sanitizeEnv(zone['temperature'] as num?);
    final hum = _sanitizeEnv(zone['humidity'] as num?);
    final envValid = temp != null && hum != null;
    if (!envValid) return 0;
    return hasMotion ? 1 : 0;
  }

  num? _sanitizeEnv(num? value) {
    if (value == null) return null;
    // Treat zeros or negative readings as missing.
    if (value <= 0) return null;
    return value;
  }

  double? _avgTemp(List<dynamic> zones) {
    final temps = zones
        .map((z) => (z as Map<String, dynamic>)['temperature'])
        .where((t) => t is num)
        .cast<num>()
        .toList();
    if (temps.isEmpty) return null;
    return temps.reduce((a, b) => a + b) / temps.length;
  }

  double? _avgHumidity(List<dynamic> zones) {
    final hums = zones
        .map((z) => (z as Map<String, dynamic>)['humidity'])
        .where((h) => h is num)
        .cast<num>()
        .toList();
    if (hums.isEmpty) return null;
    return hums.reduce((a, b) => a + b) / hums.length;
  }

  List<Map<String, dynamic>> _rankedZones(List<dynamic> zones) {
    final list = zones.map((z) => z as Map<String, dynamic>).toList();
    list.sort((a, b) {
      final occA = (a['occupancy'] ?? false) == true || (a['rcwl'] ?? 0) == 1 || (a['pir'] ?? 0) == 1;
      final occB = (b['occupancy'] ?? false) == true || (b['rcwl'] ?? 0) == 1 || (b['pir'] ?? 0) == 1;

      if (occA != occB) return occB ? 1 : -1; // occupied first

      final tsA = a['last_seen']?.toString() ?? '';
      final tsB = b['last_seen']?.toString() ?? '';
      return tsB.compareTo(tsA); // most recent first
    });
    return list;
  }

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _zonesFuture = ZonesService.fetchZones();
      _energyFuture = EnergyService.getEnergyLocations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zone Manager'),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshData(),
        child: FutureBuilder<List<dynamic>>(
          future: _zonesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refreshData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final zones = snapshot.data ?? [];
            if (zones.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('No zones available'),
                  ],
                ),
              );
            }

            final rankedZones = _rankedZones(zones);
            return ListView(
              padding: const EdgeInsets.all(12),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _buildSummaryCards(zones),
                const SizedBox(height: 12),
                _buildRankingSection(rankedZones),
                const SizedBox(height: 12),
                ...zones.map((z) {
                  final zone = z as Map<String, dynamic>;
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ZoneDetailPage(zone: zone),
                        ),
                      );
                    },
                    child: _buildZoneCard(zone),
                  );
                }).toList(),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddDevicePage()),
          );
        },
        backgroundColor: Colors.blue[700],
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildZoneCard(Map<String, dynamic> zone) {
    final location = zone['location'] ?? 'Unknown';
    final occupancy = zone['occupancy'] ?? false;
    final rcwl = zone['rcwl'] ?? 0;
    final pir = zone['pir'] ?? 0;
    final temperature = _sanitizeEnv(zone['temperature'] as num?);
    final humidity = _sanitizeEnv(zone['humidity'] as num?);
    final lastSeen = zone['last_seen'];
    final people = _peopleEstimate(zone);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location Header with Occupancy Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Module: ${zone['module'] ?? 'N/A'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: occupancy ? Colors.red[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: occupancy ? Colors.red : Colors.green,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        occupancy ? Icons.person : Icons.person_outline,
                        color: occupancy ? Colors.red : Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        occupancy ? 'Occupied' : 'Empty',
                        style: TextStyle(
                          color: occupancy ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Occupancy Sensors
            Row(
              children: [
                Expanded(
                  child: _buildSensorChip(
                    'RCWL Sensor',
                    rcwl == 1,
                    Icons.radar,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSensorChip(
                    'PIR Sensor',
                    pir == 1,
                    Icons.motion_photos_on,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // People estimate
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.people_outline, color: Colors.indigo, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('People (est.)', style: TextStyle(fontSize: 12, color: Colors.black87)),
                      Text(
                        people.toString(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Environmental Data
            if (temperature != null || humidity != null)
              Row(
                children: [
                  if (temperature != null)
                    Expanded(
                      child: _buildEnvironmentalChip(
                        'Temperature',
                        '${temperature.toStringAsFixed(1)}°C',
                        Icons.thermostat,
                        Colors.orange,
                      ),
                    ),
                  if (humidity != null) const SizedBox(width: 8),
                  if (humidity != null)
                    Expanded(
                      child: _buildEnvironmentalChip(
                        'Humidity',
                        '${humidity.toStringAsFixed(1)}%',
                        Icons.opacity,
                        Colors.blue,
                      ),
                    ),
                ],
              ),
            if (temperature != null || humidity != null) const SizedBox(height: 12),

            // Last Seen
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Last update: ${_formatTime(lastSeen)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorChip(String label, bool active, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: active ? Colors.red[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? Colors.red : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: active ? Colors.red : Colors.grey[500],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  active ? 'DETECTED' : 'CLEAR',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentalChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    try {
      if (timestamp is String) {
        final dateTime = DateTime.parse(timestamp);
        return DateFormat('HH:mm').format(dateTime);
      }
      return 'N/A';
    } catch (e) {
      return 'N/A';
    }
  }

  Widget _buildSummaryCards(List<dynamic> zones) {
    final occupied = _occupiedCount(zones);
    final empty = _emptyCount(zones);
    final avgTemp = _avgTemp(zones);
    final avgHum = _avgHumidity(zones);

    Widget buildCard(String title, String value, IconData icon, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Zone Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            buildCard('Total Zones', '${zones.length}', Icons.maps_home_work, Colors.blue),
            const SizedBox(width: 8),
            buildCard('Occupied', '$occupied', Icons.people, Colors.red),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            buildCard('Empty', '$empty', Icons.meeting_room_outlined, Colors.green),
            const SizedBox(width: 8),
            buildCard(
              'Avg Temp',
              avgTemp != null ? '${avgTemp.toStringAsFixed(1)}°C' : 'N/A',
              Icons.thermostat,
              Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            buildCard(
              'Avg Humidity',
              avgHum != null ? '${avgHum.toStringAsFixed(1)}%' : 'N/A',
              Icons.opacity,
              Colors.blueGrey,
            ),
            const SizedBox(width: 8),
            buildCard('Selected', _selectedLocation.isEmpty ? 'None' : _selectedLocation, Icons.push_pin, Colors.purple),
          ],
        ),
      ],
    );
  }

  Widget _buildRankingSection(List<Map<String, dynamic>> rankedZones) {
    final top = rankedZones.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active & Recent Zones',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...top.map((z) {
          final name = z['location'] ?? 'Unknown';
          final occ = (z['occupancy'] ?? false) == true || (z['rcwl'] ?? 0) == 1 || (z['pir'] ?? 0) == 1;
          final ts = z['last_seen'];
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: occ ? Colors.red.withOpacity(0.08) : Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: occ ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(occ ? Icons.person : Icons.person_off, color: occ ? Colors.red : Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Text(
                  _formatTime(ts),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}

// Zone Detail Page
class ZoneDetailPage extends StatefulWidget {
  final Map<String, dynamic> zone;

  const ZoneDetailPage({
    Key? key,
    required this.zone,
  }) : super(key: key);

  @override
  State<ZoneDetailPage> createState() => _ZoneDetailPageState();
}

class _ZoneDetailPageState extends State<ZoneDetailPage> {
  late Future<Map<String, dynamic>> _detailFuture;
  late Future<List<dynamic>> _energyReadingsFuture;
  late Future<List<Map<String, dynamic>>> _devicesFuture;

  num? _sanitizeEnv(num? value) {
    if (value == null) return null;
    if (value <= 0) return null;
    return value;
  }

  int _peopleEstimate(Map<String, dynamic> zone) {
    final hasMotion = (zone['rcwl'] ?? 0) == 1 || (zone['pir'] ?? 0) == 1 || (zone['occupancy'] ?? false) == true;
    final temp = _sanitizeEnv(zone['temperature'] as num?);
    final hum = _sanitizeEnv(zone['humidity'] as num?);
    final envValid = temp != null && hum != null;
    if (!envValid) return 0;
    return hasMotion ? 1 : 0;
  }

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  void _loadDetails() {
    final location = widget.zone['location'] ?? '';
    setState(() {
      _detailFuture = ZonesService.fetchZoneDetail(location);
      _energyReadingsFuture = EnergyService.getEnergyReadings(location: location);
      _devicesFuture = ZonesService.fetchDevicesForLocation(location);
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.zone['location'] ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: Text(location),
        backgroundColor: Colors.blue[700],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadDetails(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Status
              _buildCurrentStatus(),
              const SizedBox(height: 24),

              // Devices in this room
              _buildDevicesSection(),
              const SizedBox(height: 24),

              // Energy Consumption
              _buildEnergySection(),
              const SizedBox(height: 24),

              // Historical Data
              _buildHistorySection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStatus() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: _detailFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                final detail = snapshot.data ?? {};
                final latest = detail['latest'] as Map<String, dynamic>? ?? {};
                final people = _peopleEstimate(latest);
                final temp = _sanitizeEnv(latest['temperature'] as num?);
                final hum = _sanitizeEnv(latest['humidity'] as num?);

                return Column(
                  children: [
                    _buildStatusRow('Occupancy', 
                      (latest['occupancy'] ?? false) ? 'Occupied' : 'Empty',
                      (latest['occupancy'] ?? false) ? Colors.red : Colors.green),
                    const SizedBox(height: 8),
                    _buildStatusRow('RCWL', 
                      (latest['rcwl'] ?? 0) == 1 ? 'Detected' : 'Clear',
                      (latest['rcwl'] ?? 0) == 1 ? Colors.red : Colors.green),
                    const SizedBox(height: 8),
                    _buildStatusRow('PIR', 
                      (latest['pir'] ?? 0) == 1 ? 'Detected' : 'Clear',
                      (latest['pir'] ?? 0) == 1 ? Colors.red : Colors.green),
                    const SizedBox(height: 8),
                    _buildStatusRow('People (est.)', '$people', Colors.indigo),
                    if (temp != null) ...[
                      const SizedBox(height: 8),
                      _buildStatusRow('Temperature', 
                        '${temp.toStringAsFixed(1)}°C',
                        Colors.orange),
                    ],
                    if (hum != null) ...[
                      const SizedBox(height: 8),
                      _buildStatusRow('Humidity', 
                        '${hum.toStringAsFixed(1)}%',
                        Colors.blue),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesSection() {
    final location = widget.zone['location'] ?? '';
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Devices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _showAddDeviceSheet,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _devicesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Error: ${snapshot.error}'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _refreshDevices,
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }

                final devices = snapshot.data ?? [];
                if (devices.isEmpty) {
                  return const Text('No devices yet for this room');
                }

                return Column(
                  children: devices.map((d) {
                    final device = d;
                    final power = device['rated_power_watts'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device['device_name'] ?? device['device_id'] ?? 'Device',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                device['device_type'] ?? 'Unknown type',
                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                          Text(
                            power != null ? '${power} W' : 'N/A',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshDevices() async {
    final location = widget.zone['location'] ?? '';
    setState(() {
      _devicesFuture = ZonesService.fetchDevicesForLocation(location);
    });
  }

  void _showAddDeviceSheet() {
    final rootContext = context;
    final location = widget.zone['location']?.toString() ?? '';
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final typeController = TextEditingController(text: 'energy_sensor');
    final powerController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add device to $location', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: idController,
                decoration: const InputDecoration(labelText: 'Device ID (e.g., MOD001)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Device Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: typeController,
                decoration: const InputDecoration(labelText: 'Device Type'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: powerController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rated Power (W)'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () async {
                    final id = idController.text.trim();
                    final name = nameController.text.trim();
                    final dtype = typeController.text.trim().isEmpty ? 'energy_sensor' : typeController.text.trim();
                    final rated = double.tryParse(powerController.text.trim());

                    if (id.isEmpty || name.isEmpty || rated == null) {
                      ScaffoldMessenger.of(rootContext).showSnackBar(
                        const SnackBar(content: Text('Fill all fields with valid values')),
                      );
                      return;
                    }

                    try {
                      await ZonesService.addDeviceToZone(
                        location: location,
                        deviceId: id,
                        deviceName: name,
                        ratedPowerWatts: rated,
                        deviceType: dtype,
                      );
                      if (!mounted) return;
                      Navigator.of(modalContext).pop();
                      ScaffoldMessenger.of(rootContext).showSnackBar(
                        const SnackBar(content: Text('Device added')),
                      );
                      await _refreshDevices();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(rootContext).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEnergySection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Energy Readings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<dynamic>>(
              future: _energyReadingsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                final readings = snapshot.data ?? [];
                if (readings.isEmpty) {
                  return const Text('No energy data available');
                }

                // Calculate statistics
                final currentValues = readings
                    .map((r) {
                      final reading = r as Map<String, dynamic>;
                      return reading['current_a'] as num? ?? 0;
                    })
                    .toList();

                final avgCurrent = currentValues.isEmpty
                    ? 0.0
                    : currentValues.reduce((a, b) => a + b) / currentValues.length;
                final maxCurrent =
                    currentValues.isEmpty ? 0.0 : currentValues.reduce((a, b) => a > b ? a : b);

                return Column(
                  children: [
                    _buildEnergyStatCard('Average Current', '${avgCurrent.toStringAsFixed(3)} A',
                        Colors.blue),
                    const SizedBox(height: 8),
                    _buildEnergyStatCard('Peak Current', '${maxCurrent.toStringAsFixed(3)} A',
                        Colors.red),
                    const SizedBox(height: 12),
                    const Text('Latest Readings:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: readings.take(5).length,
                        itemBuilder: (context, index) {
                          final reading = readings[index] as Map<String, dynamic>;
                          final currentA = reading['current_a'] ?? 0.0;
                          final currentMa = reading['current_ma'] ?? 0.0;
                          final timestamp = reading['received_at'] ?? '';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${currentA.toStringAsFixed(3)} A',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          )),
                                      Text('${currentMa.toStringAsFixed(2)} mA',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          )),
                                    ],
                                  ),
                                  Text(_formatDateTime(timestamp),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      )),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 14,
              )),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Occupancy History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: _detailFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                final detail = snapshot.data ?? {};
                final history = (detail['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];

                if (history.isEmpty) {
                  return const Text('No history available');
                }

                return SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final occupancy = (item['rcwl'] ?? 0) == 1 || (item['pir'] ?? 0) == 1;
                      final timestamp = item['received_at'] ?? '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: occupancy ? Colors.red[50] : Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: occupancy ? Colors.red : Colors.green,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    occupancy ? 'Occupied' : 'Empty',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: occupancy ? Colors.red : Colors.green,
                                    ),
                                  ),
                                  Text(
                                    'RCWL: ${item['rcwl'] ?? 0}, PIR: ${item['pir'] ?? 0}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _formatDateTime(timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(dynamic timestamp) {
    try {
      if (timestamp is String) {
        final dateTime = DateTime.parse(timestamp);
        return DateFormat('HH:mm:ss').format(dateTime);
      }
      return 'N/A';
    } catch (e) {
      return 'N/A';
    }
  }
}

// Add Device Page
class AddDevicePage extends StatefulWidget {
  const AddDevicePage({Key? key}) : super(key: key);

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final _formKey = GlobalKey<FormState>();
  final _locationController = TextEditingController();
  final _deviceIdController = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _ratedPowerController = TextEditingController();
  final _deviceTypeController = TextEditingController(text: 'energy_sensor');
  bool _isLoading = false;

  @override
  void dispose() {
    _locationController.dispose();
    _deviceIdController.dispose();
    _deviceNameController.dispose();
    _ratedPowerController.dispose();
    _deviceTypeController.dispose();
    super.dispose();
  }

  Future<void> _addDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final location = _locationController.text.trim();
      final result = await ZonesService.addDeviceToZone(
        location: location,
        deviceId: _deviceIdController.text.trim(),
        deviceName: _deviceNameController.text.trim(),
        ratedPowerWatts: double.parse(_ratedPowerController.text),
        deviceType: _deviceTypeController.text.trim().isEmpty
            ? 'energy_sensor'
            : _deviceTypeController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device added successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Device to Zone'),
        backgroundColor: Colors.blue[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add a new device to a zone',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Zone Location',
                  hintText: 'e.g., Room1_North, LAB_1',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Location is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deviceIdController,
                decoration: InputDecoration(
                  labelText: 'Device ID',
                  hintText: 'e.g., MOD001',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Device ID is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _deviceNameController,
                decoration: InputDecoration(
                  labelText: 'Device Name',
                  hintText: 'e.g., Energy Sensor 1',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Device name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
                TextFormField(
                  controller: _deviceTypeController,
                  decoration: InputDecoration(
                    labelText: 'Device Type',
                    hintText: 'e.g., energy_sensor',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              TextFormField(
                controller: _ratedPowerController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Rated Power (Watts)',
                  hintText: 'e.g., 100',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Rated power is required';
                  }
                  try {
                    double.parse(value!);
                    return null;
                  } catch (e) {
                    return 'Please enter a valid number';
                  }
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _addDevice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Add Device',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
