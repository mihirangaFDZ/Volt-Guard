# Zone Manager - API Integration Guide

## Overview
This guide shows how to integrate the Zone Manager frontend with the backend API when you're ready to move from mock data to real data.

---

## 📡 Frontend API Integration Setup

### 1. Create API Service for Zones
Create a new file: `frontend/lib/services/zones_service.dart`

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';

class ZonesService {
  final String organizationId;

  ZonesService({required this.organizationId});

  // Get all zones
  Future<Map<String, dynamic>> getAllZones() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.apiBaseUrl}/zones?organization_id=$organizationId'),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load zones: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching zones: $e');
    }
  }

  // Get single zone details
  Future<Map<String, dynamic>> getZoneDetails(String zoneId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.apiBaseUrl}/zones/$zoneId'),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load zone details');
      }
    } catch (e) {
      throw Exception('Error fetching zone details: $e');
    }
  }

  // Create new zone
  Future<Map<String, dynamic>> createZone({
    required String zoneName,
    required String zoneType,
    int? floorNumber,
    String? location,
    double? areaSqMeters,
    int? capacity,
    double? monthlyBudget,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.apiBaseUrl}/zones?organization_id=$organizationId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'zone_name': zoneName,
          'zone_type': zoneType,
          'floor_number': floorNumber,
          'location': location,
          'area_sq_meters': areaSqMeters,
          'capacity': capacity,
          'monthly_budget': monthlyBudget,
        }),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to create zone');
      }
    } catch (e) {
      throw Exception('Error creating zone: $e');
    }
  }

  // Update zone
  Future<Map<String, dynamic>> updateZone(
    String zoneId, {
    String? zoneName,
    String? zoneType,
    int? floorNumber,
    double? monthlyBudget,
    String? occupancyStatus,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.apiBaseUrl}/zones/$zoneId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'zone_name': zoneName,
          'zone_type': zoneType,
          'floor_number': floorNumber,
          'monthly_budget': monthlyBudget,
          'occupancy_status': occupancyStatus,
        }),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update zone');
      }
    } catch (e) {
      throw Exception('Error updating zone: $e');
    }
  }

  // Delete zone
  Future<void> deleteZone(String zoneId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.apiBaseUrl}/zones/$zoneId'),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 204) {
        throw Exception('Failed to delete zone');
      }
    } catch (e) {
      throw Exception('Error deleting zone: $e');
    }
  }

  // Get zone cost analysis
  Future<Map<String, dynamic>> getZoneCostAnalysis(
    String zoneId, {
    String period = 'monthly',
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.apiBaseUrl}/zones/$zoneId/cost-analysis?period=$period',
        ),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load cost analysis');
      }
    } catch (e) {
      throw Exception('Error fetching cost analysis: $e');
    }
  }

  // Update occupancy status
  Future<Map<String, dynamic>> updateOccupancy(
    String zoneId,
    String status,
  ) async {
    try {
      final response = await http.put(
        Uri.parse(
          '${ApiConfig.apiBaseUrl}/zones/$zoneId/occupancy?status=$status',
        ),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update occupancy');
      }
    } catch (e) {
      throw Exception('Error updating occupancy: $e');
    }
  }

  // Power control (all_on, all_off, power_saver)
  Future<Map<String, dynamic>> zonePowerControl(
    String zoneId,
    String action,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(
          '${ApiConfig.apiBaseUrl}/zones/$zoneId/power-control?action=$action',
        ),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to execute power control');
      }
    } catch (e) {
      throw Exception('Error executing power control: $e');
    }
  }
}
```

---

## 🔄 Refactor ZonesPage to Use API

Update `frontend/lib/pages/zones_page.dart` to use real API:

```dart
import 'package:volt_guard/services/zones_service.dart';

class _ZonesPageState extends State<ZonesPage> {
  late ZonesService _zonesService;
  late List<ZoneData> zones;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // TODO: Get organization ID from auth/shared preferences
    _zonesService = ZonesService(organizationId: 'org_123');
    zones = [];
    _loadZones();
  }

  Future<void> _loadZones() async {
    setState(() => _isLoading = true);
    try {
      final response = await _zonesService.getAllZones();
      
      // Parse response into ZoneData objects
      final zoneSummary = response; // ZoneSummary.fromJson(response)
      
      setState(() {
        zones = (zoneSummary['zones'] as List)
            .map((zone) => ZoneData(
              id: zone['zone_id'],
              name: zone['zone_name'],
              type: zone['zone_type'],
              // ... map other fields
            ))
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading zones: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showAddZoneDialog() {
    final nameController = TextEditingController();
    final typeController = TextEditingController();
    final budgetController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add New Zone"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Zone Name",
                  hintText: "e.g., Classroom C",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Zone Type",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: ["Classroom", "Lab", "Office", "Corridor", "Other"]
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) typeController.text = value;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budgetController,
                decoration: InputDecoration(
                  labelText: "Monthly Budget (₹)",
                  hintText: "e.g., 2000",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.number,
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
            onPressed: () async {
              try {
                setState(() => _isLoading = true);
                
                final newZone = await _zonesService.createZone(
                  zoneName: nameController.text,
                  zoneType: typeController.text,
                  monthlyBudget: double.tryParse(budgetController.text),
                );

                Navigator.pop(context);
                _loadZones(); // Refresh list
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Zone created successfully!"),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Error creating zone: $e"),
                    backgroundColor: Colors.red,
                  ),
                );
              } finally {
                setState(() => _isLoading = false);
              }
            },
            child: const Text("Add Zone"),
          ),
        ],
      ),
    );
  }

  // Update quick action handlers
  void _handleQuickAction(String action) async {
    try {
      for (var zone in zones) {
        await _zonesService.zonePowerControl(zone.id, action);
      }
      _showActionSnackbar("${action.replaceAll('_', ' ')} executed for all zones!");
      _loadZones();
    } catch (e) {
      _showActionSnackbar("Error: $e");
    }
  }
}
```

---

## 🔐 Authentication Integration

Update API calls to include auth token:

```dart
class ZonesService {
  final String organizationId;
  final String? authToken;

