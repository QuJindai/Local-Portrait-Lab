import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_model.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_model_downloader.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_input_picker.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_models_page.dart';

class _FakeModelPicker implements PortraitModelPicker {
  @override
  Future<String?> pickModel() async => '/custom/custom.safetensors';
}

class _FakeDownloader implements PortraitModelDownloadService {
  PortraitModelSpec? requested;

  @override
  Future<void> cancel() async {}

  @override
  Stream<PortraitModelDownloadState> download(PortraitModelSpec model) async* {
    requested = model;
    yield PortraitModelDownloadProgress(model, receivedBytes: 50, totalBytes: 100);
    yield PortraitModelDownloadCompleted(
      model,
      model.isArchive ? '/models/${model.id}' : '/models/${model.fileName}',
    );
  }

  @override
  Future<String?> installedPath(PortraitModelSpec model) async => null;
}

void main() {
  testWidgets('P06 prioritizes DREAM DMD2 models and keeps fallback model usable',
      (tester) async {
    final downloader = _FakeDownloader();
    String? selectedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  selectedPath = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => PortraitModelsPage(
                        downloader: downloader,
                        customModelPicker: _FakeModelPicker(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('模型管理'), findsOneWidget);
    expect(find.text('Illustrious v16 DMD2'), findsOneWidget);
    expect(find.text('CyberRealistic v10 DMD2'), findsOneWidget);
    expect(find.text('Stable Diffusion 1.5'), findsOneWidget);
    expect(find.text('DreamShaper 8'), findsOneWidget);
    expect(find.text('Realistic Vision 6'), findsOneWidget);
    expect(find.text('导入本地 SafeTensors / CKPT'), findsOneWidget);
    expect(find.text('LCM DreamShaper 7 · FAST'), findsNothing);
    expect(
      find.byKey(const Key('model-use-dream-illustrious_v16_dmd2_qnn')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('model-download-sd15')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('model-download-sd15')));
    await tester.pumpAndSettle();
    expect(downloader.requested?.id, 'sd15');
    expect(find.byKey(const Key('model-use-sd15')), findsOneWidget);

    await tester.tap(find.byKey(const Key('model-use-sd15')));
    await tester.pumpAndSettle();
    expect(selectedPath, '/models/v1-5-pruned-emaonly.safetensors');
  });
}
