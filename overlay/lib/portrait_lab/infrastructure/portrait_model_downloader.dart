import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/portrait_model.dart';

const _requiredQnnSdxlFiles = <String>[
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

sealed class PortraitModelDownloadState {
  const PortraitModelDownloadState(this.model);
  final PortraitModelSpec model;
}

final class PortraitModelDownloadProgress extends PortraitModelDownloadState {
  const PortraitModelDownloadProgress(
    super.model, {
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double? get fraction =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

final class PortraitModelDownloadVerifying extends PortraitModelDownloadState {
  const PortraitModelDownloadVerifying(super.model);
}

final class PortraitModelDownloadCompleted extends PortraitModelDownloadState {
  const PortraitModelDownloadCompleted(super.model, this.path);
  final String path;
}

final class PortraitModelDownloadCancelled extends PortraitModelDownloadState {
  const PortraitModelDownloadCancelled(
    super.model, {
    required this.partialBytes,
  });
  final int partialBytes;
}

final class PortraitModelDownloadFailed extends PortraitModelDownloadState {
  const PortraitModelDownloadFailed(super.model, this.message);
  final String message;
}

abstract interface class PortraitModelDownloadService {
  Stream<PortraitModelDownloadState> download(PortraitModelSpec model);
  Future<void> cancel();
  Future<String?> installedPath(PortraitModelSpec model);
}

abstract interface class PortraitDownloadHttpResponse {
  int get statusCode;
  int get contentLength;
  Stream<List<int>> get bytes;
}

abstract interface class PortraitDownloadHttpClient {
  Future<PortraitDownloadHttpResponse> get(Uri uri, {required int startAt});
  void close({bool force = false});
}

class DartIoPortraitDownloadHttpClient implements PortraitDownloadHttpClient {
  DartIoPortraitDownloadHttpClient() : _client = HttpClient();

  final HttpClient _client;

  @override
  Future<PortraitDownloadHttpResponse> get(
    Uri uri, {
    required int startAt,
  }) async {
    var current = uri;
    for (var redirect = 0; redirect <= 8; redirect += 1) {
      final request = await _client.getUrl(current);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'PortraitLab/0.6 Android Local-Diffusion',
      );
      if (startAt > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startAt-');
      }
      final response = await request.close();
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          throw HttpException(
            'Redirect response has no Location header.',
            uri: current,
          );
        }
        current = current.resolve(location);
        continue;
      }
      return _DartIoPortraitDownloadHttpResponse(response);
    }
    throw HttpException('Too many redirects while downloading model.', uri: uri);
  }

  bool _isRedirect(int code) =>
      code == HttpStatus.movedPermanently ||
      code == HttpStatus.found ||
      code == HttpStatus.seeOther ||
      code == HttpStatus.temporaryRedirect ||
      code == HttpStatus.permanentRedirect;

  @override
  void close({bool force = false}) => _client.close(force: force);
}

class _DartIoPortraitDownloadHttpResponse
    implements PortraitDownloadHttpResponse {
  const _DartIoPortraitDownloadHttpResponse(this.response);

  final HttpClientResponse response;

  @override
  int get statusCode => response.statusCode;

  @override
  int get contentLength => response.contentLength;

  @override
  Stream<List<int>> get bytes => response;
}

typedef PortraitModelRootDirectoryProvider = Future<Directory> Function();
typedef PortraitDownloadHttpClientFactory = PortraitDownloadHttpClient Function();

class NativePortraitModelDownloadService implements PortraitModelDownloadService {
  NativePortraitModelDownloadService({
    PortraitModelRootDirectoryProvider? rootDirectoryProvider,
    PortraitDownloadHttpClientFactory? httpClientFactory,
  })  : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationDocumentsDirectory,
        _httpClientFactory =
            httpClientFactory ?? (() => DartIoPortraitDownloadHttpClient());

  final PortraitModelRootDirectoryProvider _rootDirectoryProvider;
  final PortraitDownloadHttpClientFactory _httpClientFactory;

  PortraitDownloadHttpClient? _activeClient;
  bool _active = false;
  bool _cancelRequested = false;

  Future<Directory> _modelsDirectory() async {
    final root = await _rootDirectoryProvider();
    final directory = Directory('${root.path}/portrait_lab/models');
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<String?> installedPath(PortraitModelSpec model) async {
    final directory = await _modelsDirectory();
    if (model.isArchive) {
      final modelDir = Directory('${directory.path}/${model.id}');
      return await _qnnModelDirectoryLooksComplete(modelDir)
          ? modelDir.path
          : null;
    }

    final file = File('${directory.path}/${model.fileName}');
    return await file.exists() && await file.length() > 0 ? file.path : null;
  }

  @override
  Stream<PortraitModelDownloadState> download(PortraitModelSpec model) async* {
    if (_active) {
      yield PortraitModelDownloadFailed(
        model,
        '已有模型正在下载，请先等待完成或取消当前任务。',
      );
      return;
    }

    _active = true;
    _cancelRequested = false;
    var received = 0;
    IOSink? cleanupSink;
    PortraitDownloadHttpClient? client;

    try {
      final directory = await _modelsDirectory();
      final alreadyInstalled = await installedPath(model);
      if (alreadyInstalled != null) {
        yield PortraitModelDownloadCompleted(model, alreadyInstalled);
        return;
      }

      final finalFile = File('${directory.path}/${model.fileName}');
      final partFile = File('${finalFile.path}.part');
      final downloadedArchive = File('${finalFile.path}.downloaded');

      File payloadFile;
      if (model.isArchive && await downloadedArchive.exists()) {
        payloadFile = downloadedArchive;
      } else {
        final existing = await partFile.exists() ? await partFile.length() : 0;
        received = existing;

        client = _httpClientFactory();
        _activeClient = client;
        final response = await client.get(
          Uri.parse(model.downloadUrl),
          startAt: existing,
        );

        var append =
            existing > 0 && response.statusCode == HttpStatus.partialContent;
        if (existing > 0 && response.statusCode == HttpStatus.ok) {
          append = false;
          received = 0;
        }
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          yield PortraitModelDownloadFailed(
            model,
            '下载服务器返回 HTTP ${response.statusCode}。',
          );
          return;
        }

        final total = response.contentLength > 0
            ? received + response.contentLength
            : 0;
        final outputSink =
            partFile.openWrite(mode: append ? FileMode.append : FileMode.write);
        cleanupSink = outputSink;

        if (received > 0) {
          yield PortraitModelDownloadProgress(
            model,
            receivedBytes: received,
            totalBytes: total,
          );
        }

        await for (final chunk in response.bytes) {
          if (_cancelRequested) {
            await outputSink.flush();
            await outputSink.close();
            cleanupSink = null;
            yield PortraitModelDownloadCancelled(
              model,
              partialBytes: received,
            );
            return;
          }
          outputSink.add(chunk);
          received += chunk.length;
          yield PortraitModelDownloadProgress(
            model,
            receivedBytes: received,
            totalBytes: total,
          );
        }

        await outputSink.flush();
        await outputSink.close();
        cleanupSink = null;

        if (_cancelRequested) {
          yield PortraitModelDownloadCancelled(model, partialBytes: received);
          return;
        }
        payloadFile = partFile;
      }

      yield PortraitModelDownloadVerifying(model);
      if (model.expectedSha256.isNotEmpty) {
        final digest = await sha256.bind(payloadFile.openRead()).first;
        final actual = digest.toString().toLowerCase();
        if (actual != model.expectedSha256.toLowerCase()) {
          if (await payloadFile.exists()) await payloadFile.delete();
          yield PortraitModelDownloadFailed(
            model,
            'SHA-256 校验失败。已删除损坏文件，请重新下载。',
          );
          return;
        }
      }

      if (model.isArchive) {
        if (payloadFile.path == partFile.path) {
          if (await downloadedArchive.exists()) {
            await downloadedArchive.delete();
          }
          payloadFile = await partFile.rename(downloadedArchive.path);
        }

        final installed = await Isolate.run(
          () => _extractAndValidateQnnSdxlArchive(
            payloadFile.path,
            directory.path,
            model.id,
          ),
        );
        if (await payloadFile.exists()) await payloadFile.delete();
        yield PortraitModelDownloadCompleted(model, installed);
        return;
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      final completed = await partFile.rename(finalFile.path);
      yield PortraitModelDownloadCompleted(model, completed.path);
    } catch (error) {
      if (_cancelRequested) {
        yield PortraitModelDownloadCancelled(model, partialBytes: received);
      } else {
        yield PortraitModelDownloadFailed(model, _humanizeError(error));
      }
    } finally {
      final leftover = cleanupSink;
      if (leftover != null) {
        try {
          await leftover.flush();
          await leftover.close();
        } catch (_) {}
      }
      client?.close(force: _cancelRequested);
      _activeClient = null;
      _active = false;
      _cancelRequested = false;
    }
  }

  String _humanizeError(Object error) {
    if (error is SocketException) {
      return '网络连接失败：${error.message}';
    }
    if (error is HttpException) {
      return '下载失败：${error.message}';
    }
    if (error is FileSystemException) {
      return '文件写入/解压失败：${error.message}';
    }
    if (error is FormatException) {
      return '模型包格式无效：${error.message}';
    }
    return '下载/安装失败：$error';
  }

  @override
  Future<void> cancel() async {
    if (!_active) return;
    _cancelRequested = true;
    _activeClient?.close(force: true);
  }
}

Future<bool> _qnnModelDirectoryLooksComplete(Directory directory) async {
  if (!await directory.exists()) return false;
  for (final name in _requiredQnnSdxlFiles) {
    final file = File('${directory.path}/$name');
    if (!await file.exists() || await file.length() == 0) return false;
  }
  return true;
}

String _extractAndValidateQnnSdxlArchive(
  String archivePath,
  String modelsDirectoryPath,
  String modelId,
) {
  final staging = Directory('$modelsDirectoryPath/$modelId.installing');
  final finalDirectory = Directory('$modelsDirectoryPath/$modelId');
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);

  final input = InputFileStream(archivePath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    for (final entity in archive) {
      if (entity.isSymbolicLink) {
        throw const FormatException('QNN model archive may not contain links.');
      }
      final relativePath = _safeArchiveRelativePath(entity.name);
      if (relativePath == null) continue;
      final outputPath = '${staging.path}/$relativePath';
      if (entity.isFile) {
        File(outputPath).parent.createSync(recursive: true);
        final output = OutputFileStream(outputPath);
        try {
          entity.writeContent(output);
        } finally {
          output.closeSync();
        }
      } else {
        Directory(outputPath).createSync(recursive: true);
      }
    }
  } finally {
    input.closeSync();
  }

  final modelRoot = _findQnnSdxlRoot(staging);
  if (modelRoot == null) {
    staging.deleteSync(recursive: true);
    throw FormatException(
      'QNN SDXL 模型包缺少必需文件：${_requiredQnnSdxlFiles.join(', ')}',
    );
  }

  if (finalDirectory.existsSync()) finalDirectory.deleteSync(recursive: true);
  if (modelRoot.path == staging.path) {
    staging.renameSync(finalDirectory.path);
  } else {
    modelRoot.renameSync(finalDirectory.path);
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
  return finalDirectory.path;
}

String? _safeArchiveRelativePath(String rawName) {
  if (rawName.isEmpty) return null;
  final normalized = rawName.replaceAll('\\', '/');
  if (normalized.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    throw const FormatException('Archive contains an absolute path.');
  }
  final parts = <String>[];
  for (final part in normalized.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      throw const FormatException('Archive contains a parent path traversal.');
    }
    parts.add(part);
  }
  if (parts.isEmpty || parts.first == '__MACOSX') return null;
  return parts.join('/');
}

Directory? _findQnnSdxlRoot(Directory staging) {
  final candidates = <Directory>{staging};
  for (final entity in staging.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('/unet.bin')) {
      candidates.add(entity.parent);
    }
  }

  for (final directory in candidates) {
    var complete = true;
    for (final name in _requiredQnnSdxlFiles) {
      final file = File('${directory.path}/$name');
      if (!file.existsSync() || file.lengthSync() == 0) {
        complete = false;
        break;
      }
    }
    if (complete) return directory;
  }
  return null;
}
