import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_engine.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_model.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_backend_router_engine.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_model_downloader.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_input_picker.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_models_page.dart';

class _CountingEngine implements PortraitGenerationEngine {
  int calls = 0;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    calls += 1;
    return '/out.png';
  }

  @override
  Future<void> cancel() async {}
}

class _InstalledQnnDownloader implements PortraitModelDownloadService {
  @override
  Future<void> cancel() async {}

  @override
  Stream<PortraitModelDownloadState> download(PortraitModelSpec model) async* {}

  @override
  Future<String?> installedPath(PortraitModelSpec model) async {
    if (model.id == 'cyber_realistic_v10_dmd2_qnn') {
      return '/models/cyber_realistic_v10_dmd2_qnn';
    }
    return null;
  }
}

class _NoopPicker implements PortraitModelPicker {
  @override
  Future<String?> pickModel() async => null;
}

void main() {
  test('R8 router sends qnn:// only to standalone QNN engine', () async {
    final stable = _CountingEngine();
    final dream = _CountingEngine();
    final qnn = _CountingEngine();
    final router = PortraitBackendRouterEngine(
      stableEngine: stable,
      dreamEngine: dream,
      standaloneQnnEngine: qnn,
    );

    await router.generate(
      PortraitGenerationRequest.fromStyle(
        portraitPath: '/person.jpg',
        modelPath:
            'qnn://standalone?model_id=cyber_realistic_v10_dmd2&path=%2Fmodels%2Fcyber&type=sdxl&size=1024',
        style: PortraitStyle.businessPortrait,
      ),
      onState: (_) {},
    );

    expect(qnn.calls, 1);
    expect(dream.calls, 0);
    expect(stable.calls, 0);
  });

  testWidgets('R8 installed QNN package exposes local generation selection',
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
                      downloader: _InstalledQnnDownloader(),
                      customModelPicker: _NoopPicker(),
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

    final button = find.byKey(
      const Key('model-use-local-qnn-cyber_realistic_v10_dmd2_qnn'),
    );
    await tester.scrollUntilVisible(
      button,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(button, findsOneWidget);
    expect(find.text('本机 QNN 生成'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    final uri = Uri.parse(selected!);
    expect(uri.scheme, 'qnn');
    expect(uri.host, 'standalone');
    expect(uri.queryParameters['model_id'], 'cyber_realistic_v10_dmd2');
    expect(uri.queryParameters['path'], '/models/cyber_realistic_v10_dmd2_qnn');
    expect(uri.queryParameters['type'], 'sdxl');
    expect(uri.queryParameters['size'], '1024');
  });
}
