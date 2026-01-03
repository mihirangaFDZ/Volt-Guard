import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

/// Zone-related API calls including device management
class ZonesService {
  final AuthService _authService = AuthService();

  /// Fetch devices for a specific location/zone
  Future<List<Map<String, dynamic>>> fetchDevicesForLocation(String location) async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.devicesEndpoint}?location=${Uri.encodeComponent(location)}',
    );

    final response = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load devices for $location (status ${response.statusCode})');
  }

  /// Add a device to a specific zone/location
  Future<void> addDeviceToZone(String location, Map<String, dynamic> payload) async {
    final headers = await _authService.getAuthHeaders();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/zones/${Uri.encodeComponent(location)}/devices',
    );

    // Normalize install date to YYYY-MM-DD to satisfy backend validation
    if (payload.containsKey('installed_date') && payload['installed_date'] != null) {
      final value = payload['installed_date'].toString();
      final dateOnly = value.split('T').first;
      payload['installed_date'] = dateOnly;
    }

    final response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(ApiConfig.requestTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      final detail = response.body.isNotEmpty ? response.body : 'unknown error';
      throw Exception('Failed to add device: $detail');
    }
  }
}
