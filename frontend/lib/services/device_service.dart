import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Service for managing device data and monitoring
class DeviceService {
  /// Get all devices
  Future<List<Map<String, dynamic>>> getAllDevices() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.devicesEndpoint}',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load devices: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching devices: $e');
    }
  }

  /// Get device by ID
  Future<Map<String, dynamic>> getDeviceById(String deviceId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.devicesEndpoint}/$deviceId',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load device: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching device: $e');
    }
  }

  /// Get real-time status of all devices
  Future<List<Map<String, dynamic>>> getRealTimeDeviceStatus() async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.devicesEndpoint}/realtime',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load device status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching device status: $e');
    }
  }

  /// Get device energy consumption
  Future<Map<String, dynamic>> getDeviceConsumption({
    required String deviceId,
    String period = 'day',
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
        '${ApiConfig.apiBaseUrl}${ApiConfig.devicesEndpoint}/$deviceId/consumption',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to load device consumption: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching device consumption: $e');
    }
  }

  /// Get devices by room
  Future<List<Map<String, dynamic>>> getDevicesByRoom(String roomId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.devicesEndpoint}/room/$roomId',
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
            'Failed to load devices by room: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching devices by room: $e');
    }
  }

  /// Add new device
  Future<Map<String, dynamic>> addDevice(
      Map<String, dynamic> deviceData) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.devicesEndpoint}',
      );

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(deviceData),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to add device: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error adding device: $e');
    }
  }

  /// Update device
  Future<Map<String, dynamic>> updateDevice(
    String deviceId,
    Map<String, dynamic> deviceData,
  ) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.devicesEndpoint}/$deviceId',
      );

      final response = await http
          .put(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(deviceData),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to update device: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error updating device: $e');
    }
  }

  /// Delete device
  Future<void> deleteDevice(String deviceId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.apiBaseUrl}${ApiConfig.devicesEndpoint}/$deviceId',
      );

      final response = await http.delete(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete device: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error deleting device: $e');
    }
  }
}
