import 'dart:async';

import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';
import '../domain/portrait_style.dart';
import 'portrait_generation_engine.dart';

class PortraitGenerationCancelledException implements Exception {
  const PortraitGenerationCancelledException();

  @override
  String toString() => 'PortraitGenerationCancelledException';
}

class PortraitGenerationController {
  PortraitGenerationController(this._engine);

  final PortraitGenerationEngine _engine;
  final StreamController<PortraitGenerationState> _stateController =
      StreamController<PortraitGenerationState>.broadcast(sync: true);

  bool _running = false;
  bool _cancelled = false;
  bool _disposed = false;

  Stream<PortraitGenerationState> get states => _stateController.stream;

  Future<String> generate({
    required String portraitPath,
    required String modelPath,
    required PortraitStyle style,
  }) async {
    _ensureUsable();
    if (_running) {
      throw StateError('A portrait generation is already running.');
    }

    final request = PortraitGenerationRequest.fromStyle(
      portraitPath: portraitPath,
      modelPath: modelPath,
      style: style,
    );

    _running = true;
    _cancelled = false;
    _emit(const PortraitGenerationState.preparing());

    try {
      final outputPath = await _engine.generate(
        request,
        onState: (state) {
          if (!_cancelled) {
            _emit(state);
          }
        },
      );

      if (_cancelled) {
        throw const PortraitGenerationCancelledException();
      }

      _emit(PortraitGenerationState.completed(outputPath));
      return outputPath;
    } catch (_) {
      if (_cancelled) {
        throw const PortraitGenerationCancelledException();
      }
      rethrow;
    } finally {
      _running = false;
    }
  }

  Future<void> cancel() async {
    _ensureUsable();
    if (!_running || _cancelled) {
      return;
    }

    _cancelled = true;
    _emit(const PortraitGenerationState.cancelled());
    await _engine.cancel();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _stateController.close();
  }

  void _emit(PortraitGenerationState state) {
    if (!_disposed && !_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('PortraitGenerationController is disposed.');
    }
  }
}
