import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';

abstract interface class PortraitGenerationEngine {
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  });

  Future<void> cancel();
}
