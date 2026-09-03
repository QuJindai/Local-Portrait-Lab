import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef PortraitDownloadSourceRootProvider = Future<Directory> Function();

enum PortraitDownloadSource {
  official,
  hfMirror;

  String get id => switch (this) {
        PortraitDownloadSource.official => 'official',
        PortraitDownloadSource.hfMirror => 'hf-mirror',
      };

  String get label => switch (this) {
        PortraitDownloadSource.official => 'Hugging Face 官方',
        PortraitDownloadSource.hfMirror => 'hf-mirror 国内镜像',
      };

  String resolveUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    if (uri.host != 'huggingface.co' && uri.host != 'hf-mirror.com') {
      return url;
    }
    return uri
        .replace(
          host: this == PortraitDownloadSource.hfMirror
              ? 'hf-mirror.com'
              : 'huggingface.co',
        )
        .toString();
  }

  static PortraitDownloadSource fromId(String? value) =>
      value?.trim() == 'hf-mirror'
          ? PortraitDownloadSource.hfMirror
          : PortraitDownloadSource.official;
}

abstract class PortraitDownloadSourceStore {
  Future<PortraitDownloadSource> load();
  Future<void> save(PortraitDownloadSource source);
}

class MemoryPortraitDownloadSourceStore implements PortraitDownloadSourceStore {
  MemoryPortraitDownloadSourceStore([
    this.source = PortraitDownloadSource.official,
  ]);

  PortraitDownloadSource source;

  @override
  Future<PortraitDownloadSource> load() async => source;

  @override
  Future<void> save(PortraitDownloadSource value) async {
    source = value;
  }
}

class FilePortraitDownloadSourceStore implements PortraitDownloadSourceStore {
  FilePortraitDownloadSourceStore({
    PortraitDownloadSourceRootProvider? rootDirectoryProvider,
  }) : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationDocumentsDirectory;

  final PortraitDownloadSourceRootProvider _rootDirectoryProvider;

  Future<File> _file() async {
    final root = await _rootDirectoryProvider();
    final directory = Directory('${root.path}/portrait_lab');
    await directory.create(recursive: true);
    return File('${directory.path}/download_source.txt');
  }

  @override
  Future<PortraitDownloadSource> load() async {
    final file = await _file();
    if (!await file.exists()) return PortraitDownloadSource.official;
    return PortraitDownloadSource.fromId(await file.readAsString());
  }

  @override
  Future<void> save(PortraitDownloadSource source) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString('${source.id}\n', flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}

class PortraitDownloadSourceDefaults {
  const PortraitDownloadSourceDefaults._();

  static final PortraitDownloadSourceStore _nonAndroidStore =
      MemoryPortraitDownloadSourceStore();
  static final PortraitDownloadSourceStore _androidStore =
      FilePortraitDownloadSourceStore();

  static PortraitDownloadSource current = PortraitDownloadSource.official;

  static PortraitDownloadSourceStore get store =>
      Platform.isAndroid ? _androidStore : _nonAndroidStore;

  static Future<PortraitDownloadSource> load() async {
    current = await store.load();
    return current;
  }

  static Future<void> save(PortraitDownloadSource source) async {
    current = source;
    await store.save(source);
  }
}
