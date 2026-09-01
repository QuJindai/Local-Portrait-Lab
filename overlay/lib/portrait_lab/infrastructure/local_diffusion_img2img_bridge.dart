class LocalDiffusionImg2ImgCommand {
  const LocalDiffusionImg2ImgCommand({
    required this.portraitPath,
    required this.modelPath,
    required this.prompt,
    required this.negativePrompt,
    required this.cfgScale,
    required this.sampleSteps,
    required this.strength,
    required this.outputWidth,
    required this.outputHeight,
    required this.seed,
    required this.sampleMethodIndex,
  });

  final String portraitPath;
  final String modelPath;
  final String prompt;
  final String negativePrompt;
  final double cfgScale;
  final int sampleSteps;
  final double strength;
  final int outputWidth;
  final int outputHeight;
  final int seed;
  final int sampleMethodIndex;
}

abstract interface class LocalDiffusionImg2ImgBridge {
  Future<String> generate(
    LocalDiffusionImg2ImgCommand command, {
    required void Function(int step, int steps, double elapsedSeconds)
        onProgress,
  });

  Future<void> cancel();
}
