import 'dart:async';

import 'package:flutter/material.dart';
import 'package:volt_guard/services/zones_service.dart';
import 'package:volt_guard/services/energy_service.dart';

import 'zones_page.dart';

/// Detailed view of a single zone with devices and scheduling
class ZoneDetailsPage extends StatefulWidget {
  final ZoneData zone;

  const ZoneDetailsPage({super.key, required this.zone});

  @override
  State<ZoneDetailsPage> createState() => _ZoneDetailsPageState();
}

class _ZoneDetailsPageState extends State<ZoneDetailsPage> {
  static const double _lkrPerKwh = 12.0;
  late List<DeviceData> devices;
  Map<String, Map<String, dynamic>> _energyByLocation = {};
  double _zoneLiveCurrent = 0.0;
  double _zoneEnergyKwh = 0.0;
  late List<ScheduleRuleData> schedules;
  final ZonesService _zonesService = ZonesService();
  bool _loadingDevices = false;
  bool _savingDevice = false;
  int _selectedTabIndex = 0;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    devices = [];
    schedules = _getMockSchedules();
    _loadDevices();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadDevices());
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final list = await _zonesService.fetchDevicesForLocation(widget.zone.name);

      String _norm(String? v) => v?.toLowerCase().trim() ?? '';
      final zoneKey = _norm(widget.zone.name);
      final moduleKey = _norm(widget.zone.type); // zone.type currently stores module string

      // Fetch latest per-location for live current
      final latestByLoc = await EnergyService.getLatestByLocation();
      _energyByLocation = {};
      for (final e in latestByLoc) {
        if (e is! Map<String, dynamic>) continue;
        final key = _norm(e['location']?.toString());
        if (key.isEmpty) continue;
        _energyByLocation.putIfAbsent(key, () => e as Map<String, dynamic>);
      }

      // Fetch aggregated energy usage (kWh) per location from backend
      final usageResp = await EnergyService.getEnergyUsage(limit: 5000);
      final usageList = (usageResp['usage'] is List) ? usageResp['usage'] as List : <dynamic>[];
      final Map<String, double> energyKwhByLoc = {};
      for (final u in usageList) {
        if (u is! Map<String, dynamic>) continue;
        final key = _norm(u['location']?.toString());
        final val = (u['energy_kwh'] is num) ? (u['energy_kwh'] as num).toDouble() : 0.0;
        if (key.isNotEmpty) energyKwhByLoc[key] = val;
      }

      // Fetch history for this location to compute energy
      List<dynamic> energyList = await EnergyService.getEnergyReadings(location: widget.zone.name, limit: 200);
      if (energyList.isEmpty) {
        energyList = await EnergyService.getEnergyReadings(limit: 200);
      }

      devices = list.map((d) {
        final deviceId = d['device_id']?.toString() ?? 'unknown';
        final deviceName = d['device_name']?.toString() ?? 'Unknown Device';
        final deviceType = d['device_type']?.toString() ?? 'Unknown';
        final power = (d['rated_power_watts'] is num) ? (d['rated_power_watts'] as num).toInt() : 0;

        // Match energy by normalized location/module/device hints
        Map<String, dynamic>? energy = _energyByLocation[zoneKey];
        energy ??= _energyByLocation[moduleKey];
        energy ??= _energyByLocation[_norm(deviceId)];
        energy ??= _energyByLocation[_norm(deviceName)];
        // If still null, fallback to newest reading
        energy ??= energyList.isNotEmpty && energyList.first is Map<String, dynamic>
            ? energyList.first as Map<String, dynamic>
            : null;

        double currentA = (energy != null && energy['current_a'] is num) ? (energy['current_a'] as num).toDouble() : 0.0;
        final voltage = (energy != null && energy['voltage'] is num) ? (energy['voltage'] as num).toDouble() : 230.0;
        final powerW = currentA * voltage;
        // Use backend aggregated energy if available for this location/device
        final energyToday = energyKwhByLoc[zoneKey] ?? energyKwhByLoc[moduleKey] ??
          energyKwhByLoc[_norm(deviceId)] ?? energyKwhByLoc[_norm(deviceName)] ?? 0.0;
        final lastSeen = energy != null ? (energy['received_at'] ?? energy['receivedAt'] ?? energy['timestamp']) : null;
        final parsedTs = lastSeen is String ? DateTime.tryParse(lastSeen) : (lastSeen is DateTime ? lastSeen : null);
        final isFresh = parsedTs != null ? DateTime.now().difference(parsedTs).inMinutes <= 5 : false;
        if (!isFresh) {
          currentA = 0.0; // Do not show outdated current values
        }

        return DeviceData(
          id: deviceId,
          name: deviceName,
          type: deviceType,
          power: power,
          status: 'on',
          energyToday: energyToday,
          liveCurrentA: currentA,
          lastEnergyTs: lastSeen?.toString(),
        );
      }).toList();

      // Zone energy is the sum of device-level aggregated kWh; fallback to integrated history if empty
      _zoneEnergyKwh = devices.fold(0.0, (sum, d) => sum + d.energyToday);
      if (_zoneEnergyKwh == 0 && energyList.isNotEmpty) {
        _zoneEnergyKwh = _computeEnergyKwh(energyList);
      }

      // Sum live current for the zone
      _zoneLiveCurrent = devices.fold(0.0, (sum, d) => sum + (d.liveCurrentA ?? 0.0));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load devices: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  double _computeEnergyKwh(List<dynamic> readings) {
    if (readings.isEmpty) return 0.0;

    // Extract (ts, currentA, voltage) tuples
    final points = <Map<String, dynamic>>[];
    for (final r in readings) {
      if (r is! Map<String, dynamic>) continue;
      final tsRaw = r['received_at'] ?? r['receivedAt'] ?? r['timestamp'] ?? r['created_at'];
      final ts = tsRaw is String ? DateTime.tryParse(tsRaw) : (tsRaw is DateTime ? tsRaw : null);
      if (ts == null) continue;
      double current = 0.0;
      if (r['current_a'] is num) {
        current = (r['current_a'] as num).toDouble();
      } else if (r['current_ma'] is num) {
        current = (r['current_ma'] as num).toDouble() / 1000.0;
      }
      final voltage = (r['voltage'] is num) ? (r['voltage'] as num).toDouble() : 230.0;
      points.add({'ts': ts, 'current': current, 'voltage': voltage});
    }

    if (points.length < 2) {
      // Not enough points to integrate; approximate from last reading over a short window
      final p = points.isNotEmpty ? points.first : null;
      if (p == null) return 0.0;
      return (p['current'] * p['voltage'] / 1000.0) * (10 / 3600.0); // assume 10s window
    }

    // Sort ascending by time
    points.sort((a, b) => (a['ts'] as DateTime).compareTo(b['ts'] as DateTime));

    double kwh = 0.0;
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final dtSeconds = (cur['ts'] as DateTime).difference(prev['ts'] as DateTime).inSeconds;
      if (dtSeconds <= 0) continue;
      // Cap huge gaps to reduce overestimation on stale data
      final cappedDt = dtSeconds > 900 ? 900 : dtSeconds;
      final avgCurrent = ((prev['current'] as double) + (cur['current'] as double)) / 2.0;
      final voltage = (cur['voltage'] as double); // assume stable voltage
      final kwhChunk = (avgCurrent * voltage) * (cappedDt / 3600.0) / 1000.0;
      kwh += kwhChunk;
    }
    return kwh;
  }

  List<ScheduleRuleData> _getMockSchedules() {
    return [
      ScheduleRuleData(
        id: "rule_1",
        name: "School Hours",
        description: "AC ON during school hours",
        days: "Mon - Fri",
        startTime: "08:00",
        endTime: "15:00",
        action: "ON",
        targetDevices: ["dev_1"],
      ),
      ScheduleRuleData(
        id: "rule_2",
        name: "Evening Lights Off",
        description: "Lights OFF after school",
        days: "Mon - Fri",
        startTime: "16:00",
        endTime: "07:00",
        action: "OFF",
        targetDevices: ["dev_2"],
      ),
    ];
  }

  double get totalEnergy => _zoneEnergyKwh;
  double get estimatedCost => _zoneEnergyKwh * _lkrPerKwh; // LKR per kWh

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.zone.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadDevices,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(value),
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 8),
                    Text('Edit Zone'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Zone', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B1220), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadDevices,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildZoneSummaryCard(),
                const SizedBox(height: 20),
                _buildTodayEnergySection(),
                const SizedBox(height: 20),
                _buildTabNavigation(),
                const SizedBox(height: 14),
                _buildTabContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoneSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x331D4ED8), blurRadius: 18, offset: Offset(0, 12)),
        ],
      ),
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
                    widget.zone.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${widget.zone.type} • Floor ${widget.zone.floor}",
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.people, color: Colors.white, size: 20),
                    const SizedBox(height: 4),
                    Text(
                      "${widget.zone.capacity}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                icon: Icons.bolt,
                label: "Current Power",
                value: "${(widget.zone.currentPower / 1000).toStringAsFixed(1)} kW",
              ),
              _buildSummaryItem(
                icon: Icons.devices_other,
                label: "Devices On",
                value: "${devices.where((d) => d.status == 'on').length}/${devices.length}",
              ),
              _buildSummaryItem(
                icon: Icons.visibility,
                label: "Occupancy",
                value: widget.zone.occupancy == "occupied" ? "Active" : "Empty",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildTodayEnergySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Energy",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMiniStat(
                icon: Icons.bolt,
                color: const Color(0xFFFBBF24),
                title: "Cost (today)",
                value: "LKR ${estimatedCost.toStringAsFixed(0)}",
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniStat(
                icon: Icons.attach_money,
                color: const Color(0xFF22C55E),
                title: "Est. Monthly",
                value: "LKR ${(estimatedCost * 30).toStringAsFixed(0)}",
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniStat(
                icon: Icons.electric_bolt,
                color: const Color(0xFF38BDF8),
                title: "Live Current",
                value: "${_zoneLiveCurrent.toStringAsFixed(2)} A",
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniStat({required IconData icon, required Color color, required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildTabNavigation() {
    return Row(
      children: [
        _buildTabButton("Devices", 0),
        const SizedBox(width: 12),
        _buildTabButton("Schedules", 1),
        const SizedBox(width: 12),
        _buildTabButton("Analytics", 2),
      ],
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF2563EB) : Colors.white24,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildDevicesTab();
      case 1:
        return _buildSchedulesTab();
      case 2:
        return _buildAnalyticsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDevicesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Connected Devices",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddDeviceDialog(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text("Add Device"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingDevices)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
        if (!_loadingDevices && devices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text("No devices found for this zone."),
          ),
        if (!_loadingDevices && devices.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: devices.length,
            itemBuilder: (context, index) => _buildDeviceCard(devices[index]),
          ),
      ],
    );
  }

  Widget _buildDeviceCard(DeviceData device) {
    final isOn = device.status == "on";
    final tsText = device.lastEnergyTs ?? 'Unknown';
    final ts = device.lastEnergyTs != null ? DateTime.tryParse(device.lastEnergyTs!) : null;
    final isStale = ts != null ? DateTime.now().difference(ts).inMinutes > 5 : true;
    final staleLabel = isStale ? ' (stale)' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Color(0x220F172A), blurRadius: 12, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isOn ? const Color(0xFF22C55E).withOpacity(0.15) : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.devices,
              color: isOn ? const Color(0xFF22C55E) : Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  "${device.type} • ${device.power}W",
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                if (device.liveCurrentA != null)
                  Text(
                    "Live: ${device.liveCurrentA!.toStringAsFixed(2)} A",
                    style: const TextStyle(fontSize: 12, color: Color(0xFF60A5FA)),
                  ),
                if (device.lastEnergyTs != null)
                  Text(
                    "Updated: $tsText$staleLabel",
                    style: TextStyle(
                      fontSize: 11,
                      color: isStale ? Colors.red[300] : Colors.white60,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOn
                      ? const Color(0xFF22C55E).withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isOn ? "ON" : "OFF",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isOn
                        ? const Color(0xFF22C55E)
                        : Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "LKR ${(device.energyToday * _lkrPerKwh).toStringAsFixed(2)} est.",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
              Text(
                "~LKR ${(device.energyToday * 30 * _lkrPerKwh).toStringAsFixed(0)}/mo",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("${device.name} turned ${isOn ? 'OFF' : 'ON'}"),
                duration: const Duration(seconds: 1),
              ),
            ),
            child: Icon(
              Icons.power_settings_new,
              color: isOn ? const Color(0xFF22C55E) : Colors.white38,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Automation Rules",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddScheduleDialog(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text("Add Rule"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        schedules.isEmpty
            ? Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.schedule, color: Colors.grey[300], size: 40),
                      const SizedBox(height: 8),
                      Text(
                        "No schedules yet",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: schedules.length,
                itemBuilder: (context, index) =>
                    _buildScheduleCard(schedules[index]),
              ),
      ],
    );
  }

  Widget _buildScheduleCard(ScheduleRuleData rule) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
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
                    rule.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rule.description ?? "",
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: rule.action == "ON"
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rule.action,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: rule.action == "ON"
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                rule.days,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(width: 16),
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                "${rule.startTime} - ${rule.endTime}",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Zone Performance",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAnalyticRow("Peak Usage", "${(widget.zone.currentPower / 1000).toStringAsFixed(1)} kW"),
              const Divider(),
              _buildAnalyticRow(
                "Monthly Consumption",
                "${widget.zone.monthlyConsumption.toStringAsFixed(0)} kWh",
              ),
              const Divider(),
              _buildAnalyticRow("Monthly Cost", "LKR ${widget.zone.monthlyCost.toStringAsFixed(0)}"),
              const Divider(),
              if (widget.zone.monthlyBudget != null) ...[
                _buildAnalyticRow(
                  "Budget Status",
                  "${((widget.zone.monthlyCost / widget.zone.monthlyBudget!) * 100).toStringAsFixed(0)}%",
                ),
                const Divider(),
              ],
              _buildAnalyticRow("Device Efficiency", "Excellent"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showAddDeviceDialog() {
    final nameController = TextEditingController();
    final typeController = TextEditingController();
    final powerController = TextEditingController();
    final deviceIdController = TextEditingController();
    final locationController = TextEditingController(text: widget.zone.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Device"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: deviceIdController,
                decoration: InputDecoration(
                  labelText: "Device ID",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Device Name",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typeController,
                decoration: InputDecoration(
                  labelText: "Device Type",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: powerController,
                decoration: InputDecoration(
                  labelText: "Rated Power (W)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: "Location",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: _savingDevice
                ? null
                : () async {
                    final deviceId = deviceIdController.text.trim();
                    final name = nameController.text.trim();
                    final type = typeController.text.trim();
                    final location = locationController.text.trim();
                    final power = int.tryParse(powerController.text.trim());

                    if (deviceId.isEmpty || name.isEmpty || type.isEmpty || power == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please fill all required fields")),
                      );
                      return;
                    }

                    setState(() => _savingDevice = true);
                    try {
                      await _zonesService.addDeviceToZone(location, {
                        "device_id": deviceId,
                        "device_name": name,
                        "device_type": type,
                        "location": location,
                        "rated_power_watts": power,
                        "installed_date": DateTime.now().toIso8601String(),
                      });

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Device added successfully!")),
                        );
                        _loadDevices();
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to add device: $e')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _savingDevice = false);
                    }
                  },
            child: _savingDevice
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text("Add"),
          ),
        ],
      ),
    );
  }

  void _showAddScheduleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create Schedule Rule"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: "Rule Name",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Action",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: ["ON", "OFF", "POWER_SAVER"]
                    .map((action) => DropdownMenuItem(
                          value: action,
                          child: Text(action),
                        ))
                    .toList(),
                onChanged: (value) {},
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Schedule created successfully!")),
              );
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action) {
    if (action == 'edit') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Edit zone - Coming soon!")),
      );
    } else if (action == 'delete') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Delete Zone"),
          content: const Text("Are you sure you want to delete this zone?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Zone deleted!")),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Delete", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }
}

class DeviceData {
  final String id;
  final String name;
  final String type;
  final int power;
  final String status;
  final double energyToday;
  final double? liveCurrentA;
  final String? lastEnergyTs;

  DeviceData({
    required this.id,
    required this.name,
    required this.type,
    required this.power,
    required this.status,
    required this.energyToday,
    this.liveCurrentA,
    this.lastEnergyTs,
  });
}

class ScheduleRuleData {
  final String id;
  final String name;
  final String? description;
  final String days;
  final String startTime;
  final String endTime;
  final String action;
  final List<String> targetDevices;

  ScheduleRuleData({
    required this.id,
    required this.name,
    required this.description,
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.action,
    required this.targetDevices,
  });
}
