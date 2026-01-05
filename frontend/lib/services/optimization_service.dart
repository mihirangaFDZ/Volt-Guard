import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

/// AI-driven energy optimization recommendations
class AIRecommendation {
  final String type;
  final String title;
  final String message;
  final double estimatedSavings; // kWh per day
  final String severity; // high, medium, low
  final String? location;
  final String? module;
  final double? currentEnergyWatts;
  final double? currentTemperature;
  final double? currentHumidity;
  final bool? isOccupied;
  final int? vacancyDurationMinutes;
  final int? rcwl;
  final int? pir;

  AIRecommendation({
    required this.type,
    required this.title,
    required this.message,
    required this.estimatedSavings,
    required this.severity,
    this.location,
    this.module,
    this.currentEnergyWatts,
    this.currentTemperature,
    this.currentHumidity,
    this.isOccupied,
    this.vacancyDurationMinutes,
    this.rcwl,
    this.pir,
  });

  factory AIRecommendation.fromJson(Map<String, dynamic> json) {
    return AIRecommendation(
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      estimatedSavings: (json['estimated_savings'] as num?)?.toDouble() ?? 0.0,
      severity: json['severity'] as String? ?? 'low',
      location: json['location'] as String?,
      module: json['module'] as String?,
      currentEnergyWatts: (json['current_energy_watts'] as num?)?.toDouble(),
      currentTemperature: (json['current_temperature'] as num?)?.toDouble(),
      currentHumidity: (json['current_humidity'] as num?)?.toDouble(),
      isOccupied: json['is_occupied'] as bool?,
      vacancyDurationMinutes: json['vacancy_duration_minutes'] as int?,
      rcwl: json['rcwl'] as int?,
      pir: json['pir'] as int?,
    );
  }
}

/// Response from optimization recommendations endpoint
class OptimizationResponse {
  final List<AIRecommendation> recommendations;
  final double? predictedEnergyWatts;
  final double? currentEnergyWatts;
  final double potentialSavingsKwhPerDay;
  final int count;
  final String? message;

  OptimizationResponse({
    required this.recommendations,
    this.predictedEnergyWatts,
    this.currentEnergyWatts,
    this.potentialSavingsKwhPerDay = 0.0,
    this.count = 0,
    this.message,
  });

  factory OptimizationResponse.fromJson(Map<String, dynamic> json) {
    return OptimizationResponse(
      recommendations: (json['recommendations'] as List<dynamic>?)
              ?.map((item) => AIRecommendation.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      predictedEnergyWatts: (json['predicted_energy_watts'] as num?)?.toDouble(),
      currentEnergyWatts: (json['current_energy_watts'] as num?)?.toDouble(),
      potentialSavingsKwhPerDay: (json['potential_savings_kwh_per_day'] as num?)?.toDouble() ?? 0.0,
      count: json['count'] as int? ?? 0,
      message: json['message'] as String?,
    );
  }
}

class OptimizationService {
  final AuthService _authService = AuthService();

  /// Fetch AI-driven energy optimization recommendations
  Future<OptimizationResponse> fetchRecommendations({
    int days = 2,
    String? location,
    String? module,
    double thresholdHigh = 1000.0,
    double thresholdLow = 100.0,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final query = <String, String>{
      'days': days.toString(),
      'threshold_high': thresholdHigh.toString(),
      'threshold_low': thresholdLow.toString(),
    };
    
    if (location != null && location.isNotEmpty) {
      query['location'] = location;
    }
    if (module != null && module.isNotEmpty) {
      query['module'] = module;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.optimizationEndpoint}/recommendations')
        .replace(queryParameters: query);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
      return OptimizationResponse.fromJson(data);
    }

    throw Exception('Failed to load AI recommendations (${response.statusCode})');
  }

  /// Predict energy consumption
  Future<Map<String, dynamic>> predictEnergy({
    int days = 1,
    String? location,
    String? module,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final query = <String, String>{
      'days': days.toString(),
    };
    
    if (location != null && location.isNotEmpty) {
      query['location'] = location;
    }
    if (module != null && module.isNotEmpty) {
      query['module'] = module;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.optimizationEndpoint}/predict')
        .replace(queryParameters: query);

    final response = await http
        .get(uri, headers: headers)
        .timeout(ApiConfig.requestTimeout);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    }

    throw Exception('Failed to predict energy (${response.statusCode})');
  }

  /// Train the AI model
  Future<Map<String, dynamic>> trainModel({
    int days = 7,
    String? location,
    String? module,
    String modelType = 'random_forest',
    double testSize = 0.2,
  }) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final query = <String, String>{
      'days': days.toString(),
      'model_type': modelType,
      'test_size': testSize.toString(),
    };
    
    if (location != null && location.isNotEmpty) {
      query['location'] = location;
    }
    if (module != null && module.isNotEmpty) {
      query['module'] = module;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.optimizationEndpoint}/train')
        .replace(queryParameters: query);

    final response = await http
        .post(uri, headers: headers)
        .timeout(const Duration(minutes: 5)); // Training can take longer

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    }

    throw Exception('Failed to train model (${response.statusCode})');
  }
}

