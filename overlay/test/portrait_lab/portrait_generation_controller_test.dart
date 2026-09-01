import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_controller.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_engine.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';

class FakePortraitEngine implements PortraitGenerationEngine {
  FakePortraitEngine({this.resultPath = '/tmp/generated.png'});

  final String resultPath;
  bool generateCalled = false;
  bool cancelCalled = false;
  PortraitGenerationRequest? lastRequest;
  void Function(PortraitGenerationState state)? _onState;
  final Completer<void> _release = Completer<void>();
  bool hold = false;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    generateCalled = true;
    lastRequest = request;
    _onState = onState;
    onState(const PortraitGenerationState.loadingModel());
    onState(const PortraitGenerationState.sampling(step: 1, steps: 4));
    if (hold) {
      await _release.future;
    }
    onState(const PortraitGenerationState.sampling(step: 4, steps: 4));
    return resultPath;
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  void emit(PortraitGenerationState state) => _onState?.call(state);
}

void main() {
  group('PortraitGenerationRequest', () {
    test('japanese fresh preset maps deterministic generation values', () {
      final request = PortraitGenerationRequest.fromStyle(
        portraitPath: '/tmp/person.jpg',
        modelPath: '/models/model.safetensors',
        style: PortraitStyle.japaneseFresh,
      );

      expect(request.portraitPath, '/tmp/person.jpg');
      expect(request.modelPath, '/models/model.safetensors');
      expect(request.prompt.toLowerCase(), contains('portrait'));
      expect(request.steps, greaterThan(0));
      expect(request.strength, inInclusiveRange(0.0, 1.0));
      expect(request.width % 64, 0);
      expect(request.height % 64, 0);
    });
  });

  group('PortraitGenerationController', () {
    test('generate rejects an empty portrait source before calling engine', () async {
      final engine = FakePortraitEngine();
      final controller = PortraitGenerationController(engine);

      await expectLater(
        controller.generate(
          portraitPath: '',
          modelPath: '/models/model.safetensors',
          style: PortraitStyle.japaneseFresh,
        ),
        throwsA(isA<PortraitInputException>()),
      );
      expect(engine.generateCalled, isFalse);
    });

    test('generate rejects an empty model path before calling engine', () async {
      final engine = FakePortraitEngine();
      final controller = PortraitGenerationController(engine);

      await expectLater(
        controller.generate(
          portraitPath: '/tmp/person.jpg',
          modelPath: '',
          style: PortraitStyle.japaneseFresh,
        ),
        throwsA(isA<PortraitModelException>()),
      );
      expect(engine.generateCalled, isFalse);
    });

    test('forwards ordered real engine progress and completes with output path',
        () async {
      final engine = FakePortraitEngine();
      final controller = PortraitGenerationController(engine);
      final states = <PortraitGenerationState>[];
      final subscription = controller.states.listen(states.add);

      final output = await controller.generate(
        portraitPath: '/tmp/person.jpg',
        modelPath: '/models/model.safetensors',
        style: PortraitStyle.japaneseFresh,
      );
      await Future<void>.delayed(Duration.zero);

      expect(output, '/tmp/generated.png');
      expect(
        states,
        containsAllInOrder(<PortraitGenerationState>[
          const PortraitGenerationState.preparing(),
          const PortraitGenerationState.loadingModel(),
          const PortraitGenerationState.sampling(step: 1, steps: 4),
          const PortraitGenerationState.sampling(step: 4, steps: 4),
          const PortraitGenerationState.completed('/tmp/generated.png'),
        ]),
      );
      await subscription.cancel();
      await controller.dispose();
    });

    test('cancel is terminal and suppresses completion after engine returns',
        () async {
      final engine = FakePortraitEngine()..hold = true;
      final controller = PortraitGenerationController(engine);
      final states = <PortraitGenerationState>[];
      final subscription = controller.states.listen(states.add);

      final future = controller.generate(
        portraitPath: '/tmp/person.jpg',
        modelPath: '/models/model.safetensors',
        style: PortraitStyle.japaneseFresh,
      );
      await Future<void>.delayed(Duration.zero);
      await controller.cancel();
      await expectLater(future, throwsA(isA<PortraitGenerationCancelledException>()));
      await Future<void>.delayed(Duration.zero);

      expect(engine.cancelCalled, isTrue);
      expect(states, contains(const PortraitGenerationState.cancelled()));
      expect(
        states.where((state) => state is PortraitGenerationCompleted),
        isEmpty,
      );
      await subscription.cancel();
      await controller.dispose();
    });
  });
}
