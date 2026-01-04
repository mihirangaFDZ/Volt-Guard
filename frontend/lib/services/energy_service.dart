import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';

/// Energy-related API calls
class EnergyService {
  static final AuthService _authService = AuthService();

  /// Get energy readings for a specific location or all locations
  static Future<List<dynamic>> getEnergyReadings({
    String? location,
    int limit = 50,
  }) async {
    final headers = await _authService.getAuthHeaders();
    
    String queryString = '?limit=$limit';
    if (location != null) {
      queryString += '&location=${Uri.encodeComponent(location)}';
    }
    
    final uri = Uri.parse('${ApiConfig.baseUrl}/energy/readings$queryString');

    final response = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data;
    }
    throw Exception('Failed to get energy readings (status ${response.statusCode})');
  }

  /// Get current power for all locations
  static Future<List<dynamic>> getCurrentPower() async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse('${ApiConfig.baseUrl}/energy/current-power');

    final response = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data;
    }
    throw Exception('Failed to get current power (status ${response.statusCode})');
  }

  /// Get all energy locations
  static Future<List<dynamic>> getEnergyLocations() async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse('${ApiConfig.baseUrl}/energy/locations');

    final response = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data;
    }
    throw Exception('Failed to get energy locations (status ${response.statusCode})');
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
