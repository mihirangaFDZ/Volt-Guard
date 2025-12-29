import 'package:flutter/material.dart';

/// Fault Detection page showing ML-based anomaly detection and device health
class FaultDetectionPage extends StatefulWidget {
  const FaultDetectionPage({super.key});

  @override
  State<FaultDetectionPage> createState() => _FaultDetectionPageState();
}

class _FaultDetectionPageState extends State<FaultDetectionPage> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fault Detection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Fault history')),
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
              // System Health Overview
              _buildHealthOverviewCard(context),
              const SizedBox(height: 24),

              // Severity Filter
              _buildSectionTitle('Filter by Severity'),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFilterChip('All'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Critical'),
                    const SizedBox(width: 8),
                    _buildFilterChip('High'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Medium'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Low'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Active Faults
              _buildSectionTitle('Active Faults'),
              const SizedBox(height: 12),
              _buildActiveFaultsList(context),
              const SizedBox(height: 24),

              // Device Health Status
              _buildSectionTitle('Device Health Status'),
              const SizedBox(height: 12),
              _buildDeviceHealthList(context),
              const SizedBox(height: 24),

              // ML Model Confidence
              _buildSectionTitle('AI Model Performance'),
              const SizedBox(height: 12),
              _buildMLConfidenceCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildHealthOverviewCard(BuildContext context) {
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
                const Text(
                  'System Health',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning,
                        color: Colors.orange[700],
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Attention Needed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildHealthStat('Critical', '1', Colors.red),
                _buildHealthDivider(),
                _buildHealthStat('High', '2', Colors.orange),
                _buildHealthDivider(),
                _buildHealthStat('Medium', '3', Colors.yellow[700]!),
                _buildHealthDivider(),
                _buildHealthStat('Healthy', '5', Colors.green),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Last scan: 2 minutes ago • Next scan: in 3 minutes',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[900],
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

  Widget _buildHealthStat(String label, String count, Color color) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildHealthDivider() {
    return Container(
      height: 40,
      width: 1,
      color: Colors.grey[300],
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = label;
        });
      },
    );
  }

  Widget _buildActiveFaultsList(BuildContext context) {
    return Column(
      children: [
        _buildFaultCard(
          'Air Conditioner #1',
          'Compressor failure detected',
          'Critical',
          Colors.red,
          Icons.ac_unit,
          'Requires immediate attention',
          '98% confidence',
          'Detected 15 min ago',
        ),
        const SizedBox(height: 12),
        _buildFaultCard(
          'Refrigerator #2',
          'Temperature sensor malfunction',
          'High',
          Colors.orange,
          Icons.kitchen,
          'Replace temperature sensor',
          '94% confidence',
          'Detected 1 hour ago',
        ),
        const SizedBox(height: 12),
        _buildFaultCard(
          'Water Heater #1',
          'Thermostat drift detected',
          'High',
          Colors.orange,
          Icons.water_drop,
          'Calibration required',
          '91% confidence',
          'Detected 2 hours ago',
        ),
        const SizedBox(height: 12),
        _buildFaultCard(
          'Washing Machine',
          'Unusual vibration pattern',
          'Medium',
          Colors.yellow[700]!,
          Icons.local_laundry_service,
          'Schedule maintenance check',
          '87% confidence',
          'Detected 4 hours ago',
        ),
        const SizedBox(height: 12),
        _buildFaultCard(
          'HVAC System',
          'Air filter efficiency reduced',
          'Medium',
          Colors.yellow[700]!,
          Icons.air,
          'Replace air filter',
          '85% confidence',
          'Detected 6 hours ago',
        ),
        const SizedBox(height: 12),
        _buildFaultCard(
          'Microwave',
          'Power consumption deviation',
          'Medium',
          Colors.yellow[700]!,
          Icons.microwave,
          'Monitor for next 24 hours',
          '82% confidence',
          'Detected 8 hours ago',
        ),
        const SizedBox(height: 12),
        _buildFaultCard(
          'LED Lighting Circuit #3',
          'Minor voltage fluctuation',
          'Low',
          Colors.blue,
          Icons.lightbulb,
          'No action required',
          '76% confidence',
          'Detected 1 day ago',
        ),
      ],
    );
  }

  Widget _buildFaultCard(
    String device,
    String issue,
    String severity,
    Color severityColor,
    IconData icon,
    String recommendation,
    String confidence,
    String time,
  ) {
    return Card(
      elevation: 2,
      child: ExpansionTile(
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
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(issue),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    severity,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  confidence,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.recommend,
                      color: Colors.blue[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Recommendation',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  recommendation,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      color: Colors.grey[600],
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {},
                      child: const Text('Ignore'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.build, size: 16),
                      label: const Text('Schedule Fix'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: severityColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceHealthList(BuildContext context) {
    return Column(
      children: [
        _buildDeviceHealthCard(
          'Refrigerator #1',
          95,
          Colors.green,
          Icons.kitchen,
          'Excellent',
          'Operating normally',
        ),
        const SizedBox(height: 12),
        _buildDeviceHealthCard(
          'Lighting System',
          92,
          Colors.green,
          Icons.lightbulb,
          'Excellent',
          'All circuits normal',
        ),
        const SizedBox(height: 12),
        _buildDeviceHealthCard(
          'Smart Thermostat',
          88,
          Colors.green,
          Icons.thermostat,
          'Good',
          'Minor calibration drift',
        ),
        const SizedBox(height: 12),
        _buildDeviceHealthCard(
          'Water Heater #2',
          85,
          Colors.green,
          Icons.water_drop,
          'Good',
          'Performance stable',
        ),
        const SizedBox(height: 12),
        _buildDeviceHealthCard(
          'Air Conditioner #2',
          78,
          Colors.yellow[700]!,
          Icons.ac_unit,
          'Fair',
          'Efficiency decreasing',
        ),
        const SizedBox(height: 12),
        _buildDeviceHealthCard(
          'Dishwasher',
          65,
          Colors.orange,
          Icons.kitchen_outlined,
          'Poor',
          'Requires maintenance',
        ),
        const SizedBox(height: 12),
        _buildDeviceHealthCard(
          'Air Conditioner #1',
          42,
          Colors.red,
          Icons.ac_unit,
          'Critical',
          'Immediate attention needed',
        ),
      ],
    );
  }

  Widget _buildDeviceHealthCard(
    String device,
    int healthScore,
    Color color,
    IconData icon,
    String status,
    String description,
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
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '$healthScore%',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: healthScore / 100,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMLConfidenceCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: Colors.purple[700]),
                const SizedBox(width: 8),
                const Text(
                  'Machine Learning Model Stats',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildMLStatRow('Model Accuracy', '94.2%', Colors.green),
            const SizedBox(height: 16),
            _buildMLStatRow('Detection Rate', '97.8%', Colors.blue),
            const SizedBox(height: 16),
            _buildMLStatRow('False Positive Rate', '2.1%', Colors.orange),
            const SizedBox(height: 16),
            _buildMLStatRow('Training Data Points', '125K+', Colors.purple),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Model last updated: 2 days ago • Status: Optimal',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[900],
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

  Widget _buildMLStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
