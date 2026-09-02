import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/portrait_model.dart';
import 'portrait_compute_backend.dart';

typedef PortraitActiveModelRootDirectoryProvider = Future<Directory> Function();

abstract interface class PortraitActiveModelStore {
  Future<String?> loadSelection();
  Future<void> saveSelection(String selection);
  Future<void> clearSelection();
}

class FilePortraitActiveModelStore implements PortraitActiveModelStore {
  FilePortraitActiveModelStore({
    PortraitActiveModelRootDirectoryProvider? rootDirectoryProvider,
  }) : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationDocumentsDirectory;

  final PortraitActiveModelRootDirectoryProvider _rootDirectoryProvider;

  Future<File> _file() async {
    final root = await _rootDirectoryProvider();
    final directory = Directory('${root.path}/portrait_lab/settings');
    await directory.create(recursive: true);
    return File('${directory.path}/active_model.txt');
  }

  @override
  Future<String?> loadSelection() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> saveSelection(String selection) async {
    final value = selection.trim();
    if (value.isEmpty) {
      await clearSelection();
      return;
    }
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  @override
  Future<void> clearSelection() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) await temp.delete();
  }
}

PortraitModelSpec? portraitModelForSelection(String selection) {
  final uri = Uri.tryParse(selection);
  if (uri == null || (uri.scheme != 'qnn' && uri.scheme != 'dream')) {
    return null;
  }
  final modelId = uri.queryParameters['model_id']?.trim();
  if (modelId == null || modelId.isEmpty) return null;
  for (final model in PortraitModelCatalog.curated) {
    if (model.id == modelId || model.dreamModelId == modelId) return model;
  }
  return null;
}

String portraitActiveModelDisplayName(String selection) {
  final model = portraitModelForSelection(selection);
  if (model != null) return model.displayName;
  final uri = Uri.tryParse(selection);
  if (uri != null && uri.scheme == 'dream') return 'DREAM Host';
  final normalized = selection.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  return name.isEmpty ? selection : name;
}

String portraitActiveBackendLabel(String? selection) {
  final uri = selection == null ? null : Uri.tryParse(selection);
  switch (uri?.scheme) {
    case 'qnn':
      return 'NPU · QNN/HTP';
    case 'dream':
      return 'NPU · DREAM Host';
    default:
      return PortraitComputeBackendRegistry.current.displayLabel;
  }
}

bool portraitActiveBackendIsAccelerated(String? selection) {
  final uri = selection == null ? null : Uri.tryParse(selection);
  if (uri?.scheme == 'qnn' || uri?.scheme == 'dream') return true;
  return PortraitComputeBackendRegistry.current.isGpuAccelerated;
}
