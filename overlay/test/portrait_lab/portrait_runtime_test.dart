import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_controller.dart';
import 'package:local_diffusion/portrait_lab/portrait_runtime.dart';

void main() {
  test('production runtime composes the local portrait generation controller',
      () async {
    final controller = PortraitRuntime.createController();

    expect(controller, isA<PortraitGenerationController>());

    await controller.dispose();
  });
}
