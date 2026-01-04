import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

class FaultDetectionService {
  final AuthService _authService;

  FaultDetectionService({AuthService? authService})
      : _authService = authService ?? AuthService();

  Future<List<dynamic>> fetchActive({String? severity, int limit = 20}) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/active').replace(
      queryParameters: {
        if (severity != null && severity.isNotEmpty) 'severity': severity,
        'limit': '$limit',
      },
    );
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchDeviceHealth({int limit = 20}) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/device-health')
        .replace(queryParameters: {'limit': '$limit'});
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> fetchModelStats() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/model-stats');
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchTrends({int days = 7}) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/analytics/trends')
        .replace(queryParameters: {'days': '$days'});
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchPredictiveWarnings() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/analytics/predictive-warnings');
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchEnergyCorrelation({String? deviceId, int hours = 24}) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/analytics/energy-correlation')
        .replace(queryParameters: {
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      'hours': '$hours',
    });
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchFaultPatterns() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/analytics/patterns');
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchZoneHeatmap() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/analytics/zone-heatmap');
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Fetch fault history for a specific device
  Future<List<dynamic>> fetchDeviceFaultHistory(
    String deviceId, {
    int limit = 50,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.faultsEndpoint}/history')
        .replace(queryParameters: {
      'device_id': deviceId,
      'limit': '$limit',
    });
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as List<dynamic>;
  }

  /// Fetch active faults for a specific device
  Future<List<dynamic>> fetchDeviceActiveFaults(String deviceId) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final allActive = await fetchActive(limit: 100);
    // Filter by device_id on client side since API doesn't support it directly
    return allActive.where((fault) {
      return fault['device_id'] == deviceId;
    }).toList();
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Fault API failed (${resp.statusCode}): ${resp.body}');
    }
  }
}