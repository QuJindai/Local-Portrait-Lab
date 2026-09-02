import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_controller.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_engine.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_model.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/native_local_diffusion_img2img_bridge.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_active_model_store.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_model_downloader.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/standalone_qnn_portrait_engine.dart';
import 'package:local_diffusion/portrait_lab/portrait_lab_app.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_input_picker.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_models_page.dart';

class _IdleEngine implements PortraitGenerationEngine {
  @override
  Future<void> cancel() async {}

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async => '/tmp/out.png';
}

class _NoopPhotoPicker implements PortraitPhotoPicker {
  @override
  Future<String?> pickPortrait() async => null;
}

class _NoopModelPicker implements PortraitModelPicker {
  @override
  Future<String?> pickModel() async => null;
}

class _MemoryActiveModelStore implements PortraitActiveModelStore {
  _MemoryActiveModelStore(this.value);

  String? value;

  @override
  Future<String?> loadSelection() async => value;

  @override
  Future<void> saveSelection(String selection) async {
    value = selection;
  }

  @override
  Future<void> clearSelection() async {
    value = null;
  }
}

class _InstalledCyberDownloader implements PortraitModelDownloadService {
  _InstalledCyberDownloader({this.completeOnDownload = false});

  final bool completeOnDownload;

  @override
  Future<void> cancel() async {}

  @override
  Stream<PortraitModelDownloadState> download(PortraitModelSpec model) async* {
    if (completeOnDownload && model.id == 'cyber_realistic_v10_dmd2_qnn') {
      yield PortraitModelDownloadCompleted(
        model,
        '/models/cyber_realistic_v10_dmd2_qnn',
      );
    }
  }

  @override
  Future<String?> installedPath(PortraitModelSpec model) async {
    if (!completeOnDownload && model.id == 'cyber_realistic_v10_dmd2_qnn') {
      return '/models/cyber_realistic_v10_dmd2_qnn';
    }
    return null;
  }
}

class _FakeBackendController implements StandaloneQnnBackendController {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start(StandaloneQnnBackendStart request) async {
    starts += 1;
  }

  @override
  Future<void> stop() async {
    stops += 1;
  }
}

class _FlakyTransport implements StandaloneQnnGenerationTransport {
  int generateCalls = 0;

  @override
  Stream<StandaloneQnnGenerationEvent> generate(
    StandaloneQnnGenerationRequest request,
  ) async* {
    generateCalls += 1;
    if (generateCalls == 1) {
      throw const StandaloneQnnBackendException(
        '本机 QNN 生成服务不可用：Connection refused',
      );
    }
    yield StandaloneQnnProgress(step: 1, steps: request.steps);
    yield StandaloneQnnComplete(
      Uint8List.fromList(<int>[137, 80, 78, 71]),
    );
  }

  @override
  Future<void> cancel() async {}
}

class _OutputStore implements NativePortraitOutputStore {
  @override
  Future<String> writePng(Uint8List pngBytes) async => '/history/r10.png';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('R10 active model selection persists atomically across app restarts', () async {
    final root = await Directory.systemTemp.createTemp('portrait-r10-model-store-');
    addTearDown(() => root.delete(recursive: true));
    final store = FilePortraitActiveModelStore(
      rootDirectoryProvider: () async => root,
    );
    const selection =
        'qnn://standalone?model_id=cyber_realistic_v10_dmd2&path=%2Fmodels%2Fcyber_realistic_v10_dmd2_qnn&type=sdxl&size=1024';

    await store.saveSelection(selection);

    expect(await store.loadSelection(), selection);
    await store.clearSelection();
    expect(await store.loadSelection(), isNull);
  });

