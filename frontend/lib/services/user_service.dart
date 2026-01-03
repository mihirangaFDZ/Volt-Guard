import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

class UserService {
  final AuthService _authService;

  UserService({AuthService? authService})
      : _authService = authService ?? AuthService();

  Future<Map<String, dynamic>> getUserById(String userId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.userEndpoint}/$userId'),
        headers: {
          ...headers,
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
        return {'data': data};
      }

      return {
        'error': true,
        'statusCode': response.statusCode,
        'message': _extractErrorMessage(response.body),
      };
    } catch (e) {
      return {
        'error': true,
        'statusCode': 0,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> updateUserById(
    String userId, {
    required String name,
    required String email,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.userEndpoint}/$userId'),
            headers: {
              ...headers,
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'name': name,
              'email': email,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
        };
      }

      return {
        'success': false,
        'statusCode': response.statusCode,
        'message': _extractErrorMessage(response.body),
      };
    } catch (e) {
      return {
        'success': false,
        'statusCode': 0,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  String _extractErrorMessage(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded['detail']?.toString() ??
            decoded['message']?.toString() ??
            'Request failed';
      }
      return 'Request failed';
    } catch (_) {
      return 'Request failed';
    }
  }
}
