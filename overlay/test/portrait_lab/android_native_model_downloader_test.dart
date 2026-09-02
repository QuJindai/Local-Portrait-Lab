import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_model.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/android_portrait_model_downloader.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_model_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.qujindai.localportraitlab/model_download');
  final calls = <MethodCall>[];
  final statusQueue = <Map<String, Object?>>[];
  late Directory root;

  setUp(() async {
    calls.clear();
    statusQueue.clear();
    root = await Directory.systemTemp.createTemp('portrait-android-download-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'start':
        case 'cancel':
          return null;
        case 'status':
          if (statusQueue.isEmpty) {
            return <String, Object?>{'state': 'idle'};
          }
          return statusQueue.removeAt(0);
      }
      throw PlatformException(code: 'unexpected', message: call.method);
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('R7 Android downloader delegates large model transport to native service',
      () async {
    final model = PortraitModelCatalog.curated.first;
    final modelsRoot = '${root.path}/portrait_lab/models';
    statusQueue.addAll(<Map<String, Object?>>[
      <String, Object?>{
        'state': 'downloading',
        'modelId': model.id,
        'downloadedBytes': 32,
        'totalBytes': 128,
      },
      <String, Object?>{
        'state': 'extracting',
        'modelId': model.id,
      },
      <String, Object?>{
        'state': 'success',
        'modelId': model.id,
        'path': '$modelsRoot/${model.id}',
      },
    ]);

    final downloader = AndroidPortraitModelDownloadService(
      channel: channel,
      rootDirectoryProvider: () async => root,
      pollInterval: Duration.zero,
    );

    final states = await downloader.download(model).toList();

    expect(states.whereType<PortraitModelDownloadProgress>(), hasLength(1));
    expect(states.whereType<PortraitModelDownloadVerifying>(), hasLength(1));
    final completed = states.whereType<PortraitModelDownloadCompleted>().single;
    expect(completed.path, '$modelsRoot/${model.id}');

    final start = calls.firstWhere((call) => call.method == 'start');
    final args = Map<Object?, Object?>.from(start.arguments as Map);
    expect(args['url'], model.downloadUrl);
    expect(args['modelId'], model.id);
    expect(args['fileName'], model.fileName);
    expect(args['isArchive'], isTrue);
    expect(args['destinationRoot'], modelsRoot);
    expect(args['requiredFiles'], isA<List<Object?>>());
  });

  test('R7 cancel is delegated to native foreground service', () async {
    final downloader = AndroidPortraitModelDownloadService(
      channel: channel,
      rootDirectoryProvider: () async => root,
      pollInterval: Duration.zero,
    );

    await downloader.cancel();

    expect(calls.any((call) => call.method == 'cancel'), isTrue);
  });
}
