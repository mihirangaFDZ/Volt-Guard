import 'package:flutter/material.dart';

/// Analytics page showing energy consumption trends and predictions
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Filter options coming soon')),
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
              // Time period selector
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildPeriodChip('Day', true),
                    const SizedBox(width: 8),
                    _buildPeriodChip('Week', false),
                    const SizedBox(width: 8),
                    _buildPeriodChip('Month', false),
                    const SizedBox(width: 8),
                    _buildPeriodChip('Year', false),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Chart placeholder
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Energy Consumption',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.show_chart,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Chart visualization coming soon',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Insights
              Text(
                'Insights & Predictions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _buildInsightCard(
                context,
                'Energy Savings',
                'You\'ve saved 15% compared to last week',
                Icons.trending_down,
                Colors.green,
              ),
              const SizedBox(height: 12),
              _buildInsightCard(
                context,
                'Peak Usage Time',
                'Your peak usage is between 7 PM - 9 PM',
                Icons.access_time,
                Colors.orange,
              ),
              const SizedBox(height: 12),
              _buildInsightCard(
                context,
                'Predicted Cost',
                'This month\'s estimated bill: \$124.50',
                Icons.attach_money,
                Colors.blue,
              ),
              const SizedBox(height: 24),
              // Anomalies
              Text(
                'Detected Anomalies',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.orange[50],
                child: ListTile(
                  leading: Icon(
                    Icons.warning_amber,
                    color: Colors.orange[700],
                    size: 32,
                  ),
                  title: const Text(
                    'Unusual Consumption Detected',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Air conditioner usage increased by 40% yesterday',
                  ),
                  trailing: TextButton(
                    onPressed: () {},
                    child: const Text('View'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodChip(String label, bool isSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        // TODO: Implement time period filter functionality
      },
    );
  }

  Widget _buildInsightCard(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 1,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(description),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.grey[400],
        ),
      ),
    );
  }
}
