import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/portrait_model.dart';
import 'portrait_download_source.dart';
import 'portrait_model_downloader.dart';
import 'qnn_model_layout.dart';

typedef AndroidModelRootDirectoryProvider = Future<Directory> Function();

/// Android production downloader.
///
/// Large model transport is delegated to a native foreground service using
/// OkHttp, matching the proven Local Dream download architecture. Flutter only
/// starts/cancels the task and polls the small state snapshot.
class AndroidPortraitModelDownloadService implements PortraitModelDownloadService {
  AndroidPortraitModelDownloadService({
    MethodChannel? channel,
    AndroidModelRootDirectoryProvider? rootDirectoryProvider,
    this.pollInterval = const Duration(milliseconds: 350),
  })  : _channel = channel ?? _defaultChannel,
        _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationDocumentsDirectory;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.qujindai.localportraitlab/model_download',
  );

  final MethodChannel _channel;
  final AndroidModelRootDirectoryProvider _rootDirectoryProvider;
  final Duration pollInterval;
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
      final modelDirectory = Directory('${directory.path}/${model.id}');
      if (!await modelDirectory.exists()) return null;
      for (final name in qnnSdxlRequiredFiles) {
        final file = File('${modelDirectory.path}/$name');
        if (!await file.exists() || await file.length() <= 0) return null;
      }
      return modelDirectory.path;
    }

    final file = File('${directory.path}/${model.fileName}');
    if (!await file.exists() || await file.length() <= 0) return null;
    return file.path;
  }

  @override
  Stream<PortraitModelDownloadState> download(PortraitModelSpec model) async* {
    final existing = await installedPath(model);
    if (existing != null) {
      yield PortraitModelDownloadCompleted(model, existing);
      return;
    }

    final directory = await _modelsDirectory();
    final source = await PortraitDownloadSourceDefaults.load();
    final resolvedDownloadUrl = source.resolveUrl(model.downloadUrl);
    _cancelRequested = false;

    await _channel.invokeMethod<void>('start', <String, Object?>{
      'modelId': model.id,
      'modelName': model.displayName,
      'url': resolvedDownloadUrl,
      'fileName': model.fileName,
      'destinationRoot': directory.path,
      'isArchive': model.isArchive,
      'requiredFiles': model.isArchive ? qnnSdxlRequiredFiles : const <String>[],
    });

    var idlePolls = 0;
    while (true) {
      if (pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }

      final raw = await _channel.invokeMapMethod<String, dynamic>('status') ??
          const <String, dynamic>{'state': 'idle'};
      final state = (raw['state'] as String? ?? 'idle').toLowerCase();
      final modelId = raw['modelId'] as String?;
      if (modelId != null && modelId.isNotEmpty && modelId != model.id) {
        continue;
      }

      switch (state) {
        case 'starting':
          idlePolls = 0;
          break;
        case 'downloading':
          idlePolls = 0;
          yield PortraitModelDownloadProgress(
            model,
            receivedBytes: _asInt(raw['downloadedBytes']),
            totalBytes: _asInt(raw['totalBytes']),
          );
          break;
        case 'extracting':
          idlePolls = 0;
          yield PortraitModelDownloadVerifying(model);
          break;
        case 'success':
          final path = raw['path'] as String?;
          if (path == null || path.isEmpty) {
            yield PortraitModelDownloadFailed(
              model,
              'Android 下载服务返回成功，但没有安装路径。',
            );
          } else {
            yield PortraitModelDownloadCompleted(model, path);
          }
          return;
        case 'cancelled':
          yield PortraitModelDownloadCancelled(
            model,
            partialBytes: _asInt(raw['downloadedBytes']),
          );
          return;
        case 'error':
          yield PortraitModelDownloadFailed(
            model,
            raw['message'] as String? ?? 'Android 原生下载失败。',
          );
          return;
        case 'idle':
          if (_cancelRequested) {
            yield PortraitModelDownloadCancelled(
              model,
              partialBytes: _asInt(raw['downloadedBytes']),
            );
            return;
          }
          idlePolls += 1;
          if (idlePolls >= 20) {
            yield PortraitModelDownloadFailed(
              model,
              'Android 原生下载服务未启动或已提前退出。',
            );
            return;
          }
          break;
        default:
          yield PortraitModelDownloadFailed(
            model,
            '未知下载状态：$state',
          );
          return;
      }
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    await _channel.invokeMethod<void>('cancel');
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