  ZonesService({
    required this.organizationId,
    this.authToken,
  });

  Future<Map<String, dynamic>> getAllZones() async {
    try {
      final headers = {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

      final response = await http.get(
        Uri.parse('${ApiConfig.apiBaseUrl}/zones?organization_id=$organizationId'),
        headers: headers,
      ).timeout(ApiConfig.requestTimeout);
      
      // ... rest of method
    } catch (e) {
      // ...
    }
  }
}
```

---

## 📊 State Management with Provider

For better state management, create a Zone provider:

```dart
import 'package:provider/provider.dart';

class ZonesProvider extends ChangeNotifier {
  final ZonesService _zonesService;
  List<ZoneData> _zones = [];
  bool _isLoading = false;
  String? _error;

  ZonesProvider({required ZonesService zonesService}) 
    : _zonesService = zonesService;

  List<ZoneData> get zones => _zones;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadZones() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _zonesService.getAllZones();
      _zones = (response['zones'] as List)
          .map((z) => ZoneData.fromJson(z))
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createZone({
    required String zoneName,
    required String zoneType,
    double? monthlyBudget,
  }) async {
    try {
      await _zonesService.createZone(
        zoneName: zoneName,
        zoneType: zoneType,
        monthlyBudget: monthlyBudget,
      );
      await loadZones();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteZone(String zoneId) async {
    try {
      await _zonesService.deleteZone(zoneId);
      _zones.removeWhere((z) => z.id == zoneId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateOccupancy(String zoneId, String status) async {
    try {
      await _zonesService.updateOccupancy(zoneId, status);
      await loadZones();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> powerControl(String zoneId, String action) async {
    try {
      await _zonesService.zonePowerControl(zoneId, action);
      await loadZones();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
```

---

## 🎯 Usage in main.dart

```dart
void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ZonesProvider(
            zonesService: ZonesService(organizationId: 'org_123'),
          ),
        ),
      ],
      child: const VoltGuardApp(),
    ),
  );
}
```

---

## 📝 Update zones_page.dart to use Provider

```dart
class _ZonesPageState extends State<ZonesPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<ZonesProvider>().loadZones();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ... appBar, etc.
      body: Consumer<ZonesProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${provider.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.loadZones(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadZones(),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Use provider.zones instead of zones
                  // ... rest of UI
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

---

## ✅ Integration Checklist

- [ ] Create `zones_service.dart`
- [ ] Add ZonesService implementation with all API methods
- [ ] Create `zones_provider.dart` for state management
- [ ] Update `pubspec.yaml` to include provider package
- [ ] Refactor `zones_page.dart` to use ZonesProvider
- [ ] Test API integration with mock server
- [ ] Add error handling and retry logic
- [ ] Implement caching with shared_preferences
- [ ] Add loading spinners and progress indicators
- [ ] Test on real backend server
- [ ] Add authentication token handling

---

## 🧪 Testing the Integration

### Unit Test Example
```dart
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('ZonesService', () {
    test('getAllZones returns zone list', () async {
      final mockClient = MockHttpClient();
      final service = ZonesService(organizationId: 'test_org');
      
      // Mock the HTTP response
      when(mockClient.get(any)).thenAnswer((_) async =>
        http.Response(jsonEncode({'zones': []}), 200)
      );

      final result = await service.getAllZones();
      expect(result, isNotNull);
    });
  });
}
```

---

## 🚀 Next Steps

1. **Implement ZonesService** - Connect to real API endpoints
2. **Add ZonesProvider** - Manage zone state across app
3. **Update UI** - Replace mock data with Provider data
4. **Add real-time updates** - WebSocket for live data
5. **Implement local caching** - Store zones locally
6. **Add offline mode** - Use cached data when offline
7. **Add notifications** - Alert on budget/status changes

---

**Integration Status**: Ready to Implement  
**Estimated Time**: 4-6 hours  
**Difficulty**: Medium
