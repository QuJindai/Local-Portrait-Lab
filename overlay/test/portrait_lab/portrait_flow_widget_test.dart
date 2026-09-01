import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_controller.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_engine.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/portrait_lab_app.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_input_picker.dart';

class FakePortraitPhotoPicker implements PortraitPhotoPicker {
  @override
  Future<String?> pickPortrait() async => '/tmp/person.jpg';
}

class FakePortraitModelPicker implements PortraitModelPicker {
  @override
  Future<String?> pickModel() async => '/models/portrait.safetensors';
}

class ControlledPortraitEngine implements PortraitGenerationEngine {
  final Completer<String> _result = Completer<String>();
  bool cancelCalled = false;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    onState(const PortraitGenerationState.loadingModel());
    onState(const PortraitGenerationState.sampling(step: 1, steps: 4));
    final output = await _result.future;
    onState(const PortraitGenerationState.sampling(step: 4, steps: 4));
    return output;
  }

  void complete([String output = '/tmp/result.png']) {
    if (!_result.isCompleted) {
      _result.complete(output);
    }
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    if (!_result.isCompleted) {
      _result.completeError(const PortraitGenerationCancelledException());
    }
  }
}

void main() {
  testWidgets('P01 to P04 uses real engine progress and reaches generated result',
      (tester) async {
    final engine = ControlledPortraitEngine();
    final controller = PortraitGenerationController(engine);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      PortraitLabApp(
        controller: controller,
        photoPicker: FakePortraitPhotoPicker(),
        modelPicker: FakePortraitModelPicker(),
      ),
    );

    expect(find.text('本地 AI 人像实验室'), findsOneWidget);

    await tester.tap(find.byKey(const Key('portrait-pick-photo')));
    await tester.pump();
    expect(find.text('person.jpg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('portrait-pick-model')));
    await tester.pump();
    expect(find.text('portrait.safetensors'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('portrait-next-style')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('portrait-next-style')));
    await tester.pumpAndSettle();
    expect(find.text('选择风格'), findsOneWidget);

    await tester.tap(find.byKey(const Key('portrait-style-japanese_fresh')));
    await tester.tap(find.byKey(const Key('portrait-start-generation')));
    await tester.pump();

    expect(find.text('正在本地生成'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    engine.complete();
    await tester.pumpAndSettle();

    expect(find.text('生成结果'), findsOneWidget);
    expect(find.text('result.png'), findsOneWidget);
    expect(find.textContaining('已保存到本地作品'), findsOneWidget);
  });
}
