import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

/// Service for fetching AI model evaluation metrics from the backend.
/// Powers the Research Metrics panel in the Devices page.
class ModelEvaluationService {
  final AuthService _authService;

  ModelEvaluationService({AuthService? authService})
      : _authService = authService ?? AuthService();

  /// LSTM prediction quality: RMSE, MAE, R², baseline comparison.
  Future<Map<String, dynamic>> fetchLstmMetrics() async {
    return _get('${ApiConfig.modelEvaluationEndpoint}/lstm-metrics');
  }

  /// Side-by-side table: LSTM vs last-value baseline vs rolling-mean baseline.
  Future<Map<String, dynamic>> fetchModelComparison() async {
    return _get('${ApiConfig.modelEvaluationEndpoint}/model-comparison');
  }

  /// Precision, recall, F1 for Isolation Forest and Autoencoder
  /// (evaluated via synthetic anomaly injection).
  Future<Map<String, dynamic>> fetchAnomalyMetrics() async {
    return _get('${ApiConfig.modelEvaluationEndpoint}/anomaly-metrics');
  }

  /// Dataset quality report: record count, time window, occupancy rate, features.
  Future<Map<String, dynamic>> fetchDataQuality() async {
    return _get('${ApiConfig.modelEvaluationEndpoint}/data-quality');
  }

  /// Label an anomaly document as true_positive, false_positive, or unsure.
  Future<bool> labelAnomaly(String anomalyDocId, String label) async {
    try {
      final headers = await _authService.getAuthHeaders();
      headers['Content-Type'] = 'application/json';
      headers['Accept'] = 'application/json';

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.anomaliesEndpoint}/$anomalyDocId/label',
      );
      final resp = await http
          .post(uri, headers: headers, body: jsonEncode({'label': label}))
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Internal helper ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    final headers = await _authService.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw Exception('ModelEvaluationService: HTTP ${resp.statusCode} for $path');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
