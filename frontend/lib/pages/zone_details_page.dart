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
  late List<DeviceData> devices;
  Map<String, Map<String, dynamic>> _energyByLocation = {};
  double _zoneLiveCurrent = 0.0;
  late List<ScheduleRuleData> schedules;
  final ZonesService _zonesService = ZonesService();
  bool _loadingDevices = false;
  bool _savingDevice = false;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    devices = [];
    schedules = _getMockSchedules();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final list = await _zonesService.fetchDevicesForLocation(widget.zone.name);

      // Fetch latest energy for this location and map by location + device hints
      final energyList = await EnergyService.getEnergyReadings(location: widget.zone.name, limit: 50);
      _energyByLocation = {
        for (final e in energyList)
          if (e is Map<String, dynamic> && e['location'] != null)
            e['location'].toString(): e as Map<String, dynamic>
      };

      devices = list.map((d) {
        final deviceId = d['device_id']?.toString() ?? 'unknown';
        final deviceName = d['device_name']?.toString() ?? 'Unknown Device';
        final deviceType = d['device_type']?.toString() ?? 'Unknown';
        final power = (d['rated_power_watts'] is num) ? (d['rated_power_watts'] as num).toInt() : 0;

        // Match energy by location (since backend groups by location) and fallback to deviceId/name keys if present
        Map<String, dynamic>? energy = _energyByLocation[widget.zone.name];
        energy ??= _energyByLocation[deviceId];
        energy ??= _energyByLocation[deviceName];

        final currentA = (energy != null && energy['current_a'] is num) ? (energy['current_a'] as num).toDouble() : 0.0;
        final voltage = (energy != null && energy['voltage'] is num) ? (energy['voltage'] as num).toDouble() : 230.0;
        final powerW = currentA * voltage;
        // Approximate live kWh over 1 hour window (better than zero, still labeled as live est.)
        final energyToday = powerW / 1000.0;
        final lastSeen = energy != null ? (energy['received_at'] ?? energy['receivedAt'] ?? energy['timestamp']) : null;

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

  double get totalEnergy => devices.fold(0, (sum, d) => sum + d.energyToday);
  double get estimatedCost => totalEnergy * 12; // Assuming LKR 12 per kWh

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.zone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Zone Summary Card
            _buildZoneSummaryCard(),
            const SizedBox(height: 24),

            // Today's Energy
            _buildTodayEnergySection(),
            const SizedBox(height: 24),

            // Tab Navigation
            _buildTabNavigation(),
            const SizedBox(height: 16),

            // Tab Content
            _buildTabContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A90E2), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
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
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${widget.zone.type} • Floor ${widget.zone.floor}",
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
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
                icon: Icons.devices,
                label: "Devices",
                value: "${devices.where((d) => d.status == 'on').length}/${devices.length}",
              ),
              _buildSummaryItem(
                icon: Icons.thermostat,
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
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
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
          "Today's Energy Usage",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFFFBBF24), size: 28),
                  const SizedBox(height: 8),
                  Text(
                    "${totalEnergy.toStringAsFixed(2)} kWh",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Energy Consumed",
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              Container(
                height: 50,
                width: 1,
                color: Colors.grey[200],
              ),
              Column(
                children: [
                  const Icon(Icons.attach_money, color: Color(0xFF00C853), size: 28),
                  const SizedBox(height: 8),
                  Text(
                    "LKR ${estimatedCost.toStringAsFixed(0)}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Estimated Cost",
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              Container(
                height: 50,
                width: 1,
                color: Colors.grey[200],
              ),
              Column(
                children: [
                  const Icon(Icons.electric_bolt, color: Color(0xFF42A5F5), size: 28),
                  const SizedBox(height: 8),
                  Text(
                    "${_zoneLiveCurrent.toStringAsFixed(2)} A",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Live Current",
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
            color: isSelected ? const Color(0xFF4A90E2) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF4A90E2) : Colors.grey[200]!,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.black87,
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
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isOn ? const Color(0xFFE8F5E9) : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.devices,
              color: isOn ? const Color(0xFF4CAF50) : Colors.grey[600],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  "${device.type} • ${device.power}W",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                if (device.liveCurrentA != null)
                  Text(
                    "Live: ${device.liveCurrentA!.toStringAsFixed(2)} A",
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0)),
                  ),
                if (device.lastEnergyTs != null)
                  Text(
                    "Updated: ${device.lastEnergyTs}",
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isOn ? "ON" : "OFF",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isOn
                        ? const Color(0xFF2E7D32)
                        : Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "${device.energyToday.toStringAsFixed(2)} kWh est.",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                "~${(device.energyToday * 30).toStringAsFixed(1)} kWh/mo",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
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
              color: isOn ? const Color(0xFF4CAF50) : Colors.grey[400],
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
