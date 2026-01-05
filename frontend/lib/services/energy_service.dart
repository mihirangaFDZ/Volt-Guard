import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';

/// Energy-related API calls aligned with backend routes
class EnergyService {
  static final AuthService _authService = AuthService();

  /// Latest energy readings (newest first). Optional filter by location/module.
  static Future<List<dynamic>> getEnergyReadings({
    String? location,
    String? module,
    int limit = 50,
  }) async {
    final headers = await _authService.getAuthHeaders();
    final params = <String, String>{'limit': limit.toString()};
    if (location != null) params['location'] = location;
    if (module != null) params['module'] = module;

    final uri = Uri.parse('${ApiConfig.baseUrl}/energy/latest').replace(queryParameters: params);

    final response = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data;
    }
    throw Exception('Failed to get energy readings (status ${response.statusCode})');
  }

  /// Latest reading per location (one row per location).
  static Future<List<dynamic>> getLatestByLocation({String? module}) async {
    final headers = await _authService.getAuthHeaders();
    final params = <String, String>{};
    if (module != null) params['module'] = module;

    final uri = Uri.parse('${ApiConfig.baseUrl}/energy/by-location').replace(queryParameters: params);

    final response = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data;
    }
    throw Exception('Failed to get latest energy by location (status ${response.statusCode})');
  }

  /// Alias for current power per location used by dashboards.
  static Future<List<dynamic>> getCurrentPower({String? module}) {
    return getLatestByLocation(module: module);
  }

  /// Aggregated energy usage (kWh) per location using backend integration.
  static Future<Map<String, dynamic>> getEnergyUsage({String? location, String? module, int limit = 2000}) async {
    final headers = await _authService.getAuthHeaders();
    final params = <String, String>{'limit': limit.toString()};
    if (location != null) params['location'] = location;
    if (module != null) params['module'] = module;

    final uri = Uri.parse('${ApiConfig.baseUrl}/energy/usage').replace(queryParameters: params);

    final response = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    }
    throw Exception('Failed to get energy usage (status ${response.statusCode})');
  }

  /// Format current in Amperes
  static String formatCurrent(double amperes) {
    if (amperes < 0.001) {
      return '${(amperes * 1000000).toStringAsFixed(2)} µA';
    } else if (amperes < 1) {
      return '${(amperes * 1000).toStringAsFixed(2)} mA';
    } else {
      return '${amperes.toStringAsFixed(3)} A';
    }
  }

  /// Format power in Watts
  static String formatPower(double watts) {
    if (watts < 1000) {
      return '${watts.toStringAsFixed(2)} W';
    } else {
      return '${(watts / 1000).toStringAsFixed(2)} kW';
    }
  }

  /// Calculate total power from list of readings
  static double calculateTotalPower(List<dynamic> readings) {
    if (readings.isEmpty) return 0.0;
    
    double total = 0.0;
    for (final reading in readings) {
      final map = reading as Map<String, dynamic>;
      final current = (map['current_a'] as num?)?.toDouble() ?? 0.0;
      // Standard voltage: 230V
      total += current * 230.0;
    }
    return total;
  }
}
