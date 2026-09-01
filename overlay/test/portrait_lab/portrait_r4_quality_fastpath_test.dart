import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/local_diffusion_runtime_profile.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/native_portrait_io.dart';

void main() {
  test('R4 center-crops and resizes portrait to exact inference dimensions', () async {
    final temp = await Directory.systemTemp.createTemp('portrait-r4-crop-');
    addTearDown(() => temp.delete(recursive: true));

    final source = img.Image(width: 4, height: 2, numChannels: 3);
    for (var y = 0; y < 2; y++) {
      source.setPixelRgb(0, y, 255, 0, 0);
      source.setPixelRgb(1, y, 0, 255, 0);
      source.setPixelRgb(2, y, 0, 0, 255);
      source.setPixelRgb(3, y, 255, 255, 0);
    }
    final file = File('${temp.path}/wide.png');
    await file.writeAsBytes(img.encodePng(source), flush: true);

    final decoded = await ImagePackageNativePortraitDecoder().decode(
      file.path,
      targetWidth: 2,
      targetHeight: 2,
    );

    expect(decoded.width, 2);
    expect(decoded.height, 2);
    expect(decoded.rgbBytes.length, 12);
    expect(decoded.rgbBytes.sublist(0, 3), <int>[0, 255, 0]);
    expect(decoded.rgbBytes.sublist(3, 6), <int>[0, 0, 255]);
  });

  test('R4 keeps LCM fast profile available for imported LCM checkpoints', () {
    final normal = PortraitGenerationRequest.fromStyle(
      portraitPath: '/tmp/person.jpg',
      modelPath: '/models/dreamshaper_8.safetensors',
      style: PortraitStyle.japaneseFresh,
    );
    final fast = PortraitGenerationRequest.fromStyle(
      portraitPath: '/tmp/person.jpg',
      modelPath: '/models/custom_lcm_portrait.safetensors',
      style: PortraitStyle.japaneseFresh,
    );

    final normalProfile = LocalDiffusionRuntimeProfile.forRequest(normal);
    final fastProfile = LocalDiffusionRuntimeProfile.forRequest(fast);

    expect(normalProfile.sampleMethodIndex, 0);
    expect(normalProfile.sampleSteps, normal.steps);
    expect(normalProfile.cfgScale, normal.cfgScale);
    expect(normalProfile.isFastPath, isFalse);

    expect(fastProfile.sampleMethodIndex, 9);
    expect(fastProfile.sampleSteps, 6);
    expect(fastProfile.cfgScale, 1.0);
    expect(fastProfile.isFastPath, isTrue);
  });
}
