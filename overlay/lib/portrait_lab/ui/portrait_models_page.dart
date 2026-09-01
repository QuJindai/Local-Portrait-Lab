import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/portrait_model.dart';
import '../infrastructure/portrait_model_downloader.dart';
import 'portrait_input_picker.dart';

class PortraitModelsPage extends StatefulWidget {
  const PortraitModelsPage({
    super.key,
    required this.downloader,
    required this.customModelPicker,
  });

  final PortraitModelDownloadService downloader;
  final PortraitModelPicker customModelPicker;

  @override
  State<PortraitModelsPage> createState() => _PortraitModelsPageState();
}

class _PortraitModelsPageState extends State<PortraitModelsPage> {
  final Map<String, String> _installed = <String, String>{};
  final Map<String, PortraitModelDownloadState> _states =
      <String, PortraitModelDownloadState>{};
  String? _activeModelId;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshInstalled());
  }

  Future<void> _refreshInstalled() async {
    for (final model in PortraitModelCatalog.curated) {
      final path = await widget.downloader.installedPath(model);
      if (!mounted) return;
      if (path != null) {
        setState(() => _installed[model.id] = path);
      }
    }
  }

  Future<void> _download(PortraitModelSpec model) async {
    if (_activeModelId != null && _activeModelId != model.id) return;
    setState(() {
      _activeModelId = model.id;
      _states.remove(model.id);
    });

    await for (final state in widget.downloader.download(model)) {
      if (!mounted) return;
      setState(() {
        _states[model.id] = state;
        if (state is PortraitModelDownloadCompleted) {
          _installed[model.id] = state.path;
          _activeModelId = null;
        } else if (state is PortraitModelDownloadCancelled ||
            state is PortraitModelDownloadFailed) {
          _activeModelId = null;
        }
      });
    }
  }

  Future<void> _cancel() => widget.downloader.cancel();

  Future<void> _importCustom() async {
    final path = await widget.customModelPicker.pickModel();
    if (!mounted || path == null || path.trim().isEmpty) return;
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型管理'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'P06 · 本地模型',
                style: TextStyle(fontSize: 12, color: Color(0xFF827A91)),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEEE9FF), Color(0xFFFFEFF6)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.cloud_download_rounded,
                          color: Color(0xFF6D4CF5)),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '下载后完全离线使用',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '支持断点续传与 SHA-256 完整性校验。模型保存在应用私有目录。',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Color(0xFF70697D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                key: const Key('model-import-custom'),
                onPressed: _importCustom,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Text('导入本地模型'),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '推荐模型',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                '首批均为 SD1.5 单文件 SafeTensors，可直接交给 Local-Diffusion。',
                style: TextStyle(color: Color(0xFF807889), fontSize: 12),
              ),
              const SizedBox(height: 12),
              for (final model in PortraitModelCatalog.curated) ...[
                _ModelCard(
                  model: model,
                  state: _states[model.id],
                  installedPath: _installed[model.id],
                  anotherDownloadActive:
                      _activeModelId != null && _activeModelId != model.id,
                  onDownload: () => _download(model),
                  onCancel: _cancel,
                  onUse: () => Navigator.of(context).pop(_installed[model.id]),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              const Text(
                '提示：模型文件通常为 2–4 GB，建议连接 Wi‑Fi 并预留足够存储空间。下载中断后再次点击可继续。',
                style: TextStyle(
                  color: Color(0xFF8C8495),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.state,
    required this.installedPath,
    required this.anotherDownloadActive,
    required this.onDownload,
    required this.onCancel,
    required this.onUse,
  });

  final PortraitModelSpec model;
  final PortraitModelDownloadState? state;
  final String? installedPath;
  final bool anotherDownloadActive;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final progress = state is PortraitModelDownloadProgress
        ? state as PortraitModelDownloadProgress
        : null;
    final failed = state is PortraitModelDownloadFailed
        ? state as PortraitModelDownloadFailed
        : null;
    final cancelled = state is PortraitModelDownloadCancelled;
    final verifying = state is PortraitModelDownloadVerifying;
    final installed = installedPath != null;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9E5EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _accent(model.id),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFF544A67)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${model.sizeLabel} · ${model.format}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7E768A),
                      ),
                    ),
                  ],
                ),
              ),
              if (installed)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF4EB36A), size: 22),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            model.description,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            '${model.sourceLabel} · ${model.licenseLabel}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF938B9B)),
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress.fraction),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _bytes(progress.receivedBytes),
                  style: const TextStyle(fontSize: 10),
                ),
                Text(
                  progress.totalBytes > 0
                      ? '${((progress.fraction ?? 0) * 100).round()}%'
                      : '下载中',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
          if (verifying) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('正在校验 SHA-256…', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
          if (failed != null) ...[
            const SizedBox(height: 8),
            Text(
              failed.message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 11,
              ),
            ),
          ],
          if (cancelled) ...[
            const SizedBox(height: 8),
            const Text(
              '已暂停，保留已下载部分；再次点击可继续。',
              style: TextStyle(fontSize: 11, color: Color(0xFF8B6B30)),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: installed
                ? FilledButton.icon(
                    key: Key('model-use-${model.id}'),
                    onPressed: onUse,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('使用模型'),
                  )
                : progress != null || verifying
                    ? OutlinedButton.icon(
                        key: Key('model-cancel-${model.id}'),
                        onPressed: verifying ? null : onCancel,
                        icon: const Icon(Icons.pause_rounded),
                        label: Text(verifying ? '校验中' : '暂停下载'),
                      )
                    : FilledButton.icon(
                        key: Key('model-download-${model.id}'),
                        onPressed: anotherDownloadActive ? null : onDownload,
                        icon: const Icon(Icons.download_rounded),
                        label: Text(
                          failed != null || cancelled ? '继续下载' : '下载模型',
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  static Color _accent(String id) {
    switch (id) {
      case 'sd15':
        return const Color(0xFFEAE5FF);
      case 'dreamshaper8':
        return const Color(0xFFFFE7F0);
      default:
        return const Color(0xFFE5F0FF);
    }
  }

  static String _bytes(int value) {
    if (value >= 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / 1024).toStringAsFixed(1)} KB';
  }
}
