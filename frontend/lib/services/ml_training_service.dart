import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

class MLTrainingService {
  final AuthService _authService;

  MLTrainingService({AuthService? authService})
      : _authService = authService ?? AuthService();

  Future<Map<String, dynamic>> fetchStatus() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.mlTrainingEndpoint}/status');
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> startTraining() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.mlTrainingEndpoint}/train');
    final resp = await http.post(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchModelInfo() async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.mlTrainingEndpoint}/model-info');
    final resp = await http.get(uri, headers: headers).timeout(ApiConfig.requestTimeout);
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('ML training API failed (${resp.statusCode}): ${resp.body}');
    }
  }
}
