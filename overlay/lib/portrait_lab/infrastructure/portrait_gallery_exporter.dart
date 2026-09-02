class PortraitGalleryExportResult {
  const PortraitGalleryExportResult({
    required this.uri,
    required this.displayName,
    required this.relativePath,
    required this.mimeType,
  });

  final String uri;
  final String displayName;
  final String relativePath;
  final String mimeType;
}

class PortraitGalleryExportException implements Exception {
  const PortraitGalleryExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class PortraitGalleryExporter {
  Future<PortraitGalleryExportResult> export(String sourcePath);

  Future<void> open(PortraitGalleryExportResult result);
}
