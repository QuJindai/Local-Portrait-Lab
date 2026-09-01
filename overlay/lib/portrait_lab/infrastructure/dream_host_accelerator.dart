import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class DreamHostUnavailableException implements Exception {
  const DreamHostUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DreamHostModelDefaults {
  const DreamHostModelDefaults({
    required this.steps,
    required this.cfg,
    required this.scheduler,
  });

  final int steps;
  final double cfg;
  final String scheduler;
}

class DreamHostModel {
  const DreamHostModel({
    required this.id,
    required this.name,
    required this.isSdxl,
    required this.runOnCpu,
    required this.generationSize,
    required this.defaults,
  });

  final String id;
  final String name;
  final bool isSdxl;
  final bool runOnCpu;
  final int generationSize;
  final DreamHostModelDefaults defaults;
}

class DreamHostGenerationRequest {
  const DreamHostGenerationRequest({
    required this.model,
    required this.portraitPath,
    required this.prompt,
    required this.negativePrompt,
    required this.denoiseStrength,
    required this.aspectRatio,
  });

  final DreamHostModel model;
  final String portraitPath;
  final String prompt;
  final String negativePrompt;
  final double denoiseStrength;
  final String aspectRatio;
}

sealed class DreamHostGenerationEvent {
  const DreamHostGenerationEvent();
}

final class DreamHostProgress extends DreamHostGenerationEvent {
  const DreamHostProgress(this.step, this.steps);
  final int step;
  final int steps;
}

final class DreamHostComplete extends DreamHostGenerationEvent {
  const DreamHostComplete(this.pngBytes, {this.seed});
  final Uint8List pngBytes;
  final int? seed;
}

abstract interface class DreamHostAccelerator {
  Future<DreamHostModel> selectModel(String modelId);
  Stream<DreamHostGenerationEvent> generate(DreamHostGenerationRequest request);
  Future<void> cancel();
}

class LocalDreamHostAccelerator implements DreamHostAccelerator {
  LocalDreamHostAccelerator({
    String controlHost = '127.0.0.1',
    int controlPort = 8808,
    int generationPort = 8081,
  })  : _controlBase = Uri.parse('http://$controlHost:$controlPort'),
        _generationBase = Uri.parse('http://$controlHost:$generationPort');

  final Uri _controlBase;
  final Uri _generationBase;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);
  HttpClientRequest? _activeGenerationRequest;
  bool _cancelRequested = false;

  @override
  Future<DreamHostModel> selectModel(String modelId) async {
    try {
      final info = await _getJson(_controlBase.resolve('/info'));
      if (info['app'] != 'localdream') {
        throw const DreamHostUnavailableException(
          '本机 8808 不是 DREAM Host。',
        );
      }

      final catalog = await _getJson(_controlBase.resolve('/models'));
      final rawModels = catalog['models'];
      if (rawModels is! List) {
        throw const DreamHostUnavailableException('DREAM 模型目录响应无效。');
      }
      Map<String, dynamic>? match;
      for (final raw in rawModels) {
        if (raw is Map && raw['id'] == modelId) {
          match = Map<String, dynamic>.from(raw);
          break;
        }
      }
      if (match == null) {
        throw DreamHostUnavailableException(
          'DREAM 中未安装模型 $modelId。请先在 DREAM 模型页下载。',
        );
      }
      final defaultsRaw = match['defaults'];
      final defaults = defaultsRaw is Map
          ? Map<String, dynamic>.from(defaultsRaw)
          : <String, dynamic>{};
      final model = DreamHostModel(
        id: modelId,
        name: (match['name'] ?? modelId).toString(),
        isSdxl: match['is_sdxl'] == true,
        runOnCpu: match['run_on_cpu'] == true,
        generationSize: _asInt(match['generation_size'], fallback: 1024),
        defaults: DreamHostModelDefaults(
          steps: _asDouble(defaults['steps'], fallback: 8).round().clamp(1, 100),
          cfg: _asDouble(defaults['cfg'], fallback: 1.0),
          scheduler: (defaults['scheduler'] ?? 'dpm').toString(),
        ),
      );

      final select = await _postJson(
        _controlBase.resolve('/select'),
        <String, dynamic>{
          'model_id': modelId,
          'width': model.generationSize,
          'height': model.generationSize,
        },
      );
      if (select['ok'] != true) {
        throw DreamHostUnavailableException(
          'DREAM 无法启动模型 ${model.name}。',
        );
      }

      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        final status = await _getJson(_controlBase.resolve('/status'));
        final state = (status['state'] ?? '').toString();
        final serving = status['serving_model_id']?.toString();
        if (state == 'running' && serving == modelId) return model;
        if (state == 'error') {
          throw DreamHostUnavailableException(
            'DREAM QNN 后端启动失败：${status['message'] ?? 'unknown error'}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      throw const DreamHostUnavailableException('DREAM QNN 后端启动超时。');
    } on SocketException catch (error) {
      throw DreamHostUnavailableException(
        '未连接到 DREAM 加速器（${error.message}）。请在 DREAM 的远程/Host 页面开启主机模式后重试。',
      );
    } on HttpException catch (error) {
      throw DreamHostUnavailableException('DREAM Host 通信失败：${error.message}');
    }
  }

  @override
  Stream<DreamHostGenerationEvent> generate(
    DreamHostGenerationRequest request,
  ) async* {
    _cancelRequested = false;
    final photoBytes = await File(request.portraitPath).readAsBytes();
    final body = jsonEncode(<String, dynamic>{
      'prompt': request.prompt,
      'negative_prompt': request.negativePrompt,
      'steps': request.model.defaults.steps,
      'cfg': request.model.defaults.cfg,
      'scheduler': request.model.defaults.scheduler,
      'width': request.model.generationSize,
      'height': request.model.generationSize,
      'aspect_ratio': request.aspectRatio,
      'denoise_strength': request.denoiseStrength,
      'image': base64Encode(photoBytes),
      'preview_format': 'jpeg',
      'output_format': 'png',
      'show_diffusion_process': false,
    });

    HttpClientRequest? httpRequest;
    try {
      httpRequest = await _client.postUrl(_generationBase.resolve('/generate'));
      _activeGenerationRequest = httpRequest;
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      httpRequest.write(body);
      final response = await httpRequest.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'DREAM /generate HTTP ${response.statusCode}',
          uri: _generationBase.resolve('/generate'),
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
            final step = _asInt(message['step'], fallback: 0);
            final steps = _asInt(message['total_steps'], fallback: 0);
            if (step > 0 && steps > 0) {
              yield DreamHostProgress(step, steps);
            }
          case 'complete':
            final encoded = (message['image'] ?? '').toString();
            if (encoded.isEmpty) {
              throw const FormatException('DREAM 完成事件没有图像数据。');
            }
            final bytes = Uint8List.fromList(base64Decode(encoded));
            final format = (message['format'] ?? 'raw').toString();
            final width = _asInt(message['width'], fallback: 1024);
            final height = _asInt(message['height'], fallback: 1024);
            final png = _toPng(bytes, format, width, height);
            final seed = message['seed'] == null
                ? null
                : _asInt(message['seed'], fallback: -1).takeIfNonNegative;
            yield DreamHostComplete(png, seed: seed);
            return;
        }
      }
      if (!_cancelRequested) {
        throw const FormatException('DREAM 生成流在 complete 之前结束。');
      }
    } on SocketException catch (error) {
      if (_cancelRequested) return;
      throw DreamHostUnavailableException('DREAM QNN 连接中断：${error.message}');
    } finally {
      if (identical(_activeGenerationRequest, httpRequest)) {
        _activeGenerationRequest = null;
      }
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _activeGenerationRequest?.abort(
      const DreamHostUnavailableException('generation cancelled'),
    );
    _activeGenerationRequest = null;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    return _decodeJsonResponse(response, uri);
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    return _decodeJsonResponse(response, uri);
  }

  Future<Map<String, dynamic>> _decodeJsonResponse(
    HttpClientResponse response,
    Uri uri,
  ) async {
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}: $text', uri: uri);
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('Expected JSON object.');
    return Map<String, dynamic>.from(decoded);
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
        throw const FormatException('DREAM raw RGB byte count mismatch.');
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
    if (image == null) throw const FormatException('Unable to decode DREAM image.');
    return Uint8List.fromList(img.encodePng(image));
  }

  static int _asInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _asDouble(Object? value, {required double fallback}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

extension on int {
  int? get takeIfNonNegative => this >= 0 ? this : null;
}
