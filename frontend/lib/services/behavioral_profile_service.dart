import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

class BehavioralProfileService {
  final AuthService _authService;

  BehavioralProfileService({AuthService? authService})
      : _authService = authService ?? AuthService();

  Future<Map<String, dynamic>> fetchAllProfiles({
    int hoursBack = 168,
    String? location,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final params = <String, String>{'hours_back': hoursBack.toString()};
    if (location != null) params['location'] = location;

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.behavioralProfilesEndpoint}/',
    ).replace(queryParameters: params);

    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchDeviceProfile(
    String deviceId, {
    int hoursBack = 168,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.behavioralProfilesEndpoint}/$deviceId',
    ).replace(queryParameters: {'hours_back': hoursBack.toString()});

    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Energy vampires endpoint can be slow (168h analysis). Use longer timeout.
  static const Duration _energyVampiresTimeout = Duration(seconds: 60);

  Future<Map<String, dynamic>> fetchEnergyVampires({
    int hoursBack = 168,
    String? location,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final params = <String, String>{'hours_back': hoursBack.toString()};
    if (location != null) params['location'] = location;

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.behavioralProfilesEndpoint}/energy-vampires',
    ).replace(queryParameters: params);

    final resp = await http.get(uri, headers: headers).timeout(_energyVampiresTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Behavioral profile API failed (${resp.statusCode}): ${resp.body}');
    }
  }
}
