import 'portrait_style.dart';

class PortraitInputException implements Exception {
  const PortraitInputException(this.message);

  final String message;

  @override
  String toString() => 'PortraitInputException: $message';
}

class PortraitModelException implements Exception {
  const PortraitModelException(this.message);

  final String message;

  @override
  String toString() => 'PortraitModelException: $message';
}

class PortraitGenerationRequest {
  const PortraitGenerationRequest({
    required this.portraitPath,
    required this.modelPath,
    required this.style,
    required this.prompt,
    required this.negativePrompt,
    required this.strength,
    required this.cfgScale,
    required this.steps,
    required this.width,
    required this.height,
  });

  factory PortraitGenerationRequest.fromStyle({
    required String portraitPath,
    required String modelPath,
    required PortraitStyle style,
  }) {
    final normalizedPortraitPath = portraitPath.trim();
    if (normalizedPortraitPath.isEmpty) {
      throw const PortraitInputException('A portrait image is required.');
    }

    final normalizedModelPath = modelPath.trim();
    if (normalizedModelPath.isEmpty) {
      throw const PortraitModelException('A local diffusion model is required.');
    }

    final spec = style.spec;
    return PortraitGenerationRequest(
      portraitPath: normalizedPortraitPath,
      modelPath: normalizedModelPath,
      style: style,
      prompt: spec.promptSuffix,
      negativePrompt: spec.negativePrompt,
      strength: spec.strength,
      cfgScale: spec.cfgScale,
      steps: spec.steps,
      width: spec.width,
      height: spec.height,
    );
  }

  final String portraitPath;
  final String modelPath;
  final PortraitStyle style;
  final String prompt;
  final String negativePrompt;
  final double strength;
  final double cfgScale;
  final int steps;
  final int width;
  final int height;
}
