import 'package:flutter/material.dart';

import 'application/portrait_generation_controller.dart';
import 'infrastructure/portrait_active_model_store.dart';
import 'infrastructure/portrait_model_downloader.dart';
import 'ui/portrait_home_page.dart';
import 'ui/portrait_input_picker.dart';

class PortraitLabApp extends StatelessWidget {
  const PortraitLabApp({
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
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7357E8),
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Portrait Lab',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F7FC),
        cardTheme: const CardTheme(elevation: 0, margin: EdgeInsets.zero),
      ),
      home: PortraitHomePage(
        controller: controller,
        photoPicker: photoPicker,
        modelPicker: modelPicker,
        modelDownloader: modelDownloader,
        activeModelStore: activeModelStore,
      ),
    );
  }
}
