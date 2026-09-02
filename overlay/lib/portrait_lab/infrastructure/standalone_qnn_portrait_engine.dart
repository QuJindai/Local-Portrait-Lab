import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../application/portrait_generation_engine.dart';
import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';
import 'native_local_diffusion_img2img_bridge.dart';

class StandaloneQnnConfigurationException implements Exception {
  const StandaloneQnnConfigurationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class StandaloneQnnBackendException implements Exception {
  const StandaloneQnnBackendException(this.message);
  final String message;

  @override
  String toString() => message;
}

class StandaloneQnnBackendStart {
  const StandaloneQnnBackendStart({
    required this.modelId,
    required this.modelDirectory,
    required this.backendType,
    required this.generationSize,
  });

  final String modelId;
  final String modelDirectory;
  final String backendType;
  final int generationSize;
}

abstract interface class StandaloneQnnBackendController {
  Future<void> start(StandaloneQnnBackendStart request);
  Future<void> stop();
}

class AndroidStandaloneQnnBackendController
    implements StandaloneQnnBackendController {
  AndroidStandaloneQnnBackendController({
    MethodChannel? channel,
    this.pollInterval = const Duration(milliseconds: 250),
    this.startTimeout = const Duration(seconds: 90),
  }) : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.qujindai.localportraitlab/qnn_backend',
  );

  final MethodChannel _channel;
  final Duration pollInterval;
  final Duration startTimeout;

