import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../application/portrait_generation_controller.dart';
import '../domain/portrait_model.dart';
import '../domain/portrait_style.dart';
import '../infrastructure/portrait_active_model_store.dart';
import '../infrastructure/portrait_model_downloader.dart';
import 'portrait_input_picker.dart';
import 'portrait_models_page.dart';
import 'portrait_style_page.dart';

class PortraitHomePage extends StatefulWidget {
  const PortraitHomePage({
    super.key,
    required this.controller,
    required this.photoPicker,
    required this.modelPicker,
    this.modelDownloader,
    this.activeModelStore,
  });

  final PortraitGenerationController controller;
  final PortraitPhotoPicker photoPicker;
  final PortraitModelPicker modelPicker;
  final PortraitModelDownloadService? modelDownloader;
  final PortraitActiveModelStore? activeModelStore;

  @override
  State<PortraitHomePage> createState() => _PortraitHomePageState();
}

class _PortraitHomePageState extends State<PortraitHomePage> {
  static const _brand = Color(0xFF6D4CF5);
  String? _portraitPath;
  String? _modelPath;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreActiveModel());
  }

  Future<void> _restoreActiveModel() async {
    final store = widget.activeModelStore;
    final downloader = widget.modelDownloader;
    if (store == null) return;

    String? selection = await store.loadSelection();
    selection = await _validatePersistedSelection(selection);

    if (selection == null && downloader != null) {
      for (final model in PortraitModelCatalog.curated) {
        if (!model.usesDreamQnn) continue;
        final installed = await downloader.installedPath(model);
        if (installed == null) continue;
        final discovered = model.standaloneSelectionUri(installed);
        if (discovered == null) continue;
        await store.saveSelection(discovered);
        selection = discovered;
        break;
      }
    }

    if (!mounted || selection == null) return;
    setState(() => _modelPath = selection);
  }

  Future<String?> _validatePersistedSelection(String? selection) async {
    final store = widget.activeModelStore;
    if (selection == null || selection.trim().isEmpty || store == null) {
      return null;
    }
    final value = selection.trim();
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'qnn') {
      final downloader = widget.modelDownloader;
      final model = portraitModelForSelection(value);
      if (downloader == null || model == null) {
        await store.clearSelection();
        return null;
      }
      final installed = await downloader.installedPath(model);
      if (installed == null) {
        await store.clearSelection();
        return null;
      }
      final fresh = model.standaloneSelectionUri(installed);
      if (fresh == null) {
        await store.clearSelection();
        return null;
      }
      if (fresh != value) await store.saveSelection(fresh);
      return fresh;
    }
    if (uri?.scheme == 'dream') return value;
    if (await File(value).exists()) return value;
    await store.clearSelection();
    return null;
  }

  Future<void> _activateModel(String selection) async {
    final value = selection.trim();
    if (value.isEmpty) return;
    await widget.activeModelStore?.saveSelection(value);
    if (!mounted) return;
    setState(() => _modelPath = value);
  }

  Future<void> _pickPortrait() async {
    final path = await widget.photoPicker.pickPortrait();
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() => _portraitPath = path);
  }

  Future<void> _pickModel() async {
    final path = await widget.modelPicker.pickModel();
    if (!mounted || path == null || path.trim().isEmpty) return;
    await _activateModel(path);
  }

  Future<void> _openModelStore() async {
    final downloader = widget.modelDownloader;
    if (downloader == null) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PortraitModelsPage(
          downloader: downloader,
          customModelPicker: widget.modelPicker,
        ),
      ),
    );
    if (!mounted || path == null || path.trim().isEmpty) return;
    await _activateModel(path);
  }

  void _openStyles() {
    final portrait = _portraitPath;
    final model = _modelPath;
    if (portrait == null || model == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PortraitStylePage(
          controller: widget.controller,
          portraitPath: portrait,
          modelPath: model,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _portraitPath != null && _modelPath != null;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'AI 人像',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.4),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(child: _LocalBadge(modelPath: _modelPath)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 30),
          children: [
            const SizedBox(height: 4),
            Text(
              '把一张照片，变成新的你',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                    letterSpacing: -1.0,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              '本地 AI 人像实验室',
              style: TextStyle(
                color: Color(0xFF736C82),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            _ModelRow(
              modelPath: _modelPath,
              onPick: _pickModel,
              onStore: _openModelStore,
              storeEnabled: widget.modelDownloader != null,
            ),
            const SizedBox(height: 14),
            _PhotoHero(
              key: const Key('portrait-hero-photo'),
              portraitPath: _portraitPath,
              onPick: _pickPortrait,
            ),
            const SizedBox(height: 22),
            const _SectionHeader(title: '热门风格', trailing: '8 种本地预设'),
            const SizedBox(height: 12),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: PortraitStyle.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) => _StylePreview(
                  style: PortraitStyle.values[index],
                  index: index,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const _SectionHeader(title: '输出比例', trailing: '首包 3:4'),
            const SizedBox(height: 10),
            const Row(
              children: [
                _RatioChip(label: '1:1', enabled: false),
                SizedBox(width: 8),
                _RatioChip(label: '3:4', selected: true),
                SizedBox(width: 8),
                _RatioChip(label: '4:3', enabled: false),
                SizedBox(width: 8),
                _RatioChip(label: '9:16', enabled: false),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const Key('portrait-next-style'),
                onPressed: ready ? _openStyles : null,
                icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                label: const Text(
                  '生成我的照片',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              ready ? '下一步选择风格并在本机生成' : '先选择照片和本地模型后即可继续。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8B8497),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalBadge extends StatelessWidget {
  const _LocalBadge({required this.modelPath});

  final String? modelPath;

  @override
  Widget build(BuildContext context) {
    final label = portraitActiveBackendLabel(modelPath);
    final accelerated = portraitActiveBackendIsAccelerated(modelPath);
    final isNpu = modelPath != null &&
        (Uri.tryParse(modelPath!)?.scheme == 'qnn' ||
            Uri.tryParse(modelPath!)?.scheme == 'dream');
    final background = isNpu
        ? const Color(0xFFEDE8FF)
        : accelerated
            ? const Color(0xFFE8F2FF)
            : const Color(0xFFFFF1DA);
    final foreground = isNpu
        ? const Color(0xFF5D43D5)
        : accelerated
            ? const Color(0xFF2E5EAA)
            : const Color(0xFF875B1F);
    return Container(
      key: const Key('portrait-compute-backend-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isNpu ? Icons.memory_rounded : accelerated ? Icons.memory_rounded : Icons.warning_amber_rounded,
            size: 13,
            color: foreground,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.modelPath,
    required this.onPick,
    required this.onStore,
    required this.storeEnabled,
  });

  final String? modelPath;
  final VoidCallback onPick;
  final VoidCallback onStore;
  final bool storeEnabled;

  @override
  Widget build(BuildContext context) {
    final selected = modelPath != null;
    final displayName = selected ? portraitActiveModelDisplayName(modelPath!) : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAE6F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0ECFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.memory_rounded, color: _PortraitHomePageState._brand, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本地模型',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  displayName ?? '选择或下载 Local-Diffusion 模型',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF837C8F), fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('portrait-open-model-store'),
            onPressed: storeEnabled ? onStore : null,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('下载'),
          ),
          TextButton(
            key: const Key('portrait-pick-model'),
            onPressed: onPick,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(selected ? '更换' : '选择'),
          ),
        ],
      ),
    );
  }
}

class _PhotoHero extends StatelessWidget {
  const _PhotoHero({super.key, required this.portraitPath, required this.onPick});
  final String? portraitPath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final path = portraitPath;
    return Container(
      height: 248,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0EBFF), Color(0xFFFFF2F8)],
        ),
        border: Border.all(color: const Color(0xFFE7E1F5)),
      ),
      child: path == null ? _emptyPhoto() : _selectedPhoto(path),
    );
  }

  Widget _emptyPhoto() => Stack(
        children: [
          const Positioned(
            right: -18,
            top: -24,
            child: _GlowOrb(size: 150, color: Color(0x337A5AF8)),
          ),
          const Positioned(
            left: -30,
            bottom: -48,
            child: _GlowOrb(size: 180, color: Color(0x22FF7FAE)),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 31,
                    color: _PortraitHomePageState._brand,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('先放一张你的照片',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                const Text('建议正脸、单人、光线清晰',
                    style: TextStyle(color: Color(0xFF7D758A), fontSize: 13)),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  key: const Key('portrait-pick-photo'),
                  onPressed: onPick,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('选择照片'),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _selectedPhoto(String path) => Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFFEDE8F8),
              alignment: Alignment.center,
              child: const Icon(Icons.image_outlined, size: 56),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x88000000)],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    portraitFileName(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton(
                  key: const Key('portrait-pick-photo'),
                  onPressed: onPick,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0x88FFFFFF)),
                    backgroundColor: const Color(0x33000000),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('更换'),
                ),
              ],
            ),
          ),
        ],
      );
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});
  final String title;
  final String trailing;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          Text(trailing,
              style: const TextStyle(
                  color: Color(0xFF8B8497), fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );
}

