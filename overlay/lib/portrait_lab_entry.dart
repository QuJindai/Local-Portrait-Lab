import 'package:flutter/material.dart';

import 'portrait_lab/infrastructure/portrait_compute_backend.dart';
import 'portrait_lab/portrait_lab_app.dart';
import 'portrait_lab/portrait_runtime.dart';
import 'portrait_lab/ui/portrait_input_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final backend = PortraitComputeBackendSelector(
    const FfiPortraitComputeBackendBindings(),
  ).activateFastPath();
  PortraitComputeBackendRegistry.install(backend);

  runApp(
    PortraitLabApp(
      controller: PortraitRuntime.createController(),
      photoPicker: SystemPortraitPhotoPicker(),
      modelPicker: SystemPortraitModelPicker(),
      modelDownloader: PortraitRuntime.createModelDownloader(),
      activeModelStore: PortraitRuntime.createActiveModelStore(),
    ),
  );
}
