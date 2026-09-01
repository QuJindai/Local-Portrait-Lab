import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/local_diffusion_img2img_bridge.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/native_local_diffusion_img2img_bridge.dart';

class FakeNativePortraitDecoder implements NativePortraitDecoder {
  String? lastPath;
  int? lastTargetWidth;
  int? lastTargetHeight;
  DecodedNativePortrait decoded = DecodedNativePortrait(
    rgbBytes: Uint8List(512 * 768 * 3),
    width: 512,
    height: 768,
  );

  @override
  Future<DecodedNativePortrait> decode(
    String portraitPath, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    lastPath = portraitPath;
    lastTargetWidth = targetWidth;
    lastTargetHeight = targetHeight;
    return decoded;
  }
}

class FakeNativeImg2ImgGenerator implements NativeImg2ImgGenerator {
  NativeImg2ImgRequest? lastRequest;
  bool cancelCalled = false;
  Uint8List generatedPng = Uint8List.fromList(<int>[137, 80, 78, 71]);

  @override
  Future<Uint8List> generatePng(
    NativeImg2ImgRequest request, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  }) async {
    lastRequest = request;
    onProgress(2, 8, 0.5);
    onProgress(8, 8, 2.0);
    return generatedPng;
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
  }
}

class FakeNativePortraitOutputStore implements NativePortraitOutputStore {
  Uint8List? lastBytes;
  String outputPath = '/private/portrait-lab/result.png';

  @override
  Future<String> writePng(Uint8List pngBytes) async {
    lastBytes = Uint8List.fromList(pngBytes);
    return outputPath;
  }
}

void main() {
  test('decodes source at output size, runs native img2img, stores PNG and forwards progress',
      () async {
    final decoder = FakeNativePortraitDecoder();
    final generator = FakeNativeImg2ImgGenerator();
    final outputStore = FakeNativePortraitOutputStore();
    final bridge = NativeLocalDiffusionImg2ImgBridge(
      decoder: decoder,
      generator: generator,
      outputStore: outputStore,
    );
    final command = LocalDiffusionImg2ImgCommand(
      portraitPath: '/photos/me.jpg',
      modelPath: '/models/portrait.safetensors',
      prompt: 'professional portrait',
      negativePrompt: 'blurry',
      cfgScale: 6.0,
      sampleSteps: 20,
      strength: 0.55,
      outputWidth: 512,
      outputHeight: 768,
      seed: -1,
      sampleMethodIndex: 0,
    );
    final progress = <String>[];

    final output = await bridge.generate(
      command,
      onProgress: (step, steps, elapsedSeconds) {
        progress.add('$step/$steps@${elapsedSeconds.toStringAsFixed(1)}');
      },
    );

    expect(output, '/private/portrait-lab/result.png');
    expect(decoder.lastPath, '/photos/me.jpg');
    expect(decoder.lastTargetWidth, 512);
    expect(decoder.lastTargetHeight, 768);
    expect(generator.lastRequest, isNotNull);
    expect(generator.lastRequest!.rgbBytes, decoder.decoded.rgbBytes);
    expect(generator.lastRequest!.inputWidth, 512);
    expect(generator.lastRequest!.inputHeight, 768);
    expect(generator.lastRequest!.channels, 3);
    expect(generator.lastRequest!.modelPath, command.modelPath);
    expect(generator.lastRequest!.prompt, command.prompt);
    expect(generator.lastRequest!.negativePrompt, command.negativePrompt);
    expect(generator.lastRequest!.cfgScale, command.cfgScale);
    expect(generator.lastRequest!.sampleSteps, command.sampleSteps);
    expect(generator.lastRequest!.strength, command.strength);
    expect(generator.lastRequest!.outputWidth, command.outputWidth);
    expect(generator.lastRequest!.outputHeight, command.outputHeight);
    expect(generator.lastRequest!.seed, command.seed);
    expect(generator.lastRequest!.sampleMethodIndex, command.sampleMethodIndex);
    expect(outputStore.lastBytes, generator.generatedPng);
    expect(progress, <String>['2/8@0.5', '8/8@2.0']);
  });

  test('cancel delegates to native generator teardown', () async {
    final generator = FakeNativeImg2ImgGenerator();
    final bridge = NativeLocalDiffusionImg2ImgBridge(
      decoder: FakeNativePortraitDecoder(),
      generator: generator,
      outputStore: FakeNativePortraitOutputStore(),
    );

    await bridge.cancel();

    expect(generator.cancelCalled, isTrue);
  });
}
