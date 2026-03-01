import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

class AnomalyAlertService {
  final AuthService _authService;

  AnomalyAlertService({AuthService? authService})
      : _authService = authService ?? AuthService();

  /// Fetch recent anomaly alerts formatted for the mobile app.
  Future<Map<String, dynamic>> fetchRecentAlerts({
    int limit = 20,
    int hoursBack = 24,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.anomaliesEndpoint}/recent-alerts',
    ).replace(queryParameters: {
      'limit': limit.toString(),
      'hours_back': hoursBack.toString(),
    });

    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Fetch active anomaly alerts with optional severity filter.
  Future<List<dynamic>> fetchActiveAlerts({
    String? severity,
    int limit = 50,
    int hoursBack = 168,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final params = <String, String>{
      'limit': limit.toString(),
      'hours_back': hoursBack.toString(),
    };
    if (severity != null) params['severity'] = severity;

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.anomaliesEndpoint}/active',
    ).replace(queryParameters: params);

    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as List<dynamic>;
  }

  /// Fetch anomaly statistics.
  Future<Map<String, dynamic>> fetchStats({int days = 7}) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.anomaliesEndpoint}/stats',
    ).replace(queryParameters: {'days': days.toString()});

    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Anomaly API failed (${resp.statusCode}): ${resp.body}');
    }
  }
}
