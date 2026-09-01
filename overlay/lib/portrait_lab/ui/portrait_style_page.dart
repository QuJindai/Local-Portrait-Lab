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
    return Scaffold(
      appBar: AppBar(title: const Text('选择风格')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(18),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.15,
                ),
                itemCount: PortraitStyle.values.length,
                itemBuilder: (context, index) {
                  final style = PortraitStyle.values[index];
                  final spec = style.spec;
                  final selected = style == _selected;
                  return InkWell(
                    key: Key('portrait-style-${spec.id}'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _selected = style),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                        color: selected
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.45)
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_styleIcon(style), size: 28),
                          const Spacer(),
                          Text(
                            spec.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${spec.width}×${spec.height} · ${spec.steps} steps',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('portrait-start-generation'),
                  onPressed: _selected == null ? null : _start,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('使用此风格'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _styleIcon(PortraitStyle style) {
    switch (style) {
      case PortraitStyle.japaneseFresh:
        return Icons.local_florist_outlined;
      case PortraitStyle.animeIllustration:
        return Icons.auto_awesome_outlined;
      case PortraitStyle.manga:
        return Icons.draw_outlined;
      case PortraitStyle.businessPortrait:
        return Icons.business_center_outlined;
      case PortraitStyle.cinematicPortrait:
        return Icons.movie_filter_outlined;
      case PortraitStyle.editorial:
        return Icons.photo_camera_back_outlined;
      case PortraitStyle.ancientChinese:
        return Icons.landscape_outlined;
      case PortraitStyle.cyberpunk:
        return Icons.bolt_outlined;
    }
  }
}
