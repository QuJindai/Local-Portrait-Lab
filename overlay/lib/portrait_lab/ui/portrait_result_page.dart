import 'dart:io';

import 'package:flutter/material.dart';

import '../application/portrait_generation_controller.dart';
import '../domain/portrait_style.dart';
import 'portrait_generation_page.dart';
import 'portrait_input_picker.dart';

class PortraitResultPage extends StatelessWidget {
  const PortraitResultPage({
    super.key,
    required this.controller,
    required this.portraitPath,
    required this.modelPath,
    required this.style,
    required this.outputPath,
  });

  final PortraitGenerationController controller;
  final String portraitPath;
  final String modelPath;
  final PortraitStyle style;
  final String outputPath;

  @override
  Widget build(BuildContext context) {
    final file = File(outputPath);
    final exists = file.existsSync();
    return Scaffold(
      appBar: AppBar(
        title: const Text('生成结果', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 26),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  )
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: exists
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFE8E1FF), Color(0xFFFFE4EE)],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_outlined, size: 72, color: Color(0xFF6D4CF5)),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    portraitFileName(outputPath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0ECFF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    style.spec.displayName,
                    style: const TextStyle(
                      color: Color(0xFF5A48B2),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF53B76A), size: 18),
                SizedBox(width: 6),
                Text(
                  '已保存到本地作品',
                  style: TextStyle(color: Color(0xFF6E6778), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: Icons.download_done_rounded,
                    label: '已保存',
                    subtitle: '设备本地',
                    onTap: null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.auto_fix_high_rounded,
                    label: '换一风格',
                    subtitle: '保留原照片',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.refresh_rounded,
                    label: '再生成',
                    subtitle: '同一风格',
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => PortraitGenerationPage(
                            controller: controller,
                            portraitPath: portraitPath,
                            modelPath: modelPath,
                            style: style,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => PortraitGenerationPage(
                        controller: controller,
                        portraitPath: portraitPath,
                        modelPath: modelPath,
                        style: style,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text(
                  '再生成一张',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text('换一种风格', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEAE6F0)),
          ),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF6D4CF5)),
              const SizedBox(height: 7),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF918A9A), fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
