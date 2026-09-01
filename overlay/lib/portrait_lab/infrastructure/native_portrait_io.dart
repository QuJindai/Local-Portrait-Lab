import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'native_local_diffusion_img2img_bridge.dart';

class NativePortraitDecodeException implements Exception {
  const NativePortraitDecodeException(this.message);

  final String message;

  @override
  String toString() => 'NativePortraitDecodeException: $message';
}

class ImagePackageNativePortraitDecoder implements NativePortraitDecoder {
  @override
  Future<DecodedNativePortrait> decode(String portraitPath) async {
    final path = portraitPath.trim();
    if (path.isEmpty) {
      throw const NativePortraitDecodeException('Portrait path is empty.');
    }

    final file = File(path);
    Uint8List encoded;
    try {
      encoded = await file.readAsBytes();
    } on FileSystemException catch (error) {
      throw NativePortraitDecodeException(
        'Unable to read portrait image: ${error.message}',
      );
    }

    final decoded = img.decodeImage(encoded);
    if (decoded == null) {
      throw const NativePortraitDecodeException(
        'Unsupported or corrupted portrait image.',
      );
    }

    final oriented = img.bakeOrientation(decoded);
    final rgb = oriented.getBytes(order: img.ChannelOrder.rgb);
    return DecodedNativePortrait(
      rgbBytes: Uint8List.fromList(rgb),
      width: oriented.width,
      height: oriented.height,
    );
  }
}

typedef NativePortraitRootDirectoryProvider = Future<Directory> Function();

class FileNativePortraitOutputStore implements NativePortraitOutputStore {
  FileNativePortraitOutputStore({
    NativePortraitRootDirectoryProvider? rootDirectoryProvider,
    int Function()? clockMillis,
  })  : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationDocumentsDirectory,
        _clockMillis =
            clockMillis ?? (() => DateTime.now().millisecondsSinceEpoch);

  final NativePortraitRootDirectoryProvider _rootDirectoryProvider;
  final int Function() _clockMillis;

  @override
  Future<String> writePng(Uint8List pngBytes) async {
    if (pngBytes.isEmpty) {
      throw ArgumentError.value(pngBytes, 'pngBytes', 'PNG output is empty.');
    }

    final root = await _rootDirectoryProvider();
    final historyDirectory = Directory('${root.path}/portrait_lab/history');
    await historyDirectory.create(recursive: true);

    final path =
        '${historyDirectory.path}/portrait_${_clockMillis()}.png';
    final file = File(path);
    await file.writeAsBytes(pngBytes, flush: true);
    return file.path;
  }
}
