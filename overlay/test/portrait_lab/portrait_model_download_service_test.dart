import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
    final remaining = startAt > 0 && startAt < payload.length
        ? payload.sublist(startAt)
        : startAt >= payload.length
            ? const <int>[]
            : payload;
    return _FakeResponse(
      startAt > 0 ? statusCode : 200,
      remaining.length,
      Stream<List<int>>.value(remaining),
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

PortraitModelSpec _qnnFixture() => const PortraitModelSpec(
      id: 'qnn_fixture',
      displayName: 'QNN Fixture',
      description: 'test',
      sourceLabel: 'Test',
      licenseLabel: 'test',
      format: 'QNN SDXL ZIP',
      sizeLabel: 'tiny',
      fileName: 'qnn_fixture.zip',
      downloadUrl: 'https://example.invalid/qnn_fixture.zip',
      expectedSha256: '',
      backend: PortraitModelBackend.dreamQnnSdxl,
      isArchive: true,
      generationSize: 1024,
    );

List<int> _validQnnZip() {
  const required = <String>[
    'tokenizer.json',
    'clip.mnn',
    'pos_emb.bin',
    'token_emb.bin',
    'clip_2.mnn',
    'pos_emb_2.bin',
    'token_emb_2.bin',
    'unet.bin',
    'vae_encoder.bin',
    'vae_decoder.bin',
  ];
  final archive = Archive();
  for (final name in required) {
    archive.addFile(ArchiveFile.string('model/$name', 'fixture-$name'));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  test('catalog prioritizes two DREAM QNN DMD2 packs plus three fallbacks', () {
    expect(PortraitModelCatalog.curated, hasLength(5));
    expect(
      PortraitModelCatalog.curated.take(2).map((m) => m.id),
      <String>['illustrious_v16_dmd2_qnn', 'cyber_realistic_v10_dmd2_qnn'],
    );
    expect(
      PortraitModelCatalog.curated.any((m) => m.id == 'lcm_dreamshaper7'),
      isFalse,
    );
    for (final model in PortraitModelCatalog.curated.take(2)) {
      expect(model.backend, PortraitModelBackend.dreamQnnSdxl);
      expect(model.isArchive, isTrue);
      expect(model.fileName.endsWith('.zip'), isTrue);
      expect(model.generationSize, 1024);
    }
    for (final model in PortraitModelCatalog.curated.skip(2)) {
      expect(model.backend, PortraitModelBackend.stableDiffusionCpp);
      expect(model.fileName.endsWith('.safetensors'), isTrue);
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

    final client = _FakeHttpClient(<int>[1, 2, 3, 4]);
    final service = NativePortraitModelDownloadService(
      rootDirectoryProvider: () async => root,
      httpClientFactory: () => client,
    );

    final states = await service.download(_fixture()).toList();

    expect(client.requestedStartAt, 2);
    final completed = states.whereType<PortraitModelDownloadCompleted>().single;
    expect(completed.path.endsWith('fixture.safetensors'), isTrue);
    expect(
      await File(completed.path).readAsBytes(),
      Uint8List.fromList(<int>[1, 2, 3, 4]),
    );
    expect(await partial.exists(), isFalse);
  });

  test('QNN zip is stream-installed and returns a validated model directory',
      () async {
    final root = await Directory.systemTemp.createTemp('portrait_qnn_install_');
    addTearDown(() => root.delete(recursive: true));
    final zip = _validQnnZip();
    final service = NativePortraitModelDownloadService(
      rootDirectoryProvider: () async => root,
      httpClientFactory: () => _FakeHttpClient(zip),
    );

    final states = await service.download(_qnnFixture()).toList();

    final completed = states.whereType<PortraitModelDownloadCompleted>().single;
    final modelDir = Directory(completed.path);
    expect(await modelDir.exists(), isTrue);
    expect(completed.path, endsWith('/portrait_lab/models/qnn_fixture'));
    expect(await File('${modelDir.path}/unet.bin').exists(), isTrue);
    expect(await File('${modelDir.path}/vae_encoder.bin').exists(), isTrue);
    expect(await File('${modelDir.path}/clip_2.mnn').exists(), isTrue);
    expect(
      await File('${root.path}/portrait_lab/models/qnn_fixture.zip.downloaded')
          .exists(),
      isFalse,
    );
    expect(await service.installedPath(_qnnFixture()), completed.path);
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
