import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/local_diffusion_img2img_bridge.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/local_diffusion_portrait_engine.dart';

class FakeLocalDiffusionImg2ImgBridge implements LocalDiffusionImg2ImgBridge {
  LocalDiffusionImg2ImgCommand? lastCommand;
  bool cancelCalled = false;
  String outputPath = '/tmp/native-result.png';

  @override
  Future<String> generate(
    LocalDiffusionImg2ImgCommand command, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  }) async {
    lastCommand = command;
    onProgress(1, command.sampleSteps, 0.25);
    onProgress(command.sampleSteps, command.sampleSteps, 1.0);
    return outputPath;
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
  }
}

void main() {
  test('maps standard portrait request into Local-Diffusion img2img command', () async {
    final request = PortraitGenerationRequest.fromStyle(
      portraitPath: '/tmp/person.jpg',
      modelPath: '/models/portrait.safetensors',
      style: PortraitStyle.japaneseFresh,
    );
    final bridge = FakeLocalDiffusionImg2ImgBridge();
    final engine = LocalDiffusionPortraitEngine(bridge);
    final states = <PortraitGenerationState>[];

    final output = await engine.generate(request, onState: states.add);

    expect(output, '/tmp/native-result.png');
    expect(bridge.lastCommand, isNotNull);
    expect(bridge.lastCommand!.portraitPath, request.portraitPath);
    expect(bridge.lastCommand!.modelPath, request.modelPath);
    expect(bridge.lastCommand!.prompt, request.prompt);
    expect(bridge.lastCommand!.negativePrompt, request.negativePrompt);
    expect(bridge.lastCommand!.cfgScale, request.cfgScale);
    expect(bridge.lastCommand!.sampleSteps, request.steps);
    expect(bridge.lastCommand!.strength, request.strength);
    expect(bridge.lastCommand!.outputWidth, request.width);
    expect(bridge.lastCommand!.outputHeight, request.height);
    expect(bridge.lastCommand!.seed, -1);
    expect(bridge.lastCommand!.sampleMethodIndex, 0);
    expect(
      states,
      containsAllInOrder(<PortraitGenerationState>[
        const PortraitGenerationState.loadingModel(),
        PortraitGenerationState.sampling(step: 1, steps: request.steps),
        PortraitGenerationState.sampling(step: request.steps, steps: request.steps),
      ]),
    );
  });

  test('LCM checkpoint maps to six-step CFG1 LCM native command', () async {
    final request = PortraitGenerationRequest.fromStyle(
      portraitPath: '/tmp/person.jpg',
      modelPath: '/models/LCM_Dreamshaper_v7_4k.safetensors',
      style: PortraitStyle.japaneseFresh,
    );
    final bridge = FakeLocalDiffusionImg2ImgBridge();
    final engine = LocalDiffusionPortraitEngine(bridge);

    await engine.generate(request, onState: (_) {});

    expect(bridge.lastCommand!.sampleMethodIndex, 9);
    expect(bridge.lastCommand!.sampleSteps, 6);
    expect(bridge.lastCommand!.cfgScale, 1.0);
    expect(bridge.lastCommand!.strength, request.strength);
  });

  test('cancel delegates to the active Local-Diffusion bridge', () async {
    final bridge = FakeLocalDiffusionImg2ImgBridge();
    final engine = LocalDiffusionPortraitEngine(bridge);

    await engine.cancel();

    expect(bridge.cancelCalled, isTrue);
  });
}
