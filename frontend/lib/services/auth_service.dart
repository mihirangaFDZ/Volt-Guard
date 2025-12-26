// lib/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'dart:async';

class AuthService {
  static const String _tokenKey = 'access_token';
  static const String _userNameKey = 'user_name';
  static const String _userIdKey = 'user_id';

  /// Login user with email and password
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.authEndpoint}'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Store token and user name
        await saveToken(data['access_token']);
        await saveUserName(data['user_name']);
        if (data['user_id'] != null) {
          await saveUserId(data['user_id'].toString());
        }

        return {
          'success': true,
          'data': data,
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Invalid email or password',
        };
      } else {
        return {
          'success': false,
          'message': 'Login failed. Please try again.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: $e',
      };
    }
  }

  /// Register a new user account
  Future<Map<String, dynamic>> signup(
    String name,
    String email,
    String password, {
    String role = 'user',
  }) async {
    final payload = {
      'user_id': _generateUserId(),
      'name': name,
      'email': email,
      'role': role,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'password': password,
    };

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.signupEndpoint}'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == false) {
          return {
            'success': false,
            'message': data['message'] ?? 'Signup failed. Please try again.',
          };
        }
        return {
          'success': true,
          'data': data,
        };
      }

      return {
        'success': false,
        'message': _extractErrorMessage(response.body),
      };
    } on TimeoutException {
      return {
        'success': false,
        'message': 'Signup request timed out. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: $e',
      };
    }
  }

  /// Save access token to local storage
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Save user name to local storage
  Future<void> saveUserName(String userName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, userName);
  }

  /// Save user id to local storage
  Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
  }

  /// Get stored access token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Get stored user name
  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  /// Get stored user id
  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Logout user
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userIdKey);
  }

  /// Get authorization header for API requests
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ""}',
    };
  }

  String _generateUserId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'USR$timestamp';
  }

  String _extractErrorMessage(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      return decoded['detail'] ??
          decoded['message'] ??
          'Signup failed. Please try again.';
    } catch (_) {
      return 'Signup failed. Please try again.';
    }
  }
}
