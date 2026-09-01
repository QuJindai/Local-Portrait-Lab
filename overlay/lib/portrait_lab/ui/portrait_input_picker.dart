import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

abstract interface class PortraitPhotoPicker {
  Future<String?> pickPortrait();
}

abstract interface class PortraitModelPicker {
  Future<String?> pickModel();
}

class SystemPortraitPhotoPicker implements PortraitPhotoPicker {
  SystemPortraitPhotoPicker({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<String?> pickPortrait() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    return image?.path;
  }
}

class SystemPortraitModelPicker implements PortraitModelPicker {
  @override
  Future<String?> pickModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    return result.files.single.path;
  }
}

String portraitFileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}
