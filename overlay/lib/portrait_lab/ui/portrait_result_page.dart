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
      appBar: AppBar(title: const Text('生成结果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: exists
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_outlined, size: 72),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              portraitFileName(outputPath),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 6),
                Text('已保存到本地作品 · ${style.spec.displayName}'),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 13),
                      child: Text('换一种风格'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
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
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 13),
                      child: Text('重新生成'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