  @override
  Future<void> start(StandaloneQnnBackendStart request) async {
    await _channel.invokeMethod<void>('start', <String, Object?>{
      'modelId': request.modelId,
      'modelDirectory': request.modelDirectory,
      'backendType': request.backendType,
      'generationSize': request.generationSize,
    });

    final deadline = DateTime.now().add(startTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final raw = await _channel.invokeMapMethod<String, dynamic>('status') ??
          const <String, dynamic>{'state': 'idle'};
      final state = (raw['state'] ?? 'idle').toString();
      final servingModelId = raw['modelId']?.toString();
      if (state == 'running' && servingModelId == request.modelId) return;
      if (state == 'error') {
        throw StandaloneQnnBackendException(
          '本机 QNN 后端启动失败：${raw['message'] ?? 'unknown error'}',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
    throw const StandaloneQnnBackendException('本机 QNN 后端启动超时。');
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

class StandaloneQnnGenerationRequest {
  const StandaloneQnnGenerationRequest({
    required this.modelId,
    required this.portraitPath,
    required this.prompt,
    required this.negativePrompt,
    required this.steps,
    required this.cfg,
    required this.scheduler,
    required this.generationSize,
    required this.aspectRatio,
    required this.denoiseStrength,
  });

  final String modelId;
  final String portraitPath;
  final String prompt;
  final String negativePrompt;
  final int steps;
  final double cfg;
  final String scheduler;
  final int generationSize;
  final String aspectRatio;
  final double denoiseStrength;
}

sealed class StandaloneQnnGenerationEvent {
  const StandaloneQnnGenerationEvent();
}

final class StandaloneQnnProgress extends StandaloneQnnGenerationEvent {
  const StandaloneQnnProgress({required this.step, required this.steps});
  final int step;
  final int steps;
}

final class StandaloneQnnComplete extends StandaloneQnnGenerationEvent {
  const StandaloneQnnComplete(this.pngBytes, {this.seed});
  final Uint8List pngBytes;
  final int? seed;
}

abstract interface class StandaloneQnnGenerationTransport {
  Stream<StandaloneQnnGenerationEvent> generate(
    StandaloneQnnGenerationRequest request,
  );

  Future<void> cancel();
}

class LocalStandaloneQnnGenerationTransport
    implements StandaloneQnnGenerationTransport {
  LocalStandaloneQnnGenerationTransport({
    String host = '127.0.0.1',
    int port = 8082,
  }) : _base = Uri.parse('http://$host:$port');

  final Uri _base;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);
  HttpClientRequest? _activeRequest;
  bool _cancelRequested = false;

  @override
  Stream<StandaloneQnnGenerationEvent> generate(
    StandaloneQnnGenerationRequest request,
  ) async* {
    _cancelRequested = false;
    final photoBytes = await File(request.portraitPath).readAsBytes();
    final body = jsonEncode(<String, dynamic>{
      'prompt': request.prompt,
      'negative_prompt': request.negativePrompt,
      'steps': request.steps,
      'cfg': request.cfg,
      'scheduler': request.scheduler,
      'width': request.generationSize,
      'height': request.generationSize,
      'aspect_ratio': request.aspectRatio,
      'denoise_strength': request.denoiseStrength,
      'image': base64Encode(photoBytes),
      'preview_format': 'jpeg',
      'output_format': 'png',
      'show_diffusion_process': false,
    });

    HttpClientRequest? httpRequest;
    try {
      httpRequest = await _client.postUrl(_base.resolve('/generate'));
      _activeRequest = httpRequest;
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      httpRequest.write(body);
      final response = await httpRequest.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'standalone QNN /generate HTTP ${response.statusCode}',
          uri: _base.resolve('/generate'),
        );
      }

      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (_cancelRequested) return;
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') return;
        final decoded = jsonDecode(data);
        if (decoded is! Map) continue;
        final message = Map<String, dynamic>.from(decoded);
        switch ((message['type'] ?? '').toString()) {
          case 'progress':
            final step = _asInt(message['step']);
            final total = _asInt(message['total_steps']);
            if (step > 0 && total > 0) {
              yield StandaloneQnnProgress(step: step, steps: total);
            }
          case 'complete':
            final encoded = (message['image'] ?? '').toString();
            if (encoded.isEmpty) {
              throw const FormatException('本机 QNN 完成事件没有图像数据。');
            }
            final bytes = Uint8List.fromList(base64Decode(encoded));
            final format = (message['format'] ?? 'raw').toString();
            final width = _asInt(message['width'], fallback: request.generationSize);
            final height = _asInt(message['height'], fallback: request.generationSize);
            final png = _toPng(bytes, format, width, height);
            final seedValue = message['seed'];
            final seed = seedValue == null ? null : _asInt(seedValue, fallback: -1);
            yield StandaloneQnnComplete(
              png,
              seed: seed != null && seed >= 0 ? seed : null,
            );
            return;
        }
      }
      if (!_cancelRequested) {
        throw const FormatException('本机 QNN 生成流在 complete 之前结束。');
      }
    } on SocketException catch (error) {
      if (_cancelRequested) return;
      throw StandaloneQnnBackendException(
        '本机 QNN 生成服务不可用：${error.message}',
      );
    } finally {
      if (identical(_activeRequest, httpRequest)) _activeRequest = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _activeRequest?.abort(
      const StandaloneQnnBackendException('generation cancelled'),
    );
    _activeRequest = null;
  }

  static int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  static Uint8List _toPng(
    Uint8List bytes,
    String format,
    int width,
    int height,
  ) {
    if (format == 'png') return bytes;
    img.Image? image;
    if (format == 'raw') {
      if (bytes.length != width * height * 3) {
        throw const FormatException('本机 QNN raw RGB byte count mismatch.');
      }
      image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bytes.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      );
    } else {
      image = img.decodeImage(bytes);
    }
    if (image == null) {
      throw FormatException('无法解码本机 QNN $format 图像。');
    }
    return Uint8List.fromList(img.encodePng(image));
  }
}

class StandaloneQnnPortraitEngine implements PortraitGenerationEngine {
  StandaloneQnnPortraitEngine({
    required StandaloneQnnBackendController backend,
    required StandaloneQnnGenerationTransport transport,
    required NativePortraitOutputStore outputStore,
  })  : _backend = backend,
        _transport = transport,
        _outputStore = outputStore;

  final StandaloneQnnBackendController _backend;
  final StandaloneQnnGenerationTransport _transport;
  final NativePortraitOutputStore _outputStore;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    final selection = _parseSelection(request.modelPath);
    final defaults = await _readDmd2Defaults(selection.modelDirectory);

    onState(const PortraitGenerationState.loadingModel());
    await _backend.start(
      StandaloneQnnBackendStart(
        modelId: selection.modelId,
        modelDirectory: selection.modelDirectory,
        backendType: selection.backendType,
        generationSize: selection.generationSize,
      ),
    );

