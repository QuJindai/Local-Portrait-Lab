import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_model.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_model_downloader.dart';

class _FakeResponse implements PortraitDownloadHttpResponse {
  _FakeResponse(this.statusCode, this.contentLength, this.bytes);

  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final Stream<List<int>> bytes;
}

class _FakeHttpClient implements PortraitDownloadHttpClient {
  _FakeHttpClient(this.payload, {this.statusCode = 206});

  final List<int> payload;
  final int statusCode;
  int? requestedStartAt;
  bool closed = false;

  @override
  Future<PortraitDownloadHttpResponse> get(Uri uri, {required int startAt}) async {
    requestedStartAt = startAt;
    return _FakeResponse(
      startAt > 0 ? statusCode : 200,
      payload.length,
      Stream<List<int>>.value(payload),
    );
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

PortraitModelSpec _fixture({String? expectedSha256}) => PortraitModelSpec(
      id: 'fixture',
      displayName: 'Fixture Model',
      description: 'test',
      sourceLabel: 'Test',
      licenseLabel: 'test',
      format: 'SafeTensors',
      sizeLabel: '4 B',
      fileName: 'fixture.safetensors',
      downloadUrl: 'https://example.invalid/fixture.safetensors',
      expectedSha256: expectedSha256 ?? '',
    );

void main() {
  test('catalog exposes three curated one-file SafeTensors models with hashes', () {
    expect(PortraitModelCatalog.curated, hasLength(3));
    for (final model in PortraitModelCatalog.curated) {
      expect(model.fileName.endsWith('.safetensors'), isTrue);
      expect(model.downloadUrl.startsWith('https://'), isTrue);
      expect(model.expectedSha256, hasLength(64));
    }
  });

  test('download resumes an existing .part file and promotes it to final model',
      () async {
    final root = await Directory.systemTemp.createTemp('portrait_model_resume_');
    addTearDown(() => root.delete(recursive: true));

    final modelsDir = Directory('${root.path}/portrait_lab/models');
    await modelsDir.create(recursive: true);
    final partial = File('${modelsDir.path}/fixture.safetensors.part');
    await partial.writeAsBytes(<int>[1, 2], flush: true);

    final client = _FakeHttpClient(<int>[3, 4]);
    final service = NativePortraitModelDownloadService(
      rootDirectoryProvider: () async => root,
      httpClientFactory: () => client,
    );

    final states = await service.download(_fixture()).toList();

    expect(client.requestedStartAt, 2);
    final completed = states.whereType<PortraitModelDownloadCompleted>().single;
    expect(completed.path.endsWith('fixture.safetensors'), isTrue);
    expect(await File(completed.path).readAsBytes(), Uint8List.fromList(<int>[1, 2, 3, 4]));
    expect(await partial.exists(), isFalse);
  });

  test('installedPath only returns a completed model file, never the .part file',
      () async {
    final root = await Directory.systemTemp.createTemp('portrait_model_installed_');
    addTearDown(() => root.delete(recursive: true));

    final modelsDir = Directory('${root.path}/portrait_lab/models');
    await modelsDir.create(recursive: true);
    final service = NativePortraitModelDownloadService(
      rootDirectoryProvider: () async => root,
      httpClientFactory: () => _FakeHttpClient(const <int>[]),
    );

    await File('${modelsDir.path}/fixture.safetensors.part').writeAsBytes(<int>[1]);
    expect(await service.installedPath(_fixture()), isNull);

    final finalFile = File('${modelsDir.path}/fixture.safetensors');
    await finalFile.writeAsBytes(<int>[1, 2]);
    expect(await service.installedPath(_fixture()), finalFile.path);
  });
}
