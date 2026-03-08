# AI Recommendations Frontend Integration Guide

This guide shows how to integrate AI-driven recommendations into your Flutter app.

## ✅ What's Ready

1. **Optimization Service** (`lib/services/optimization_service.dart`)
   - `fetchRecommendations()` - Get AI recommendations
   - `predictEnergy()` - Predict energy consumption
   - `trainModel()` - Train the AI model (optional)

2. **API Configuration** (`lib/services/api_config.dart`)
   - Added `optimizationEndpoint = '/optimization'`

## 📱 Integration Steps

### Option 1: Add AI Recommendations to Analytics Page

#### Step 1: Import the service

Add to `lib/pages/analytics_page.dart`:

```dart
import '../services/optimization_service.dart';
```

#### Step 2: Add state variables

In `_AnalyticsPageState` class:

```dart
final OptimizationService _optimizationService = OptimizationService();
OptimizationResponse? _aiRecommendations;
bool _loadingAIRecommendations = false;
```

#### Step 3: Load AI recommendations

In `_loadReadings()` method, add:

```dart
// Load AI recommendations (non-blocking)
try {
  setState(() {
    _loadingAIRecommendations = true;
  });
  final aiRecs = await _optimizationService.fetchRecommendations(
    days: 2,
    location: _selectedLocation,
    module: _selectedModule,
  );
  if (!mounted) return;
  setState(() {
    _aiRecommendations = aiRecs;
    _loadingAIRecommendations = false;
  });
} catch (e) {
  // Ignore errors for AI recommendations (optional feature)
  if (!mounted) return;
  setState(() {
    _loadingAIRecommendations = false;
  });
}
```

#### Step 4: Create AI Recommendations Widget

Add new method to `_AnalyticsPageState`:

```dart
Widget _buildAIRecommendations() {
  if (_loadingAIRecommendations) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            const Text('Loading AI recommendations...'),
          ],
        ),
      ),
    );
  }

  if (_aiRecommendations == null || _aiRecommendations!.recommendations.isEmpty) {
    return const SizedBox.shrink(); // Hide if no recommendations
  }

  return Card(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.psychology, color: Colors.purple),
              SizedBox(width: 8),
              Text(
                'AI Energy Recommendations',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (_aiRecommendations!.potentialSavingsKwhPerDay > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.savings, color: Colors.green[700], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Potential savings: ${_aiRecommendations!.potentialSavingsKwhPerDay.toStringAsFixed(2)} kWh/day',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ..._aiRecommendations!.recommendations.map((rec) => _buildAIRecommendationTile(rec)),
        ],
      ),
    ),
  );
}

Widget _buildAIRecommendationTile(AIRecommendation rec) {
  Color severityColor;
  IconData iconData;
  
  switch (rec.severity.toLowerCase()) {
    case 'high':
      severityColor = Colors.red;
      iconData = Icons.priority_high;
      break;
    case 'medium':
      severityColor = Colors.orange;
      iconData = Icons.info;
      break;
    default:
      severityColor = Colors.blue;
      iconData = Icons.lightbulb_outline;
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: severityColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(iconData, color: severityColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rec.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: severityColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      rec.severity.toUpperCase(),
                      style: TextStyle(
                        color: severityColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                rec.message,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
              if (rec.estimatedSavings > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.savings, size: 14, color: Colors.green[700]),
                    const SizedBox(width: 4),
                    Text(
                      '${rec.estimatedSavings.toStringAsFixed(2)} kWh/day',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
```

#### Step 5: Add to build method

In `_buildBody()` method, add AI recommendations section:

```dart
_buildRecommendations(),  // Existing rule-based recommendations
const SizedBox(height: 16),
_buildAIRecommendations(),  // New AI recommendations
const SizedBox(height: 16),
```

### Option 2: Create Separate AI Recommendations Page

Create a new page `lib/pages/ai_recommendations_page.dart`:

```dart
import 'package:flutter/material.dart';
import '../services/optimization_service.dart';

class AIRecommendationsPage extends StatefulWidget {
  const AIRecommendationsPage({super.key});

  @override
  State<AIRecommendationsPage> createState() => _AIRecommendationsPageState();
}

class _AIRecommendationsPageState extends State<AIRecommendationsPage> {
  final OptimizationService _service = OptimizationService();
  OptimizationResponse? _recommendations;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final recs = await _service.fetchRecommendations(days: 2);
      setState(() {
        _recommendations = recs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Energy Recommendations'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecommendations,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRecommendations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_recommendations == null || _recommendations!.recommendations.isEmpty) {
      return const Center(
        child: Text('No recommendations available'),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Potential Savings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_recommendations!.potentialSavingsKwhPerDay.toStringAsFixed(2)} kWh/day',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
                if (_recommendations!.currentEnergyWatts != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Current: ${_recommendations!.currentEnergyWatts!.toStringAsFixed(2)} W',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Recommendations list
        ..._recommendations!.recommendations.map((rec) => _buildRecommendationCard(rec)),
      ],
    );
  }

  Widget _buildRecommendationCard(AIRecommendation rec) {
    // Similar to _buildAIRecommendationTile above
    // ... (implementation same as above)
  }
}
```

## 🎨 Styling Recommendations

- **High Priority**: Red background, priority icon
- **Medium Priority**: Orange background, info icon
- **Low Priority**: Blue background, lightbulb icon

## 🔧 Testing

1. **Test API Connection**
   ```dart
   final service = OptimizationService();
   final recs = await service.fetchRecommendations();
   print('Recommendations: ${recs.count}');
   ```

2. **Handle Errors Gracefully**
   - Show fallback to rule-based recommendations if AI fails
   - Log errors for debugging
   - Don't block UI if AI recommendations fail

## 📝 Notes

- AI recommendations are **optional** - app works without them
- Consider caching recommendations to reduce API calls
- Refresh recommendations on pull-to-refresh
- Show loading state while fetching

---

**Ready to integrate!** Choose the option that fits your app architecture.

