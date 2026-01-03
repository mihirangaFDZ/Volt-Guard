import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Service for managing anomalies and alerts
class AnomalyService {
  /// Get all active anomalies
  Future<List<Map<String, dynamic>>> getActiveAnomalies() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.anomaliesEndpoint}/active',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load anomalies: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching anomalies: $e');
    }
  }

  /// Get all anomalies with optional filtering
  Future<List<Map<String, dynamic>>> getAllAnomalies({
    String? severity,
    String? deviceId,
    DateTime? startDate,
    DateTime? endDate,
    bool? resolved,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (severity != null) queryParams['severity'] = severity;
      if (deviceId != null) queryParams['device_id'] = deviceId;
      if (resolved != null) queryParams['resolved'] = resolved.toString();
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.anomaliesEndpoint}',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load anomalies: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching anomalies: $e');
    }
  }

  /// Get anomaly by ID
  Future<Map<String, dynamic>> getAnomalyById(String anomalyId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.anomaliesEndpoint}/$anomalyId',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load anomaly: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching anomaly: $e');
    }
  }

  /// Get anomalies by device
  Future<List<Map<String, dynamic>>> getAnomaliesByDevice(
      String deviceId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.anomaliesEndpoint}/device/$deviceId',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception(
            'Failed to load device anomalies: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching device anomalies: $e');
    }
  }

  /// Mark anomaly as resolved
  Future<Map<String, dynamic>> resolveAnomaly(
    String anomalyId,
    String resolution,
  ) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.anomaliesEndpoint}/$anomalyId/resolve',
      );

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'resolution': resolution}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to resolve anomaly: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error resolving anomaly: $e');
    }
  }

  /// Get anomaly statistics
  Future<Map<String, dynamic>> getAnomalyStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }

      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.anomaliesEndpoint}/statistics',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to load anomaly statistics: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching anomaly statistics: $e');
    }
  }

  /// Get severity counts
  Future<Map<String, int>> getSeverityCounts() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.anomaliesEndpoint}/severity-counts',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data.map((key, value) => MapEntry(key, value as int));
      } else {
        throw Exception(
            'Failed to load severity counts: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching severity counts: $e');
    }
  }
}
