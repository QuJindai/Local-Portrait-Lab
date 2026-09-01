import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../image_processing_utils.dart';
import 'native_local_diffusion_img2img_bridge.dart';

class NativePortraitDecodeException implements Exception {
  const NativePortraitDecodeException(this.message);

  final String message;

  @override
  String toString() => 'NativePortraitDecodeException: $message';
}

class ImagePackageNativePortraitDecoder implements NativePortraitDecoder {
  @override
  Future<DecodedNativePortrait> decode(
    String portraitPath, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    final path = portraitPath.trim();
    if (path.isEmpty) {
      throw const NativePortraitDecodeException('Portrait path is empty.');
    }
    if ((targetWidth == null) != (targetHeight == null)) {
      throw const NativePortraitDecodeException(
        'Target width and height must be provided together.',
      );
    }
    if ((targetWidth != null && targetWidth <= 0) ||
        (targetHeight != null && targetHeight <= 0)) {
      throw const NativePortraitDecodeException(
        'Target dimensions must be positive.',
      );
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
    final rgb = Uint8List.fromList(
      oriented.getBytes(order: img.ChannelOrder.rgb),
    );

    if (targetWidth != null && targetHeight != null) {
      final processed = cropImage(
        rgb,
        oriented.width,
        oriented.height,
        targetWidth,
        targetHeight,
      );
      return DecodedNativePortrait(
        rgbBytes: processed.bytes,
        width: processed.width,
        height: processed.height,
      );
    }

    return DecodedNativePortrait(
      rgbBytes: rgb,
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

    final path = '${historyDirectory.path}/portrait_${_clockMillis()}.png';
    final file = File(path);
    await file.writeAsBytes(pngBytes, flush: true);
    return file.path;
  }
}
