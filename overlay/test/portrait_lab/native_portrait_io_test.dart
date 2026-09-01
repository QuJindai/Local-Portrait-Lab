import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:local_diffusion/portrait_lab/infrastructure/native_portrait_io.dart';

void main() {
  test('image decoder converts a PNG portrait into packed RGB bytes', () async {
    final temp = await Directory.systemTemp.createTemp('portrait-io-');
    addTearDown(() => temp.delete(recursive: true));
    final source = img.Image(width: 2, height: 1, numChannels: 3);
    source.setPixelRgb(0, 0, 10, 20, 30);
    source.setPixelRgb(1, 0, 40, 50, 60);
    final sourceFile = File('${temp.path}/portrait.png');
    await sourceFile.writeAsBytes(img.encodePng(source), flush: true);

    final decoded = await ImagePackageNativePortraitDecoder().decode(
      sourceFile.path,
    );

    expect(decoded.width, 2);
    expect(decoded.height, 1);
    expect(decoded.rgbBytes, Uint8List.fromList(<int>[10, 20, 30, 40, 50, 60]));
  });

  test('image decoder rejects a file that cannot be decoded', () async {
    final temp = await Directory.systemTemp.createTemp('portrait-io-bad-');
    addTearDown(() => temp.delete(recursive: true));
    final sourceFile = File('${temp.path}/broken.jpg');
    await sourceFile.writeAsString('not an image', flush: true);

    await expectLater(
      ImagePackageNativePortraitDecoder().decode(sourceFile.path),
      throwsA(isA<NativePortraitDecodeException>()),
    );
  });

  test('output store writes generated PNG into app-private portrait history',
      () async {
    final temp = await Directory.systemTemp.createTemp('portrait-output-');
    addTearDown(() => temp.delete(recursive: true));
    final store = FileNativePortraitOutputStore(
      rootDirectoryProvider: () async => temp,
      clockMillis: () => 1788242400000,
    );
    final pngBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);

    final path = await store.writePng(pngBytes);

    expect(path, endsWith('/portrait_lab/history/portrait_1788242400000.png'));
    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), pngBytes);
  });
}
