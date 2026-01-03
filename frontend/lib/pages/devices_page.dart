import 'package:flutter/material.dart';

/// Devices page showing connected IoT devices
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add device feature coming soon')),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(seconds: 1));
        },
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text(
              'Connected Devices',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildDeviceCard(
              context,
              'Air Conditioner',
              'Living Room',
              true,
              '1.2 kW',
              Icons.ac_unit,
              Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildDeviceCard(
              context,
              'Water Heater',
              'Bathroom',
              true,
              '0.8 kW',
              Icons.water_drop,
              Colors.red,
            ),
            const SizedBox(height: 12),
            _buildDeviceCard(
              context,
              'Refrigerator',
              'Kitchen',
              true,
              '0.4 kW',
              Icons.kitchen,
              Colors.green,
            ),
            const SizedBox(height: 12),
            _buildDeviceCard(
              context,
              'Washing Machine',
              'Laundry Room',
              false,
              '0.0 kW',
              Icons.local_laundry_service,
              Colors.grey,
            ),
            const SizedBox(height: 12),
            _buildDeviceCard(
              context,
              'Smart TV',
              'Living Room',
              false,
              '0.0 kW',
              Icons.tv,
              Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              'Device Statistics',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildStatRow('Total Devices', '5'),
                    const Divider(height: 24),
                    _buildStatRow('Active Now', '3'),
                    const Divider(height: 24),
                    _buildStatRow('Total Power', '2.4 kW'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    String name,
    String location,
    bool isOn,
    String power,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    power,
                    style: TextStyle(
                      fontSize: 14,
                      color: isOn ? color : Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: isOn,
              onChanged: (value) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value ? 'Turning on $name' : 'Turning off $name',
                    ),
                  ),
                );
              },
              activeThumbColor: color,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
