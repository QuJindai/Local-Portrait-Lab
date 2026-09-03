import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R10.2 QNN health socket probe runs off the Flutter UI thread', () async {
    final activity = await File(
      'android/app/src/main/kotlin/com/qujindai/localportraitlab/MainActivity.kt',
    ).readAsString();

    final healthStart = activity.indexOf('"health" -> {');
    final stopStart = activity.indexOf('"stop" -> {', healthStart);
    expect(healthStart, greaterThanOrEqualTo(0));
    expect(stopStart, greaterThan(healthStart));

    final healthBlock = activity.substring(healthStart, stopStart);
    expect(healthBlock, contains('qnnExecutor.execute'));
    expect(healthBlock, contains('PortraitQnnBackendService.health(modelId)'));
    expect(healthBlock, contains('runOnUiThread'));
  });
}