  testWidgets('R10 home restores installed QNN model and shows real NPU backend',
      (tester) async {
    const selection =
        'qnn://standalone?model_id=cyber_realistic_v10_dmd2&path=%2Fmodels%2Fcyber_realistic_v10_dmd2_qnn&type=sdxl&size=1024';
    final store = _MemoryActiveModelStore(selection);
    final controller = PortraitGenerationController(_IdleEngine());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      PortraitLabApp(
        controller: controller,
        photoPicker: _NoopPhotoPicker(),
        modelPicker: _NoopModelPicker(),
        modelDownloader: _InstalledCyberDownloader(),
        activeModelStore: store,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    expect(find.text('CyberRealistic v10 DMD2'), findsOneWidget);
    expect(find.text('NPU · QNN/HTP'), findsOneWidget);
    expect(find.text('GPU · Vulkan'), findsNothing);
  });

  testWidgets('R10 completed QNN download immediately activates the local model',
      (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => PortraitModelsPage(
                      downloader: _InstalledCyberDownloader(completeOnDownload: true),
                      customModelPicker: _NoopModelPicker(),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final download = find.byKey(
      const Key('model-download-cyber_realistic_v10_dmd2_qnn'),
    );
    await tester.scrollUntilVisible(
      download,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(download);
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(Uri.parse(selected!).scheme, 'qnn');
    expect(Uri.parse(selected!).queryParameters['model_id'], 'cyber_realistic_v10_dmd2');
  });

  test('R10 QNN controller ignores stale running snapshot using request token',
      () async {
    const channel = MethodChannel('com.qujindai.localportraitlab/qnn_backend');
    final calls = <MethodCall>[];
    var started = false;
    var postStartStatus = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'status':
          if (!started) {
            return <String, Object?>{
              'state': 'running',
              'modelId': 'cyber_realistic_v10_dmd2',
              'requestToken': 'old-token',
            };
          }
          postStartStatus += 1;
          if (postStartStatus == 1) {
            return <String, Object?>{
              'state': 'running',
              'modelId': 'cyber_realistic_v10_dmd2',
              'requestToken': 'old-token',
            };
          }
          if (postStartStatus == 2) {
            return <String, Object?>{
              'state': 'starting',
              'modelId': 'cyber_realistic_v10_dmd2',
              'requestToken': 'r10-token',
            };
          }
          return <String, Object?>{
            'state': 'running',
            'modelId': 'cyber_realistic_v10_dmd2',
            'requestToken': 'r10-token',
          };
        case 'health':
          return started;
        case 'start':
          started = true;
          return null;
      }
      throw PlatformException(code: 'unexpected', message: call.method);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final controller = AndroidStandaloneQnnBackendController(
      channel: channel,
      pollInterval: Duration.zero,
      startTimeout: const Duration(milliseconds: 200),
      requestTokenFactory: () => 'r10-token',
    );

    await controller.start(
      const StandaloneQnnBackendStart(
        modelId: 'cyber_realistic_v10_dmd2',
        modelDirectory: '/models/cyber',
        backendType: 'sdxl',
        generationSize: 1024,
      ),
    );

    final start = calls.singleWhere((call) => call.method == 'start');
    final args = Map<Object?, Object?>.from(start.arguments as Map);
    expect(args['requestToken'], 'r10-token');
    expect(postStartStatus, greaterThanOrEqualTo(3));
  });

  test('R10 healthy same-model QNN backend is reused without restart', () async {
    const channel = MethodChannel('com.qujindai.localportraitlab/qnn_backend');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'status') {
        return <String, Object?>{
          'state': 'running',
          'modelId': 'cyber_realistic_v10_dmd2',
          'requestToken': 'previous-token',
        };
      }
      if (call.method == 'health') return true;
      if (call.method == 'start') return null;
      throw PlatformException(code: 'unexpected', message: call.method);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final controller = AndroidStandaloneQnnBackendController(
      channel: channel,
      pollInterval: Duration.zero,
      startTimeout: const Duration(milliseconds: 200),
      requestTokenFactory: () => 'unused-token',
    );
    await controller.start(
      const StandaloneQnnBackendStart(
        modelId: 'cyber_realistic_v10_dmd2',
        modelDirectory: '/models/cyber',
        backendType: 'sdxl',
        generationSize: 1024,
      ),
    );

    expect(calls.where((call) => call.method == 'start'), isEmpty);
    expect(calls.where((call) => call.method == 'health'), hasLength(1));
  });

  test('R10 standalone QNN retries once after transient connection refusal',
      () async {
    final root = await Directory.systemTemp.createTemp('portrait-r10-qnn-retry-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/config.json').writeAsString(
      jsonEncode(<String, Object>{
        'default_steps': 8,
        'default_cfg': 1.0,
        'default_scheduler': 'lcm',
      }),
    );
    final backend = _FakeBackendController();
    final transport = _FlakyTransport();
    final engine = StandaloneQnnPortraitEngine(
      backend: backend,
      transport: transport,
      outputStore: _OutputStore(),
    );
    final modelPath = Uri(
      scheme: 'qnn',
      host: 'standalone',
      queryParameters: <String, String>{
        'model_id': 'cyber_realistic_v10_dmd2',
        'path': root.path,
        'type': 'sdxl',
        'size': '1024',
      },
    ).toString();

    final output = await engine.generate(
      PortraitGenerationRequest.fromStyle(
        portraitPath: '/photos/person.jpg',
        modelPath: modelPath,
        style: PortraitStyle.ancientChinese,
      ),
      onState: (_) {},
    );

    expect(output, '/history/r10.png');
    expect(transport.generateCalls, 2);
    expect(backend.starts, 2);
    expect(backend.stops, 1);
  });
}
