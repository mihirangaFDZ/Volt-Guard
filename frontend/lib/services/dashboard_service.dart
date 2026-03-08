import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_service.dart';

class DashboardService {
  static final AuthService _authService = AuthService();

  static Future<Map<String, dynamic>> getSummary() async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.dashboardEndpoint}/summary');

    final response =
        await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
        'Failed to load dashboard (status ${response.statusCode})');
  }

  /// Fetch live-update data only (today energy, bill, devices, top device).
  /// Use for periodic refresh without reloading charts or full summary.
  static Future<Map<String, dynamic>> getLive() async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.dashboardEndpoint}/live');

    final response =
        await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
        'Failed to load live data (status ${response.statusCode})');
  }

  /// Fetch time-series energy chart data.
  /// [period] must be "day", "week", or "month".
  static Future<Map<String, dynamic>> getEnergyChart(String period) async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.dashboardEndpoint}/energy-chart?period=$period');

    final response =
        await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
        'Failed to load energy chart (status ${response.statusCode})');
  }

  /// Fetch savings comparison data (baseline vs actual in LKR).
  /// [period] must be "day", "week", or "month".
  static Future<Map<String, dynamic>> getSavings(String period) async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.dashboardEndpoint}/savings?period=$period');

    final response =
        await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
        'Failed to load savings (status ${response.statusCode})');
  }
}
