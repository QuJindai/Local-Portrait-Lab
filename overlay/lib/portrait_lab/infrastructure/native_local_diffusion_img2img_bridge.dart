import 'dart:typed_data';

import 'local_diffusion_img2img_bridge.dart';

class DecodedNativePortrait {
  DecodedNativePortrait({
    required this.rgbBytes,
    required this.width,
    required this.height,
  });

  final Uint8List rgbBytes;
  final int width;
  final int height;
}

abstract interface class NativePortraitDecoder {
  Future<DecodedNativePortrait> decode(String portraitPath);
}

class NativeImg2ImgRequest {
  NativeImg2ImgRequest({
    required this.rgbBytes,
    required this.inputWidth,
    required this.inputHeight,
    required this.channels,
    required this.modelPath,
    required this.prompt,
    required this.negativePrompt,
    required this.cfgScale,
    required this.sampleSteps,
    required this.strength,
    required this.outputWidth,
    required this.outputHeight,
    required this.seed,
    required this.sampleMethodIndex,
  });

  final Uint8List rgbBytes;
  final int inputWidth;
  final int inputHeight;
  final int channels;
  final String modelPath;
  final String prompt;
  final String negativePrompt;
  final double cfgScale;
  final int sampleSteps;
  final double strength;
  final int outputWidth;
  final int outputHeight;
  final int seed;
  final int sampleMethodIndex;
}

abstract interface class NativeImg2ImgGenerator {
  Future<Uint8List> generatePng(
    NativeImg2ImgRequest request, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  });

  Future<void> cancel();
}

abstract interface class NativePortraitOutputStore {
  Future<String> writePng(Uint8List pngBytes);
}

class NativeLocalDiffusionImg2ImgBridge implements LocalDiffusionImg2ImgBridge {
  NativeLocalDiffusionImg2ImgBridge({
    required NativePortraitDecoder decoder,
    required NativeImg2ImgGenerator generator,
    required NativePortraitOutputStore outputStore,
  })  : _decoder = decoder,
        _generator = generator,
        _outputStore = outputStore;

  final NativePortraitDecoder _decoder;
  final NativeImg2ImgGenerator _generator;
  final NativePortraitOutputStore _outputStore;

  @override
  Future<String> generate(
    LocalDiffusionImg2ImgCommand command, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  }) async {
    final portrait = await _decoder.decode(command.portraitPath);
    final request = NativeImg2ImgRequest(
      rgbBytes: portrait.rgbBytes,
      inputWidth: portrait.width,
      inputHeight: portrait.height,
      channels: 3,
      modelPath: command.modelPath,
      prompt: command.prompt,
      negativePrompt: command.negativePrompt,
      cfgScale: command.cfgScale,
      sampleSteps: command.sampleSteps,
      strength: command.strength,
      outputWidth: command.outputWidth,
      outputHeight: command.outputHeight,
      seed: command.seed,
      sampleMethodIndex: command.sampleMethodIndex,
    );

    final pngBytes = await _generator.generatePng(
      request,
      onProgress: onProgress,
    );
    return _outputStore.writePng(pngBytes);
  }

  @override
  Future<void> cancel() => _generator.cancel();
}
