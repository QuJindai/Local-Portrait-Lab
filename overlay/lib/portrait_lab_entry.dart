import 'package:flutter/material.dart';

import 'ffi_bindings.dart';
import 'portrait_lab/portrait_lab_app.dart';
import 'portrait_lab/portrait_runtime.dart';
import 'portrait_lab/ui/portrait_input_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FFIBindings.initializeBindings('CPU');

  final controller = PortraitRuntime.createController();
  runApp(
    PortraitLabApp(
      controller: controller,
      photoPicker: SystemPortraitPhotoPicker(),
      modelPicker: SystemPortraitModelPicker(),
    ),
  );
}
