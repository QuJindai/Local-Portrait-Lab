sealed class PortraitGenerationState {
  const PortraitGenerationState();

  const factory PortraitGenerationState.preparing() =
      PortraitGenerationPreparing;
  const factory PortraitGenerationState.loadingModel() =
      PortraitGenerationLoadingModel;
  const factory PortraitGenerationState.sampling({
    required int step,
    required int steps,
  }) = PortraitGenerationSampling;
  const factory PortraitGenerationState.completed(String outputPath) =
      PortraitGenerationCompleted;
  const factory PortraitGenerationState.cancelled() =
      PortraitGenerationCancelled;
}

final class PortraitGenerationPreparing extends PortraitGenerationState {
  const PortraitGenerationPreparing();

  @override
  bool operator ==(Object other) => other is PortraitGenerationPreparing;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class PortraitGenerationLoadingModel extends PortraitGenerationState {
  const PortraitGenerationLoadingModel();

  @override
  bool operator ==(Object other) => other is PortraitGenerationLoadingModel;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class PortraitGenerationSampling extends PortraitGenerationState {
  const PortraitGenerationSampling({required this.step, required this.steps})
      : assert(step >= 0),
        assert(steps > 0),
        assert(step <= steps);

  final int step;
  final int steps;

  @override
  bool operator ==(Object other) =>
      other is PortraitGenerationSampling &&
      other.step == step &&
      other.steps == steps;

  @override
  int get hashCode => Object.hash(runtimeType, step, steps);
}

final class PortraitGenerationCompleted extends PortraitGenerationState {
  const PortraitGenerationCompleted(this.outputPath);

  final String outputPath;

  @override
  bool operator ==(Object other) =>
      other is PortraitGenerationCompleted && other.outputPath == outputPath;

  @override
  int get hashCode => Object.hash(runtimeType, outputPath);
}

final class PortraitGenerationCancelled extends PortraitGenerationState {
  const PortraitGenerationCancelled();

  @override
  bool operator ==(Object other) => other is PortraitGenerationCancelled;

  @override
  int get hashCode => runtimeType.hashCode;
}