    Uint8List? completed;
    await for (final event in _transport.generate(
      StandaloneQnnGenerationRequest(
        modelId: selection.modelId,
        portraitPath: request.portraitPath,
        prompt: request.prompt,
        negativePrompt: request.negativePrompt,
        steps: defaults.steps,
        cfg: defaults.cfg,
        scheduler: defaults.scheduler,
        generationSize: selection.generationSize,
        aspectRatio: '${request.width ~/ _gcd(request.width, request.height)}:${request.height ~/ _gcd(request.width, request.height)}',
        denoiseStrength: request.strength,
      ),
    )) {
      switch (event) {
        case StandaloneQnnProgress(:final step, :final steps):
          onState(PortraitGenerationState.sampling(step: step, steps: steps));
        case StandaloneQnnComplete(:final pngBytes):
          completed = pngBytes;
      }
    }

    final png = completed;
    if (png == null) {
      throw const StandaloneQnnBackendException('本机 QNN 未返回生成结果。');
    }
    return _outputStore.writePng(png);
  }

  @override
  Future<void> cancel() async {
    await _transport.cancel();
    await _backend.stop();
  }

  static _StandaloneQnnSelection _parseSelection(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'qnn') {
      throw const StandaloneQnnConfigurationException('无效的独立 QNN 模型选择。');
    }
    final modelId = uri.queryParameters['model_id']?.trim() ?? '';
    final modelDirectory = uri.queryParameters['path']?.trim() ?? '';
    final backendType = uri.queryParameters['type']?.trim() ?? 'sdxl';
    final generationSize = int.tryParse(uri.queryParameters['size'] ?? '') ?? 1024;
    if (modelId.isEmpty || modelDirectory.isEmpty || generationSize <= 0) {
      throw const StandaloneQnnConfigurationException('独立 QNN 模型选择缺少必要参数。');
    }
    return _StandaloneQnnSelection(
      modelId: modelId,
      modelDirectory: modelDirectory,
      backendType: backendType,
      generationSize: generationSize,
    );
  }

  static Future<_StandaloneQnnDefaults> _readDmd2Defaults(
    String modelDirectory,
  ) async {
    final file = File('$modelDirectory/config.json');
    if (!await file.exists()) {
      throw const StandaloneQnnConfigurationException(
        'DMD2 独立 QNN 模型缺少 config.json，不能安全猜测 steps/CFG/scheduler。',
      );
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('config root must be object');
      final map = Map<String, dynamic>.from(decoded);
      final steps = _readNumber(map['default_steps'])?.round();
      final cfg = _readNumber(map['default_cfg']);
      final scheduler = map['default_scheduler']?.toString().trim() ?? '';
      if (steps == null || steps < 1 || cfg == null || cfg <= 0 || scheduler.isEmpty) {
        throw const FormatException('missing DMD2 generation defaults');
      }
      return _StandaloneQnnDefaults(
        steps: steps.clamp(1, 50),
        cfg: cfg.clamp(1.0, 30.0),
        scheduler: scheduler,
      );
    } catch (error) {
      if (error is StandaloneQnnConfigurationException) rethrow;
      throw StandaloneQnnConfigurationException(
        'DMD2 config.json 无效：$error',
      );
    }
  }

  static double? _readNumber(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int _gcd(int a, int b) {
    var x = a.abs();
    var y = b.abs();
    while (y != 0) {
      final t = x % y;
      x = y;
      y = t;
    }
    return x == 0 ? 1 : x;
  }
}

class _StandaloneQnnSelection {
  const _StandaloneQnnSelection({
    required this.modelId,
    required this.modelDirectory,
    required this.backendType,
    required this.generationSize,
  });

  final String modelId;
  final String modelDirectory;
  final String backendType;
  final int generationSize;
}

class _StandaloneQnnDefaults {
  const _StandaloneQnnDefaults({
    required this.steps,
    required this.cfg,
    required this.scheduler,
  });

  final int steps;
  final double cfg;
  final String scheduler;
}
