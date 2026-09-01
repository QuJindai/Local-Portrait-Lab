import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/native_local_diffusion_img2img_bridge.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/upstream_local_diffusion_native_generator.dart';

class FakeUpstreamImg2ImgSession implements UpstreamImg2ImgSession {
  NativeImg2ImgRequest? lastRequest;
  bool disposed = false;
  bool hold = false;
  final Completer<Uint8List> _heldResult = Completer<Uint8List>();
  final Uint8List result = Uint8List.fromList(<int>[137, 80, 78, 71]);

  @override
  Future<Uint8List> generatePng(
    NativeImg2ImgRequest request, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  }) async {
    lastRequest = request;
    onProgress(1, request.sampleSteps, 0.2);
    if (hold) {
      return _heldResult.future;
    }
    onProgress(request.sampleSteps, request.sampleSteps, 1.1);
    return result;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (hold && !_heldResult.isCompleted) {
      _heldResult.completeError(StateError('native session disposed'));
    }
  }
}

class FakeUpstreamImg2ImgSessionFactory implements UpstreamImg2ImgSessionFactory {
  FakeUpstreamImg2ImgSessionFactory(this.session);

  final FakeUpstreamImg2ImgSession session;
  int createCount = 0;

  @override
  UpstreamImg2ImgSession create() {
    createCount += 1;
    return session;
  }
}

NativeImg2ImgRequest requestFixture() => NativeImg2ImgRequest(
      rgbBytes: Uint8List.fromList(<int>[1, 2, 3]),
      inputWidth: 1,
      inputHeight: 1,
      channels: 3,
      modelPath: '/models/portrait.safetensors',
      prompt: 'portrait',
      negativePrompt: 'blurry',
      cfgScale: 6.0,
      sampleSteps: 8,
      strength: 0.55,
      outputWidth: 512,
      outputHeight: 768,
      seed: -1,
      sampleMethodIndex: 0,
    );

void main() {
  test('native generator forwards request/progress and disposes session after success',
      () async {
    final session = FakeUpstreamImg2ImgSession();
    final factory = FakeUpstreamImg2ImgSessionFactory(session);
    final generator = UpstreamLocalDiffusionNativeGenerator(factory: factory);
    final progress = <String>[];
    final request = requestFixture();

    final result = await generator.generatePng(
      request,
      onProgress: (step, steps, elapsedSeconds) {
        progress.add('$step/$steps@${elapsedSeconds.toStringAsFixed(1)}');
      },
    );

    expect(result, session.result);
    expect(factory.createCount, 1);
    expect(session.lastRequest, same(request));
    expect(progress, <String>['1/8@0.2', '8/8@1.1']);
    expect(session.disposed, isTrue);
  });

  test('cancel disposes the active upstream session', () async {
    final session = FakeUpstreamImg2ImgSession()..hold = true;
    final generator = UpstreamLocalDiffusionNativeGenerator(
      factory: FakeUpstreamImg2ImgSessionFactory(session),
    );
    final future = generator.generatePng(
      requestFixture(),
      onProgress: (_, __, ___) {},
    );
    final failureExpectation = expectLater(future, throwsStateError);

    await Future<void>.delayed(Duration.zero);
    await generator.cancel();
    await failureExpectation;

    expect(session.disposed, isTrue);
  });

  test('invocation preserves the upstream img2img primitive values', () {
    final invocation = UpstreamImg2ImgInvocation.fromRequest(requestFixture());

    expect(invocation.channel, 3);
    expect(invocation.outputWidth, 512);
    expect(invocation.outputHeight, 768);
    expect(invocation.prompt, 'portrait');
    expect(invocation.negativePrompt, 'blurry');
    expect(invocation.cfgScale, 6.0);
    expect(invocation.sampleSteps, 8);
    expect(invocation.strength, 0.55);
    expect(invocation.seed, -1);
    expect(invocation.sampleMethod, 0);
    expect(invocation.batchCount, 1);
  });
}
