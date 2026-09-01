import '../domain/portrait_generation_request.dart';

class LocalDiffusionRuntimeProfile {
  const LocalDiffusionRuntimeProfile({
    required this.sampleMethodIndex,
    required this.sampleSteps,
    required this.cfgScale,
    required this.isFastPath,
    required this.label,
  });

  factory LocalDiffusionRuntimeProfile.forRequest(
    PortraitGenerationRequest request,
  ) {
    final model = request.modelPath.toLowerCase();
    final isLcm = model.contains('lcm');
    if (isLcm) {
      return const LocalDiffusionRuntimeProfile(
        sampleMethodIndex: 9,
        sampleSteps: 6,
        cfgScale: 1.0,
        isFastPath: true,
        label: 'LCM · 6 steps · CFG 1.0',
      );
    }
    return LocalDiffusionRuntimeProfile(
      sampleMethodIndex: 0,
      sampleSteps: request.steps,
      cfgScale: request.cfgScale,
      isFastPath: false,
      label: 'Standard · Euler A · ${request.steps} steps',
    );
  }

  final int sampleMethodIndex;
  final int sampleSteps;
  final double cfgScale;
  final bool isFastPath;
  final String label;
}
