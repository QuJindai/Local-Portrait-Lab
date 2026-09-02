import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_engine.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/dream_host_accelerator.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/dream_host_portrait_engine.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/native_local_diffusion_img2img_bridge.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_backend_router_engine.dart';

class _FakeDreamAccelerator implements DreamHostAccelerator {
  String? selectedId;
  DreamHostGenerationRequest? request;
  bool cancelled = false;

  @override
  Future<DreamHostModel> selectModel(String modelId) async {
    selectedId = modelId;
    return DreamHostModel(
      id: modelId,
      name: 'DMD2',
      isSdxl: true,
      runOnCpu: false,
      generationSize: 1024,
      defaults: const DreamHostModelDefaults(
        steps: 4,
        cfg: 1.0,
        scheduler: 'lcm',
      ),
    );
  }

  @override
  Stream<DreamHostGenerationEvent> generate(DreamHostGenerationRequest value) async* {
    request = value;
    yield const DreamHostProgress(1, 4);
    yield const DreamHostProgress(4, 4);
    yield DreamHostComplete(Uint8List.fromList(<int>[137, 80, 78, 71]));
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

class _FakeOutputStore implements NativePortraitOutputStore {
  Uint8List? bytes;
  @override
  Future<String> writePng(Uint8List pngBytes) async {
    bytes = pngBytes;
    return '/history/dream.png';
  }
}

class _CountingEngine implements PortraitGenerationEngine {
  int calls = 0;
  bool cancelled = false;
  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    calls += 1;
    return '/fallback.png';
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

void main() {
  test('DREAM engine maps dream URI to QNN host and real 3:4 img2img request', () async {
    final accelerator = _FakeDreamAccelerator();
    final output = _FakeOutputStore();
    final engine = DreamHostPortraitEngine(
      accelerator: accelerator,
      outputStore: output,
    );
    final request = PortraitGenerationRequest.fromStyle(
      portraitPath: '/photos/person.jpg',
      modelPath: 'dream://illustrious_v16_dmd2',
      style: PortraitStyle.japaneseFresh,
    );
    final states = <PortraitGenerationState>[];

    final path = await engine.generate(request, onState: states.add);

    expect(path, '/history/dream.png');
    expect(accelerator.selectedId, 'illustrious_v16_dmd2');
    expect(accelerator.request!.aspectRatio, '3:4');
    expect(accelerator.request!.portraitPath, request.portraitPath);
    expect(accelerator.request!.denoiseStrength, request.strength);
    expect(states, contains(const PortraitGenerationState.loadingModel()));
    expect(states, contains(const PortraitGenerationState.sampling(step: 4, steps: 4)));
    expect(output.bytes, isNotNull);
  });

  test('backend router keeps DREAM Host and stable fallback separate from QNN', () async {
    final accelerator = _FakeDreamAccelerator();
    final dream = DreamHostPortraitEngine(
      accelerator: accelerator,
      outputStore: _FakeOutputStore(),
    );
    final fallback = _CountingEngine();
    final qnn = _CountingEngine();
    final router = PortraitBackendRouterEngine(
      stableEngine: fallback,
      dreamEngine: dream,
      standaloneQnnEngine: qnn,
    );

    await router.generate(
      PortraitGenerationRequest.fromStyle(
        portraitPath: '/p.jpg',
        modelPath: 'dream://cyber_realistic_v10_dmd2',
        style: PortraitStyle.businessPortrait,
      ),
      onState: (_) {},
    );
    expect(accelerator.selectedId, 'cyber_realistic_v10_dmd2');
    expect(fallback.calls, 0);
    expect(qnn.calls, 0);

    await router.generate(
      PortraitGenerationRequest.fromStyle(
        portraitPath: '/p.jpg',
        modelPath: '/models/realistic.safetensors',
        style: PortraitStyle.businessPortrait,
      ),
      onState: (_) {},
    );
    expect(fallback.calls, 1);
    expect(qnn.calls, 0);
  });
}
