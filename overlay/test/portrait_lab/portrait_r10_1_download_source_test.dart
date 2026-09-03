import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_model.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_model_downloader.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_input_picker.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_models_page.dart';

class _NoopDownloader implements PortraitModelDownloadService {
  @override
  Future<void> cancel() async {}

  @override
  Stream<PortraitModelDownloadState> download(PortraitModelSpec model) async* {}

  @override
  Future<String?> installedPath(PortraitModelSpec model) async => null;
}

class _NoopPicker implements PortraitModelPicker {
  @override
  Future<String?> pickModel() async => null;
}

void main() {
  testWidgets('R10.1 model page offers only official and hf-mirror sources',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PortraitModelsPage(
          downloader: _NoopDownloader(),
          customModelPicker: _NoopPicker(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Hugging Face 官方'), findsOneWidget);
    expect(find.text('hf-mirror 国内镜像'), findsOneWidget);
    expect(find.textContaining('自定义'), findsNothing);
  });
}
