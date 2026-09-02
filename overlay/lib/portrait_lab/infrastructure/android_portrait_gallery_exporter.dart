import 'package:flutter/services.dart';

import 'portrait_gallery_exporter.dart';

class AndroidPortraitGalleryExporter implements PortraitGalleryExporter {
  const AndroidPortraitGalleryExporter({
    MethodChannel channel = const MethodChannel(
      'com.qujindai.localportraitlab/gallery',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<PortraitGalleryExportResult> export(String sourcePath) async {
    if (sourcePath.trim().isEmpty) {
      throw const PortraitGalleryExportException('生成结果路径为空。');
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'export',
        <String, Object?>{'sourcePath': sourcePath},
      );
      if (raw == null) {
        throw const PortraitGalleryExportException('Android 相册导出没有返回 MediaStore 回执。');
      }
      final uri = (raw['uri'] ?? '').toString().trim();
      final displayName = (raw['displayName'] ?? '').toString().trim();
      final relativePath = (raw['relativePath'] ?? '').toString().trim();
      final mimeType = (raw['mimeType'] ?? '').toString().trim();
      if (uri.isEmpty ||
          displayName.isEmpty ||
          relativePath.isEmpty ||
          mimeType.isEmpty) {
        throw const PortraitGalleryExportException('Android 相册导出回执不完整。');
      }
      return PortraitGalleryExportResult(
        uri: uri,
        displayName: displayName,
        relativePath: relativePath,
        mimeType: mimeType,
      );
    } on PortraitGalleryExportException {
      rethrow;
    } on PlatformException catch (error) {
      throw PortraitGalleryExportException(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Android MediaStore 导出失败（${error.code}）。',
      );
    } on MissingPluginException {
      throw const PortraitGalleryExportException('当前平台没有 Android MediaStore 相册桥。');
    }
  }

  @override
  Future<void> open(PortraitGalleryExportResult result) async {
    try {
      await _channel.invokeMethod<void>('open', <String, Object?>{
        'uri': result.uri,
        'mimeType': result.mimeType,
      });
    } on PlatformException catch (error) {
      throw PortraitGalleryExportException(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : '无法打开系统图片查看器（${error.code}）。',
      );
    } on MissingPluginException {
      throw const PortraitGalleryExportException('当前平台不能打开 Android 系统相册。');
    }
  }
}
