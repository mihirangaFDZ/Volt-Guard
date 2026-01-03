import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Service for managing energy consumption data
class EnergyService {
  /// Fetch energy consumption data for a specific period
  Future<Map<String, dynamic>> getEnergyData({
    String? deviceId,
    String? roomId,
    DateTime? startDate,
    DateTime? endDate,
    String period = 'day',
  }) async {
    try {
      final queryParams = <String, String>{
        'period': period,
      };

      if (deviceId != null) queryParams['device_id'] = deviceId;
      if (roomId != null) queryParams['room_id'] = roomId;
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.energyEndpoint}',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load energy data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching energy data: $e');
    }
  }

  /// Get real-time energy consumption
  Future<Map<String, dynamic>> getRealTimeConsumption() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.energyEndpoint}/realtime',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to load real-time data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching real-time data: $e');
    }
  }

  /// Get today's energy summary
  Future<Map<String, dynamic>> getTodaySummary() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.energyEndpoint}/today',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to load today\'s summary: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching today\'s summary: $e');
    }
  }

  /// Get energy statistics for a period
  Future<Map<String, dynamic>> getStatistics({
    required String period,
    DateTime? startDate,
    DateTime? endDate,
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
        '${ApiConfig.apiBaseUrl}${ApiConfig.energyEndpoint}/statistics',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load statistics: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching statistics: $e');
    }
  }

  /// Get peak hours analysis
  Future<Map<String, dynamic>> getPeakHours({DateTime? date}) async {
    try {
      final queryParams = <String, String>{};
      if (date != null) {
        queryParams['date'] = date.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.energyEndpoint}/peak-hours',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load peak hours: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching peak hours: $e');
    }
  }

  /// Get cost breakdown
  Future<Map<String, dynamic>> getCostBreakdown({
    required String period,
    DateTime? startDate,
    DateTime? endDate,
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
        '${ApiConfig.apiBaseUrl}${ApiConfig.energyEndpoint}/cost-breakdown',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to load cost breakdown: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching cost breakdown: $e');
    }
  }
}
