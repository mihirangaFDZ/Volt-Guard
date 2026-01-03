import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Service for managing energy predictions and forecasts
class PredictionService {
  /// Get energy prediction for a future period
  Future<Map<String, dynamic>> getPrediction({
    String? deviceId,
    String? roomId,
    DateTime? targetDate,
    String period = 'day',
  }) async {
    try {
      final queryParams = <String, String>{
        'period': period,
      };

      if (deviceId != null) queryParams['device_id'] = deviceId;
      if (roomId != null) queryParams['room_id'] = roomId;
      if (targetDate != null) {
        queryParams['target_date'] = targetDate.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.predictionsEndpoint}',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load prediction: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching prediction: $e');
    }
  }

  /// Get tomorrow's energy prediction
  Future<Map<String, dynamic>> getTomorrowPrediction() async {
    try {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.predictionsEndpoint}/tomorrow',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load tomorrow\'s prediction: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching tomorrow\'s prediction: $e');
    }
  }

  /// Get weekly forecast
  Future<List<Map<String, dynamic>>> getWeeklyForecast() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.predictionsEndpoint}/weekly',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load weekly forecast: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching weekly forecast: $e');
    }
  }

  /// Get monthly forecast
  Future<List<Map<String, dynamic>>> getMonthlyForecast() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.predictionsEndpoint}/monthly',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load monthly forecast: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching monthly forecast: $e');
    }
  }

  /// Get device-specific prediction
  Future<Map<String, dynamic>> getDevicePrediction({
    required String deviceId,
    DateTime? targetDate,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (targetDate != null) {
        queryParams['target_date'] = targetDate.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.predictionsEndpoint}/device/$deviceId',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load device prediction: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching device prediction: $e');
    }
  }

  /// Get peak hours prediction
  Future<Map<String, dynamic>> getPeakHoursPrediction({
    DateTime? targetDate,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (targetDate != null) {
        queryParams['target_date'] = targetDate.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.predictionsEndpoint}/peak-hours',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load peak hours prediction: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching peak hours prediction: $e');
    }
  }

  /// Get cost prediction
  Future<Map<String, dynamic>> getCostPrediction({
    DateTime? startDate,
    DateTime? endDate,
    String period = 'day',
  }) async {
    try {
      final queryParams = <String, String>{
        'period': period,
      };

      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.predictionsEndpoint}/cost',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load cost prediction: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching cost prediction: $e');
    }
  }

  /// Get energy-saving recommendations
  Future<List<Map<String, dynamic>>> getRecommendations() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.predictionsEndpoint}/recommendations',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load recommendations: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching recommendations: $e');
    }
  }
}
