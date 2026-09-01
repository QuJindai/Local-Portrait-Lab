import 'package:flutter/material.dart';

import 'application/portrait_generation_controller.dart';
import 'ui/portrait_home_page.dart';
import 'ui/portrait_input_picker.dart';

class PortraitLabApp extends StatelessWidget {
  const PortraitLabApp({
    super.key,
    required this.controller,
    required this.photoPicker,
    required this.modelPicker,
  });

  final PortraitGenerationController controller;
  final PortraitPhotoPicker photoPicker;
  final PortraitModelPicker modelPicker;

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
        cardTheme: const CardTheme(
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: PortraitHomePage(
        controller: controller,
        photoPicker: photoPicker,
        modelPicker: modelPicker,
      ),
    );
  }
}
