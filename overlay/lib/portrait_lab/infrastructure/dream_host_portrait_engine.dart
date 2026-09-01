import '../application/portrait_generation_engine.dart';
import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';
import 'dream_host_accelerator.dart';
import 'native_local_diffusion_img2img_bridge.dart';

class DreamHostPortraitEngine implements PortraitGenerationEngine {
  DreamHostPortraitEngine({
    required DreamHostAccelerator accelerator,
    required NativePortraitOutputStore outputStore,
  })  : _accelerator = accelerator,
        _outputStore = outputStore;

  final DreamHostAccelerator _accelerator;
  final NativePortraitOutputStore _outputStore;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    final modelId = dreamModelIdFromPath(request.modelPath);
    if (modelId == null) {
      throw ArgumentError.value(
        request.modelPath,
        'modelPath',
        'DREAM engine requires dream:// model URI.',
      );
    }

    onState(const PortraitGenerationState.loadingModel());
    final model = await _accelerator.selectModel(modelId);
    DreamHostComplete? complete;
    await for (final event in _accelerator.generate(
      DreamHostGenerationRequest(
        model: model,
        portraitPath: request.portraitPath,
        prompt: request.prompt,
        negativePrompt: request.negativePrompt,
        denoiseStrength: request.strength,
        aspectRatio: _aspectRatio(request.width, request.height),
      ),
    )) {
      switch (event) {
        case DreamHostProgress(:final step, :final steps):
          onState(PortraitGenerationState.sampling(step: step, steps: steps));
        case DreamHostComplete():
          complete = event;
      }
    }

    if (complete == null) {
      throw const DreamHostUnavailableException('DREAM 没有返回完成图像。');
    }
    return _outputStore.writePng(complete.pngBytes);
  }

  @override
  Future<void> cancel() => _accelerator.cancel();
}

String? dreamModelIdFromPath(String path) {
  const prefix = 'dream://';
  if (!path.startsWith(prefix)) return null;
  final id = path.substring(prefix.length).trim();
  return id.isEmpty ? null : id;
}

String _aspectRatio(int width, int height) {
  final divisor = _gcd(width.abs(), height.abs());
  return '${width ~/ divisor}:${height ~/ divisor}';
}

int _gcd(int a, int b) {
  if (a == 0 || b == 0) return 1;
  while (b != 0) {
    final r = a % b;
    a = b;
    b = r;
  }
  return a;
}
