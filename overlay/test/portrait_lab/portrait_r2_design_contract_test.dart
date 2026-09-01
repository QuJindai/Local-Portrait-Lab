import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_controller.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_engine.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/portrait_lab_app.dart';
import 'package:local_diffusion/portrait_lab/ui/portrait_input_picker.dart';

class _NoopEngine implements PortraitGenerationEngine {
  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async => '/tmp/result.png';

  @override
  Future<void> cancel() async {}
}

class _NoopPhotoPicker implements PortraitPhotoPicker {
  @override
  Future<String?> pickPortrait() async => null;
}

class _NoopModelPicker implements PortraitModelPicker {
  @override
  Future<String?> pickModel() async => null;
}

void main() {
  testWidgets('R2 home follows the approved product hierarchy', (tester) async {
    final controller = PortraitGenerationController(_NoopEngine());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      PortraitLabApp(
        controller: controller,
        photoPicker: _NoopPhotoPicker(),
        modelPicker: _NoopModelPicker(),
      ),
    );

    expect(find.text('把一张照片，变成新的你'), findsOneWidget);
    expect(find.text('热门风格'), findsOneWidget);
    expect(find.text('输出比例'), findsOneWidget);
    expect(find.text('本地模型'), findsOneWidget);
    expect(find.text('生成我的照片'), findsOneWidget);
    expect(find.byKey(const Key('portrait-hero-photo')), findsOneWidget);
  });
}
