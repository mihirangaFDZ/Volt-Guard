import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

class PredictionService {
  final AuthService _authService;

  PredictionService({AuthService? authService})
      : _authService = authService ?? AuthService();

  /// Fetch a weekly energy forecast from the LSTM model.
  /// Returns daily breakdown with predicted kWh per day and weekly total.
  Future<Map<String, dynamic>> fetchWeeklyForecast({String? location}) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final params = <String, String>{};
    if (location != null) params['location'] = location;

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.predictionEndpoint}/weekly-forecast',
    ).replace(queryParameters: params.isNotEmpty ? params : null);

    final resp = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 60), // forecasts can be slow
    );
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Fetch a short-term energy prediction (up to 24 hours ahead).
  Future<Map<String, dynamic>> fetchPrediction({
    String? location,
    int hoursAhead = 24,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final params = <String, String>{
      'hours_ahead': hoursAhead.toString(),
    };
    if (location != null) params['location'] = location;

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.predictionEndpoint}/predict',
    ).replace(queryParameters: params);

    final resp = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 30),
    );
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Fetch a device-specific 7-day forecast with historical comparison,
  /// risk level, and cost projections.
  Future<Map<String, dynamic>> fetchDeviceForecast(
    String deviceId, {
    double ratePerKwh = 42.5,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final params = <String, String>{
      'rate_per_kwh': ratePerKwh.toString(),
    };

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.predictionEndpoint}/device-forecast/$deviceId',
    ).replace(queryParameters: params);

    final resp = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 90),
    );
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Fetch ranked comparison of all devices by predicted weekly consumption.
  Future<Map<String, dynamic>> fetchDeviceComparison({
    double ratePerKwh = 42.5,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final params = <String, String>{
      'rate_per_kwh': ratePerKwh.toString(),
    };

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.predictionEndpoint}/device-comparison',
    ).replace(queryParameters: params);

    final resp = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 120),
    );
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Prediction API failed (${resp.statusCode}): ${resp.body}');
    }
  }
}
