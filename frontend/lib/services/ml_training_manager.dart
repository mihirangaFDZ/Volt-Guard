import 'dart:async';

import 'ml_training_service.dart';

/// Singleton manager that caches ML model readiness from status checks.
///
/// Usage:
///   await MLTrainingManager.instance.ensureModelTrained();
class MLTrainingManager {
  MLTrainingManager._();
  static final MLTrainingManager instance = MLTrainingManager._();

  final MLTrainingService _service = MLTrainingService();

  bool _hasTriggeredTraining = false;
  bool _isTraining = false;
  bool _isModelReady = false;
  String? _trainingError;
  Completer<void>? _trainingCompleter;

  bool get isTraining => _isTraining;
  bool get isModelReady => _isModelReady;
  String? get trainingError => _trainingError;

  /// Fetch model status once and cache readiness.
  /// This does not auto-trigger training.
  Future<void> ensureModelTrained() async {
    if (_hasTriggeredTraining) {
      // Already triggered — wait for the in-flight request if still going.
      if (_trainingCompleter != null && !_trainingCompleter!.isCompleted) {
        await _trainingCompleter!.future;
      }
      return;
    }

    _hasTriggeredTraining = true;
    _trainingCompleter = Completer<void>();

    try {
      final status = await _service.fetchStatus();
      _isTraining = status['is_training'] == true;

      final models = status['models'] as Map<String, dynamic>?;
      final lstm = models?['prediction_lstm'] as Map<String, dynamic>?;
      final isLoaded = lstm?['loaded'] == true;
      final isTrained = lstm?['trained'] == true;
      _isModelReady = isLoaded || isTrained;

      _trainingError = status['training_error'] as String?;
      _trainingCompleter!.complete();
    } catch (e) {
      _trainingError = e.toString();
      _isTraining = false;
      if (!_trainingCompleter!.isCompleted) {
        _trainingCompleter!.complete();
      }
    }
  }

  /// Refresh the training status from the server.
  Future<void> refreshStatus() async {
    try {
      final status = await _service.fetchStatus();
      _isTraining = status['is_training'] == true;
      final models = status['models'] as Map<String, dynamic>?;
      final lstm = models?['prediction_lstm'] as Map<String, dynamic>?;
      _isModelReady = lstm?['loaded'] == true || lstm?['trained'] == true;
      _trainingError = status['training_error'] as String?;
    } catch (e) {
      _trainingError = e.toString();
    }
  }
}
