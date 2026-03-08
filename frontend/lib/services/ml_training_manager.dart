import 'dart:async';

import 'ml_training_service.dart';

/// Singleton manager that ensures ML model training is triggered exactly once
/// at app startup and caches the training state globally.
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

  /// Trigger model training once. Subsequent calls are no-ops.
  /// Returns immediately after firing the training request — it runs
  /// in the background on the server.
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
      // First check if models are already trained
      final status = await _service.fetchStatus();
      final isAlreadyTraining = status['is_training'] == true;

      if (!isAlreadyTraining && status['last_training'] != null) {
        // Models have been trained before — mark as ready
        _isModelReady = true;
        _trainingCompleter!.complete();
        return;
      }

      if (isAlreadyTraining) {
        // Training is already in progress on the server
        _isTraining = true;
        _isModelReady = false;
        _trainingCompleter!.complete();
        return;
      }

      // No previous training — start training
      _isTraining = true;
      _trainingError = null;
      await _service.startTraining();
      // Training runs asynchronously on the server.
      // The model will become ready once the server finishes.
      _isModelReady = false;
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
      if (!_isTraining && status['last_training'] != null) {
        _isModelReady = true;
      }
      _trainingError = status['training_error'] as String?;
    } catch (e) {
      _trainingError = e.toString();
    }
  }
}
