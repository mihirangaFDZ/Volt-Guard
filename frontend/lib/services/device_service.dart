import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';
import '../models/energy_reading.dart';

class DeviceService {
  final AuthService _authService;

  DeviceService({AuthService? authService})
      : _authService = authService ?? AuthService();

  /// Fetch all devices
  Future<List<Map<String, dynamic>>> fetchDevices() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.devicesEndpoint}');
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((item) => item as Map<String, dynamic>).toList();
  }

  /// Fetch energy readings for a specific device
  /// [hours] - Optional time range in hours (6, 24, 168 for 7 days)
  Future<Map<String, dynamic>> fetchDeviceEnergyReadings(
    String deviceId, {
    int limit = 1000,
    int? hours,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final queryParams = <String, String>{'limit': '$limit'};
    if (hours != null) {
      queryParams['hours'] = '$hours';
    }
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.devicesEndpoint}/$deviceId/energy-readings',
    ).replace(queryParameters: queryParams);
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    final Map<String, dynamic> data = jsonDecode(resp.body) as Map<String, dynamic>;
    
    // Parse readings into EnergyReading objects
    final List<dynamic> readingsJson = data['readings'] as List<dynamic>? ?? [];
    final List<EnergyReading> readings = readingsJson
        .map((item) => EnergyReading.fromJson(item as Map<String, dynamic>))
        .toList();
    
    return {
      'device_id': data['device_id'] as String?,
      'module_id': data['module_id'] as String?,
      'readings': readings,
      'count': data['count'] as int? ?? 0,
    };
  }

  /// Add a new device
  Future<Map<String, dynamic>> addDevice(Map<String, dynamic> deviceData) async {
    final headers = await _authService.getAuthHeaders();
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = 'application/json';
    // Add trailing slash to avoid 307 redirect
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.devicesEndpoint}/');
    final resp = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(deviceData),
    ).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Device API failed (${resp.statusCode}): ${resp.body}');
    }
  }
}