class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.style, required this.index});
  final PortraitStyle style;
  final int index;

  @override
  Widget build(BuildContext context) {
    const gradients = <List<Color>>[
      [Color(0xFFFFD7E4), Color(0xFFF7F0FF)],
      [Color(0xFFD9E5FF), Color(0xFFEDE4FF)],
      [Color(0xFFF6E2C8), Color(0xFFFFF0D9)],
      [Color(0xFFE6E7EA), Color(0xFFF9F9FA)],
      [Color(0xFFD8D3E8), Color(0xFFF0DDE7)],
      [Color(0xFFF8DDD0), Color(0xFFFFF0EB)],
      [Color(0xFFE9D9C6), Color(0xFFF5EEDF)],
      [Color(0xFFC9D0FF), Color(0xFFE8CCFF)],
    ];
    return Container(
      width: 96,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: gradients[index % gradients.length]),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(child: Icon(_styleIcon(style), size: 34, color: const Color(0xFF5D5470))),
          ),
          Text(
            style.spec.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _RatioChip extends StatelessWidget {
  const _RatioChip({required this.label, this.selected = false, this.enabled = true});
  final String label;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? _PortraitHomePageState._brand
                : enabled
                    ? Colors.white
                    : const Color(0xFFF0EEF4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? _PortraitHomePageState._brand : const Color(0xFFE5E1EB)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : enabled
                      ? const Color(0xFF3A3543)
                      : const Color(0xFFA7A1AE),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
}

IconData _styleIcon(PortraitStyle style) {
  switch (style) {
    case PortraitStyle.japaneseFresh:
      return Icons.local_florist_rounded;
    case PortraitStyle.animeIllustration:
      return Icons.auto_awesome_rounded;
    case PortraitStyle.manga:
      return Icons.draw_rounded;
    case PortraitStyle.businessPortrait:
      return Icons.business_center_rounded;
    case PortraitStyle.cinematicPortrait:
      return Icons.movie_filter_rounded;
    case PortraitStyle.editorial:
      return Icons.photo_camera_back_rounded;
    case PortraitStyle.ancientChinese:
      return Icons.landscape_rounded;
    case PortraitStyle.cyberpunk:
      return Icons.bolt_rounded;
  }
}
