import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/portrait_model.dart';

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
        'PortraitLab/0.3 Android Local-Diffusion',
      );
      if (startAt > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startAt-');
      }
      final response = await request.close();
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          throw HttpException('Redirect response has no Location header.', uri: current);
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
    final file = File('${directory.path}/${model.fileName}');
    return await file.exists() ? file.path : null;
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
      final finalFile = File('${directory.path}/${model.fileName}');
      if (await finalFile.exists()) {
        yield PortraitModelDownloadCompleted(model, finalFile.path);
        return;
      }

      final partFile = File('${finalFile.path}.part');
      final existing = await partFile.exists() ? await partFile.length() : 0;
      received = existing;

      client = _httpClientFactory();
      _activeClient = client;
      final response = await client.get(
        Uri.parse(model.downloadUrl),
        startAt: existing,
      );

      var append = existing > 0 && response.statusCode == HttpStatus.partialContent;
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

      yield PortraitModelDownloadVerifying(model);
      if (model.expectedSha256.isNotEmpty) {
        final digest = await sha256.bind(partFile.openRead()).first;
        final actual = digest.toString().toLowerCase();
        if (actual != model.expectedSha256.toLowerCase()) {
          await partFile.delete();
          yield PortraitModelDownloadFailed(
            model,
            'SHA-256 校验失败。已删除损坏文件，请重新下载。',
          );
          return;
        }
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
      return '文件写入失败：${error.message}';
    }
    return '下载失败：$error';
  }

  @override
  Future<void> cancel() async {
    if (!_active) return;
    _cancelRequested = true;
    _activeClient?.close(force: true);
  }
}
