import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import '../models/sensor_reading.dart';
import 'api_config.dart';
import 'auth_service.dart';

class AnalyticsService {
  final AuthService _authService = AuthService();

  Future<List<SensorReading>> fetchLatestReadings({
    int limit = 50,
    String? module,
    String? location,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final query = <String, String>{'limit': '$limit'};
    if (module != null && module.isNotEmpty) {
      query['module'] = module;
    }
    if (location != null && location.isNotEmpty) {
      query['location'] = location;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/latest')
        .replace(queryParameters: query);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => SensorReading.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    throw Exception('Failed to load analytics (${response.statusCode})');
  }

  Future<Map<String, List<String>>> fetchAvailableFilters() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/filters');

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'locations': (data['locations'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
        'modules': (data['modules'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      };
    }

    throw Exception('Failed to load filters (${response.statusCode})');
  }

  Future<Map<String, dynamic>> fetchOccupancyStats({
    int limit = 50,
    String? module,
    String? location,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final query = <String, String>{'limit': '$limit'};
    if (module != null && module.isNotEmpty) {
      query['module'] = module;
    }
    if (location != null && location.isNotEmpty) {
      query['location'] = location;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/occupancy-stats')
        .replace(queryParameters: query);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    }

    throw Exception('Failed to load occupancy stats (${response.statusCode})');
  }
}
