import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_controller.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_engine.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/android_portrait_gallery_exporter.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_gallery_exporter.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_result_page.dart';

class _IdleEngine implements PortraitGenerationEngine {
  @override
  Future<void> cancel() async {}

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async => '/tmp/unused.png';
}

class _SequenceExporter implements PortraitGalleryExporter {
  _SequenceExporter(this.responses);

  final List<Object> responses;
  final List<String> exportedPaths = <String>[];
  final List<PortraitGalleryExportResult> opened = <PortraitGalleryExportResult>[];

  @override
  Future<PortraitGalleryExportResult> export(String sourcePath) async {
    exportedPaths.add(sourcePath);
    final response = responses.removeAt(0);
    if (response is Exception) throw response;
    return response as PortraitGalleryExportResult;
  }

  @override
  Future<void> open(PortraitGalleryExportResult result) async {
    opened.add(result);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('R9 Android gallery bridge returns verified MediaStore receipt', () async {
    const channel = MethodChannel('com.qujindai.localportraitlab/gallery');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'export') {
        return <String, Object?>{
          'uri': 'content://media/external/images/media/42',
          'displayName': 'portrait_42.png',
          'relativePath': 'Pictures/Portrait Lab',
          'mimeType': 'image/png',
        };
      }
      if (call.method == 'open') return null;
      throw PlatformException(code: 'unexpected', message: call.method);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const exporter = AndroidPortraitGalleryExporter(channel: channel);
    final receipt = await exporter.export('/private/result.png');

    expect(receipt.uri, 'content://media/external/images/media/42');
    expect(receipt.relativePath, 'Pictures/Portrait Lab');
    expect(receipt.displayName, 'portrait_42.png');
    expect(receipt.mimeType, 'image/png');
    expect(calls.single.method, 'export');
    expect(
      Map<Object?, Object?>.from(calls.single.arguments as Map)['sourcePath'],
      '/private/result.png',
    );

    await exporter.open(receipt);
    expect(calls.last.method, 'open');
  });

  testWidgets('R9 result page auto-exports once and only claims gallery save after receipt',
      (tester) async {
    final receipt = const PortraitGalleryExportResult(
      uri: 'content://media/external/images/media/7',
      displayName: 'portrait_7.png',
      relativePath: 'Pictures/Portrait Lab',
      mimeType: 'image/png',
    );
    final exporter = _SequenceExporter(<Object>[receipt]);
    final controller = PortraitGenerationController(_IdleEngine());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PortraitResultPage(
          controller: controller,
          portraitPath: '/tmp/source.jpg',
          modelPath: '/tmp/model.safetensors',
          style: PortraitStyle.japaneseFresh,
          outputPath: '/tmp/generated.png',
          galleryExporter: exporter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(exporter.exportedPaths, <String>['/tmp/generated.png']);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(find.textContaining('已保存到系统相册'), findsOneWidget);
    expect(find.textContaining('Pictures/Portrait Lab'), findsWidgets);
    expect(find.byKey(const Key('portrait-open-gallery-result')), findsOneWidget);

    await tester.tap(find.byKey(const Key('portrait-open-gallery-result')));
    await tester.pump();
    expect(exporter.opened, <PortraitGalleryExportResult>[receipt]);
  });

  testWidgets('R9 save failure is honest and retry can reach a verified gallery receipt',
      (tester) async {
    final receipt = const PortraitGalleryExportResult(
      uri: 'content://media/external/images/media/9',
      displayName: 'portrait_9.png',
      relativePath: 'Pictures/Portrait Lab',
      mimeType: 'image/png',
    );
    final exporter = _SequenceExporter(<Object>[
      const PortraitGalleryExportException('MediaStore insert failed'),
      receipt,
    ]);
    final controller = PortraitGenerationController(_IdleEngine());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: PortraitResultPage(
          controller: controller,
          portraitPath: '/tmp/source.jpg',
          modelPath: '/tmp/model.safetensors',
          style: PortraitStyle.japaneseFresh,
          outputPath: '/tmp/generated.png',
          galleryExporter: exporter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(find.textContaining('生成成功，但保存到相册失败'), findsOneWidget);
    expect(find.byKey(const Key('portrait-retry-gallery-save')), findsOneWidget);
    expect(find.textContaining('已保存到系统相册'), findsNothing);

    await tester.tap(find.byKey(const Key('portrait-retry-gallery-save')));
    await tester.pumpAndSettle();

    expect(exporter.exportedPaths, <String>[
      '/tmp/generated.png',
      '/tmp/generated.png',
    ]);
    expect(find.textContaining('已保存到系统相册'), findsOneWidget);
  });
}
