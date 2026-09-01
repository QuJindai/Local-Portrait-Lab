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
    const brand = Color(0xFF6D4CF5);
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
      surface: const Color(0xFFF8F7FC),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Portrait Lab',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F7FC),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF8F7FC),
          foregroundColor: Color(0xFF17151F),
          surfaceTintColor: Colors.transparent,
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: const Color(0xFF17151F),
              displayColor: const Color(0xFF17151F),
            ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF3B3548),
            side: const BorderSide(color: Color(0xFFE2DEEC)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFEEEAF5)),
          ),
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
