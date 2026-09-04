import 'portrait_identity.dart';

sealed class PortraitGenerationState {
  const PortraitGenerationState();

  const factory PortraitGenerationState.preparing() =
      PortraitGenerationPreparing;
  const factory PortraitGenerationState.detectingIdentity() =
      PortraitGenerationDetectingIdentity;
  const factory PortraitGenerationState.extractingIdentity() =
      PortraitGenerationExtractingIdentity;
  const factory PortraitGenerationState.loadingModel() =
      PortraitGenerationLoadingModel;
  const factory PortraitGenerationState.sampling({
    required int step,
    required int steps,
  }) = PortraitGenerationSampling;
  const factory PortraitGenerationState.lockingIdentity() =
      PortraitGenerationLockingIdentity;
  const factory PortraitGenerationState.verifyingIdentity() =
      PortraitGenerationVerifyingIdentity;
  const factory PortraitGenerationState.identityVerified(
    PortraitIdentityDiagnostics diagnostics,
  ) = PortraitGenerationIdentityVerified;
  const factory PortraitGenerationState.identityLockFailed(String message) =
      PortraitGenerationIdentityLockFailed;
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

final class PortraitGenerationDetectingIdentity extends PortraitGenerationState {
  const PortraitGenerationDetectingIdentity();

  @override
  bool operator ==(Object other) => other is PortraitGenerationDetectingIdentity;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class PortraitGenerationExtractingIdentity extends PortraitGenerationState {
  const PortraitGenerationExtractingIdentity();

  @override
  bool operator ==(Object other) => other is PortraitGenerationExtractingIdentity;

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

final class PortraitGenerationLockingIdentity extends PortraitGenerationState {
  const PortraitGenerationLockingIdentity();

  @override
  bool operator ==(Object other) => other is PortraitGenerationLockingIdentity;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class PortraitGenerationVerifyingIdentity extends PortraitGenerationState {
  const PortraitGenerationVerifyingIdentity();

  @override
  bool operator ==(Object other) => other is PortraitGenerationVerifyingIdentity;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class PortraitGenerationIdentityVerified extends PortraitGenerationState {
  const PortraitGenerationIdentityVerified(this.diagnostics);

  final PortraitIdentityDiagnostics diagnostics;

  @override
  bool operator ==(Object other) =>
      other is PortraitGenerationIdentityVerified &&
      other.diagnostics == diagnostics;

  @override
  int get hashCode => Object.hash(runtimeType, diagnostics);
}

final class PortraitGenerationIdentityLockFailed extends PortraitGenerationState {
  const PortraitGenerationIdentityLockFailed(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is PortraitGenerationIdentityLockFailed && other.message == message;

  @override
  int get hashCode => Object.hash(runtimeType, message);
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
