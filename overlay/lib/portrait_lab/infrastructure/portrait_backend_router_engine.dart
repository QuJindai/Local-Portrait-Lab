import '../application/portrait_generation_engine.dart';
import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';

class PortraitBackendRouterEngine implements PortraitGenerationEngine {
  PortraitBackendRouterEngine({
    required PortraitGenerationEngine stableEngine,
    required PortraitGenerationEngine dreamEngine,
    required PortraitGenerationEngine standaloneQnnEngine,
  })  : _stableEngine = stableEngine,
        _dreamEngine = dreamEngine,
        _standaloneQnnEngine = standaloneQnnEngine;

  final PortraitGenerationEngine _stableEngine;
  final PortraitGenerationEngine _dreamEngine;
  final PortraitGenerationEngine _standaloneQnnEngine;
  PortraitGenerationEngine? _active;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    final engine = switch (Uri.tryParse(request.modelPath)?.scheme) {
      'dream' => _dreamEngine,
      'qnn' => _standaloneQnnEngine,
      _ => _stableEngine,
    };
    _active = engine;
    try {
      return await engine.generate(request, onState: onState);
    } finally {
      if (identical(_active, engine)) _active = null;
    }
  }

  @override
  Future<void> cancel() async {
    final active = _active;
    if (active != null) await active.cancel();
  }
}
