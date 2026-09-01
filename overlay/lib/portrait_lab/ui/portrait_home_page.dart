import 'package:flutter/material.dart';

import '../application/portrait_generation_controller.dart';
import 'portrait_input_picker.dart';
import 'portrait_style_page.dart';

class PortraitHomePage extends StatefulWidget {
  const PortraitHomePage({
    super.key,
    required this.controller,
    required this.photoPicker,
    required this.modelPicker,
  });

  final PortraitGenerationController controller;
  final PortraitPhotoPicker photoPicker;
  final PortraitModelPicker modelPicker;

  @override
  State<PortraitHomePage> createState() => _PortraitHomePageState();
}

class _PortraitHomePageState extends State<PortraitHomePage> {
  String? _portraitPath;
  String? _modelPath;

  Future<void> _pickPortrait() async {
    final path = await widget.photoPicker.pickPortrait();
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() => _portraitPath = path);
  }

  Future<void> _pickModel() async {
    final path = await widget.modelPicker.pickModel();
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() => _modelPath = path);
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
        title: const Text('Portrait Lab'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                children: [
                  Icon(Icons.circle, size: 9, color: Colors.green),
                  SizedBox(width: 6),
                  Text('本地推理'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              '本地 AI 人像实验室',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '照片、模型和生成结果均留在设备本地。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _InputCard(
              icon: Icons.person_outline,
              title: '我的照片',
              value: _portraitPath == null
                  ? '选择一张清晰的单人照片'
                  : portraitFileName(_portraitPath!),
              buttonKey: const Key('portrait-pick-photo'),
              buttonLabel: _portraitPath == null ? '选择照片' : '更换照片',
              onPressed: _pickPortrait,
            ),
            const SizedBox(height: 14),
            _InputCard(
              icon: Icons.memory_outlined,
              title: '本地模型',
              value: _modelPath == null
                  ? '选择 Local-Diffusion 支持的模型文件'
                  : portraitFileName(_modelPath!),
              buttonKey: const Key('portrait-pick-model'),
              buttonLabel: _modelPath == null ? '选择本地模型' : '更换模型',
              onPressed: _pickModel,
            ),
            const SizedBox(height: 22),
            Text(
              '想变成什么样？',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('日系清新')),
                Chip(label: Text('二次元插画')),
                Chip(label: Text('商务')),
                Chip(label: Text('电影')),
                Chip(label: Text('古风')),
                Chip(label: Text('赛博朋克')),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              key: const Key('portrait-next-style'),
              onPressed: ready ? _openStyles : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('选择风格'),
              ),
            ),
            if (!ready) ...[
              const SizedBox(height: 10),
              const Text(
                '先选择照片和本地模型后即可继续。',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String value;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            OutlinedButton(
              key: buttonKey,
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
