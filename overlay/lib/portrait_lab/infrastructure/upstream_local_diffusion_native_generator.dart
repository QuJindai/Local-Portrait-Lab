import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../ffi_bindings.dart';
import '../../img2img_processor.dart';
import 'native_local_diffusion_img2img_bridge.dart';

class UpstreamImg2ImgInvocation {
  const UpstreamImg2ImgInvocation({
    required this.channel,
    required this.outputWidth,
    required this.outputHeight,
    required this.prompt,
    required this.negativePrompt,
    required this.cfgScale,
    required this.sampleSteps,
    required this.strength,
    required this.seed,
    required this.sampleMethod,
    required this.batchCount,
  });

  factory UpstreamImg2ImgInvocation.fromRequest(NativeImg2ImgRequest request) {
    return UpstreamImg2ImgInvocation(
      channel: request.channels,
      outputWidth: request.outputWidth,
      outputHeight: request.outputHeight,
      prompt: request.prompt,
      negativePrompt: request.negativePrompt,
      cfgScale: request.cfgScale,
      sampleSteps: request.sampleSteps,
      strength: request.strength,
      seed: request.seed,
      sampleMethod: request.sampleMethodIndex,
      batchCount: 1,
    );
  }

  final int channel;
  final int outputWidth;
  final int outputHeight;
  final String prompt;
  final String negativePrompt;
  final double cfgScale;
  final int sampleSteps;
  final double strength;
  final int seed;
  final int sampleMethod;
  final int batchCount;
}

abstract interface class UpstreamImg2ImgSession {
  Future<Uint8List> generatePng(
    NativeImg2ImgRequest request, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  });

  Future<void> dispose();
}

abstract interface class UpstreamImg2ImgSessionFactory {
  UpstreamImg2ImgSession create();
}

class UpstreamLocalDiffusionNativeGenerator implements NativeImg2ImgGenerator {
  UpstreamLocalDiffusionNativeGenerator({UpstreamImg2ImgSessionFactory? factory})
      : _factory = factory ?? const Img2ImgProcessorSessionFactory();

  final UpstreamImg2ImgSessionFactory _factory;
  UpstreamImg2ImgSession? _activeSession;

  @override
  Future<Uint8List> generatePng(
    NativeImg2ImgRequest request, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  }) async {
    if (_activeSession != null) {
      throw StateError('An upstream img2img session is already active.');
    }

    final session = _factory.create();
    _activeSession = session;
    try {
      return await session.generatePng(request, onProgress: onProgress);
    } finally {
      await session.dispose();
      if (identical(_activeSession, session)) {
        _activeSession = null;
      }
    }
  }

  @override
  Future<void> cancel() async {
    final active = _activeSession;
    if (active != null) {
      await active.dispose();
    }
  }
}

class Img2ImgProcessorSessionFactory implements UpstreamImg2ImgSessionFactory {
  const Img2ImgProcessorSessionFactory();

  @override
  UpstreamImg2ImgSession create() => Img2ImgProcessorSession();
}

class Img2ImgProcessorSession implements UpstreamImg2ImgSession {
  Img2ImgProcessor? _processor;
  StreamSubscription<Map<String, dynamic>>? _resultSubscription;
  Completer<Uint8List>? _resultCompleter;
  bool _disposed = false;
  bool _started = false;

  @override
  Future<Uint8List> generatePng(
    NativeImg2ImgRequest request, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  }) async {
    if (_disposed) {
      throw StateError('Upstream img2img session is disposed.');
    }
    if (_started) {
      throw StateError('Upstream img2img session may only generate once.');
    }
    _started = true;

    final resultCompleter = Completer<Uint8List>();
    _resultCompleter = resultCompleter;

    final processor = Img2ImgProcessor(
      modelPath: request.modelPath,
      useFlashAttention: false,
      modelType: SDType.NONE,
      schedule: Schedule.DEFAULT,
      isDiffusionModelType: false,
      onProgress: (progress) {
        onProgress(progress.step, progress.totalSteps, progress.time);
      },
      onLog: (log) {
        if (log.level < 0 && !resultCompleter.isCompleted) {
          resultCompleter.completeError(StateError(log.message));
        }
      },
    );
    _processor = processor;

    _resultSubscription = processor.generationResultStream.listen(
      (result) async {
        if (resultCompleter.isCompleted) {
          return;
        }
        try {
          final generatedImage = result['image'];
          if (generatedImage is! ui.Image) {
            throw StateError('Local-Diffusion returned no generated image.');
          }
          final byteData =
              await generatedImage.toByteData(format: ui.ImageByteFormat.png);
          if (byteData == null) {
            throw StateError('Unable to encode generated image as PNG.');
          }
          final view = byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          );
          resultCompleter.complete(Uint8List.fromList(view));
        } catch (error, stackTrace) {
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(error, stackTrace);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.completeError(error, stackTrace);
        }
      },
    );

    final invocation = UpstreamImg2ImgInvocation.fromRequest(request);
    try {
      await processor.generateImg2Img(
        inputImageData: request.rgbBytes,
        inputWidth: request.inputWidth,
        inputHeight: request.inputHeight,
        channel: invocation.channel,
        outputWidth: invocation.outputWidth,
        outputHeight: invocation.outputHeight,
        prompt: invocation.prompt,
        negativePrompt: invocation.negativePrompt,
        cfgScale: invocation.cfgScale,
        sampleMethod: invocation.sampleMethod,
        sampleSteps: invocation.sampleSteps,
        strength: invocation.strength,
        seed: invocation.seed,
        batchCount: invocation.batchCount,
      );
    } catch (error, stackTrace) {
      if (!resultCompleter.isCompleted) {
        resultCompleter.completeError(error, stackTrace);
      }
    }

    return resultCompleter.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    final completer = _resultCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Upstream img2img session disposed.'));
    }

    await _resultSubscription?.cancel();
    _resultSubscription = null;

    final processor = _processor;
    _processor = null;
    processor?.dispose();
  }
}
