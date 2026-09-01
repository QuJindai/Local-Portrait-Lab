import '../application/portrait_generation_engine.dart';
import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';
import 'local_diffusion_img2img_bridge.dart';
import 'local_diffusion_runtime_profile.dart';

class LocalDiffusionPortraitEngine implements PortraitGenerationEngine {
  LocalDiffusionPortraitEngine(this._bridge);

  final LocalDiffusionImg2ImgBridge _bridge;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    onState(const PortraitGenerationState.loadingModel());

    final profile = LocalDiffusionRuntimeProfile.forRequest(request);
    final command = LocalDiffusionImg2ImgCommand(
      portraitPath: request.portraitPath,
      modelPath: request.modelPath,
      prompt: request.prompt,
      negativePrompt: request.negativePrompt,
      cfgScale: profile.cfgScale,
      sampleSteps: profile.sampleSteps,
      strength: request.strength,
      outputWidth: request.width,
      outputHeight: request.height,
      seed: -1,
      sampleMethodIndex: profile.sampleMethodIndex,
    );

    return _bridge.generate(
      command,
      onProgress: (step, steps, _) {
        onState(PortraitGenerationState.sampling(step: step, steps: steps));
      },
    );
  }

  @override
  Future<void> cancel() => _bridge.cancel();
}
