import 'package:flutter/material.dart';

import '../application/portrait_generation_controller.dart';
import '../domain/portrait_style.dart';
import 'portrait_generation_page.dart';

class PortraitStylePage extends StatefulWidget {
  const PortraitStylePage({
    super.key,
    required this.controller,
    required this.portraitPath,
    required this.modelPath,
  });

  final PortraitGenerationController controller;
  final String portraitPath;
  final String modelPath;

  @override
  State<PortraitStylePage> createState() => _PortraitStylePageState();
}

class _PortraitStylePageState extends State<PortraitStylePage> {
  static const _brand = Color(0xFF6D4CF5);
  PortraitStyle? _selected;

  void _start() {
    final style = _selected;
    if (style == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PortraitGenerationPage(
          controller: widget.controller,
          portraitPath: widget.portraitPath,
          modelPath: widget.modelPath,
          style: style,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择风格', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                children: [
                  const Text(
                    '选择一种视觉方向',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '风格只改变本地生成参数，不上传照片。',
                    style: TextStyle(color: Color(0xFF827B8D), fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: .92,
                    ),
                    itemCount: PortraitStyle.values.length,
                    itemBuilder: (context, index) {
                      final style = PortraitStyle.values[index];
                      return _StyleCard(
                        key: Key('portrait-style-${style.spec.id}'),
                        style: style,
                        index: index,
                        selected: style == _selected,
                        onTap: () => setState(() => _selected = style),
                      );
                    },
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 18),
                    _SelectedSummary(style: selected),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F7FC),
                border: Border(top: BorderSide(color: Color(0xFFEDE9F3))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  key: const Key('portrait-start-generation'),
                  onPressed: selected == null ? null : _start,
                  child: Text(
                    selected == null ? '先选择一个风格' : '使用 ${selected.spec.displayName}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    super.key,
    required this.style,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final PortraitStyle style;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spec = style.spec;
    final colors = _gradients[index % _gradients.length];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? _PortraitStylePageState._brand : const Color(0xFFE7E2EE),
              width: selected ? 2.2 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x246D4CF5),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    )
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _PortraitStylePageState._brand : const Color(0x99FFFFFF),
                  ),
                  child: Icon(
                    selected ? Icons.check_rounded : Icons.add_rounded,
                    size: 17,
                    color: selected ? Colors.white : const Color(0xFF655D70),
                  ),
                ),
              ),
              Center(
                child: Icon(
                  _styleIcon(style),
                  size: 58,
                  color: const Color(0xFF51485F),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 13,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${spec.steps} steps · ${(spec.strength * 100).round()}% 风格强度',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF61596B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedSummary extends StatelessWidget {
  const _SelectedSummary({required this.style});
  final PortraitStyle style;

  @override
  Widget build(BuildContext context) {
    final spec = style.spec;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E3EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: _PortraitStylePageState._brand),
              const SizedBox(width: 8),
              Text(
                '${spec.displayName} · 生成参数',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ParamChip('${spec.width}×${spec.height}'),
              _ParamChip('${spec.steps} steps'),
              _ParamChip('CFG ${spec.cfgScale.toStringAsFixed(1)}'),
              _ParamChip('强度 ${(spec.strength * 100).round()}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParamChip extends StatelessWidget {
  const _ParamChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FA),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF655C74),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

const _gradients = <List<Color>>[
  [Color(0xFFFFD9E6), Color(0xFFF1E9FF)],
  [Color(0xFFD6E5FF), Color(0xFFE9DFFF)],
  [Color(0xFFF5E0C8), Color(0xFFFFF0D8)],
  [Color(0xFFE4E6E9), Color(0xFFF8F8F8)],
  [Color(0xFFD9D0E8), Color(0xFFF3DCE7)],
  [Color(0xFFF9DACD), Color(0xFFFFEEE8)],
  [Color(0xFFEAD7C1), Color(0xFFF4EADC)],
  [Color(0xFFC5D0FF), Color(0xFFE6C9FF)],
];

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
