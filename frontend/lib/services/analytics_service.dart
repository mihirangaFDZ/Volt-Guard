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
    String? deviceId,
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
    if (deviceId != null && deviceId.isNotEmpty) {
      query['device_id'] = deviceId;
    }

    final uri =
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/latest')
            .replace(queryParameters: query);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.analyticsRequestTimeout);

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

    final uri =
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/filters');

    final response =
        await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
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
    String? deviceId,
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
    if (deviceId != null && deviceId.isNotEmpty) {
      query['device_id'] = deviceId;
    }

    final uri = Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/occupancy-stats')
        .replace(queryParameters: query);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.analyticsRequestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    }

    throw Exception('Failed to load occupancy stats (${response.statusCode})');
  }

  Future<Map<String, List<String>>> fetchEnergyFilters() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/energy-filters');

    final response =
        await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'locations': (data['locations'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
        'modules': (data['modules'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
      };
    }

    throw Exception('Failed to load energy filters (${response.statusCode})');
  }

  Future<Map<String, dynamic>> fetchCurrentEnergyStats({
    int limit = 120,
    String? module,
    String? location,
    String? deviceId,
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
    if (deviceId != null && deviceId.isNotEmpty) {
      query['device_id'] = deviceId;
    }

    final uri = Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/current-energy-stats')
        .replace(queryParameters: query);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.analyticsRequestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    }

    throw Exception(
        'Failed to load current energy stats (${response.statusCode})');
  }

  /// Fetch current energy recommendations from the trained model (CSV-dataset).
  /// Uses current_a, trend and signal from the latest reading for accurate recommendations.
  Future<List<Map<String, dynamic>>> fetchCurrentEnergyRecommendations({
    required double currentA,
    double? currentMa,
    double? powerW,
    String trendDirection = 'stable',
    double trendPercentChange = 0.0,
    String signalQuality = 'unknown',
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final query = <String, String>{
      'current_a': currentA.toString(),
      'trend_direction': trendDirection,
      'trend_percent_change': trendPercentChange.toString(),
      'signal_quality': signalQuality,
    };
    if (currentMa != null) query['current_ma'] = currentMa.toString();
    if (powerW != null) query['power_w'] = powerW.toString();

    final uri = Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/current-energy-recommendations')
        .replace(queryParameters: query);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.analyticsRequestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> recs = data['recommendations'] as List<dynamic>? ?? [];
      return recs
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  /// Fetch environment (occupancy telemetry) recommendations from the trained model.
  /// Data is read from occupancy_telemetry table (latest reading per filter).
  Future<List<Map<String, dynamic>>> fetchEnvironmentRecommendations({
    String? module,
    String? location,
    String? deviceId,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final query = <String, String>{};
    if (module != null && module.isNotEmpty) query['module'] = module;
    if (location != null && location.isNotEmpty) query['location'] = location;
    if (deviceId != null && deviceId.isNotEmpty) query['device_id'] = deviceId;

    final uri = Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/environment-recommendations')
        .replace(queryParameters: query.isNotEmpty ? query : null);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.analyticsRequestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> recs =
          data['recommendations'] as List<dynamic>? ?? [];
      return recs
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchDevices() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/device-filters');

    final response =
        await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> devices = data['devices'] as List<dynamic>;
      return devices
          .map((device) => Map<String, dynamic>.from(device as Map))
          .toList();
    }

    throw Exception('Failed to load devices (${response.statusCode})');
  }

  /// Save energy advice and recommendations with readings snapshot to history.
  Future<bool> saveEnergyAdviceHistory({
    required Map<String, dynamic> readingsSnapshot,
    required List<Map<String, dynamic>> recommendations,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/energy-advice-history');

    final response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode({
            'readings_snapshot': readingsSnapshot,
            'recommendations': recommendations,
          }),
        )
        .timeout(ApiConfig.requestTimeout);

    return response.statusCode == 200;
  }

  /// Fetch energy advice history (previous recommendations with readings).
  Future<List<Map<String, dynamic>>> fetchEnergyAdviceHistory({
    int limit = 50,
    String? since,
    String? before,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final query = <String, String>{'limit': '$limit'};
    if (since != null && since.isNotEmpty) query['since'] = since;
    if (before != null && before.isNotEmpty) query['before'] = before;

    final uri = Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/energy-advice-history')
        .replace(queryParameters: query);

    final response =
        await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> items = data['items'] as List<dynamic>? ?? [];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Delete selected energy advice history entries by id.
  Future<int> deleteEnergyAdviceHistory(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.analyticsEndpoint}/energy-advice-history');

    final response = await http
        .delete(
          uri,
          headers: headers,
          body: jsonEncode({'ids': ids}),
        )
        .timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      return data['deleted_count'] as int? ?? 0;
    }
    return 0;
  }
}
