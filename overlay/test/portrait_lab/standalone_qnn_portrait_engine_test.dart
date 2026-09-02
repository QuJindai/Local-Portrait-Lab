import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/native_local_diffusion_img2img_bridge.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/standalone_qnn_portrait_engine.dart';

class _FakeBackendController implements StandaloneQnnBackendController {
  StandaloneQnnBackendStart? lastStart;
  bool stopped = false;

  @override
  Future<void> start(StandaloneQnnBackendStart request) async {
    lastStart = request;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

class _FakeTransport implements StandaloneQnnGenerationTransport {
  StandaloneQnnGenerationRequest? lastRequest;
  bool cancelled = false;

  @override
  Stream<StandaloneQnnGenerationEvent> generate(
    StandaloneQnnGenerationRequest request,
  ) async* {
    lastRequest = request;
    yield const StandaloneQnnProgress(step: 1, steps: 4);
    yield const StandaloneQnnProgress(step: 4, steps: 4);
    yield StandaloneQnnComplete(Uint8List.fromList(<int>[137, 80, 78, 71]));
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
    return '/history/qnn.png';
  }
}

void main() {
  test('standalone QNN engine starts local SDXL backend and uses model config', () async {
    final root = await Directory.systemTemp.createTemp('portrait-qnn-engine-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/config.json').writeAsString(
      jsonEncode(<String, Object>{
        'default_steps': 4,
        'default_cfg': 1.0,
        'default_scheduler': 'lcm',
      }),
    );

    final backend = _FakeBackendController();
    final transport = _FakeTransport();
    final output = _FakeOutputStore();
    final engine = StandaloneQnnPortraitEngine(
      backend: backend,
      transport: transport,
      outputStore: output,
    );
    final modelUri = Uri(
      scheme: 'qnn',
      host: 'standalone',
      queryParameters: <String, String>{
        'model_id': 'cyber_realistic_v10_dmd2',
        'path': root.path,
        'type': 'sdxl',
        'size': '1024',
      },
    ).toString();
    final request = PortraitGenerationRequest.fromStyle(
      portraitPath: '/photos/person.jpg',
      modelPath: modelUri,
      style: PortraitStyle.businessPortrait,
    );
    final states = <PortraitGenerationState>[];

    final path = await engine.generate(request, onState: states.add);

    expect(path, '/history/qnn.png');
    expect(backend.lastStart?.modelId, 'cyber_realistic_v10_dmd2');
    expect(backend.lastStart?.modelDirectory, root.path);
    expect(backend.lastStart?.backendType, 'sdxl');
    expect(backend.lastStart?.generationSize, 1024);
    expect(transport.lastRequest?.steps, 4);
    expect(transport.lastRequest?.cfg, 1.0);
    expect(transport.lastRequest?.scheduler, 'lcm');
    expect(transport.lastRequest?.aspectRatio, '3:4');
    expect(transport.lastRequest?.portraitPath, request.portraitPath);
    expect(states, contains(const PortraitGenerationState.loadingModel()));
    expect(states, contains(const PortraitGenerationState.sampling(step: 4, steps: 4)));
    expect(output.bytes, isNotNull);
  });

  test('standalone QNN engine rejects a DMD2 package without config.json', () async {
    final root = await Directory.systemTemp.createTemp('portrait-qnn-no-config-');
    addTearDown(() => root.delete(recursive: true));

    final engine = StandaloneQnnPortraitEngine(
      backend: _FakeBackendController(),
      transport: _FakeTransport(),
      outputStore: _FakeOutputStore(),
    );
    final request = PortraitGenerationRequest.fromStyle(
      portraitPath: '/photos/person.jpg',
      modelPath: Uri(
        scheme: 'qnn',
        host: 'standalone',
        queryParameters: <String, String>{
          'model_id': 'illustrious_v16_dmd2',
          'path': root.path,
          'type': 'sdxl',
          'size': '1024',
        },
      ).toString(),
      style: PortraitStyle.japaneseFresh,
    );

    expect(
      () => engine.generate(request, onState: (_) {}),
      throwsA(isA<StandaloneQnnConfigurationException>()),
    );
  });
}
