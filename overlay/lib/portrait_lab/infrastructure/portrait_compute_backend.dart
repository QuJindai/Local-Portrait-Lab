import '../../ffi_bindings.dart';

abstract interface class PortraitComputeBackendBindings {
  void initialize(String backend);
  String get currentBackend;
}

class FfiPortraitComputeBackendBindings implements PortraitComputeBackendBindings {
  const FfiPortraitComputeBackendBindings();

  @override
  void initialize(String backend) => FFIBindings.initializeBindings(backend);

  @override
  String get currentBackend => FFIBindings.getCurrentBackend();
}

class PortraitComputeBackendState {
  const PortraitComputeBackendState({
    required this.requestedBackend,
    required this.actualBackend,
  });

  final String requestedBackend;
  final String actualBackend;

  bool get isGpuAccelerated => actualBackend.toLowerCase() == 'vulkan';

  String get displayLabel =>
      isGpuAccelerated ? 'GPU · Vulkan' : 'CPU · fallback';

  String get detailLabel => isGpuAccelerated
      ? 'Adreno/Vulkan FastPath'
      : 'Vulkan unavailable · CPU fallback';
}

class PortraitComputeBackendSelector {
  const PortraitComputeBackendSelector(this._bindings);

  final PortraitComputeBackendBindings _bindings;

  PortraitComputeBackendState activateFastPath() {
    const requested = 'Vulkan';
    _bindings.initialize(requested);
    return PortraitComputeBackendState(
      requestedBackend: requested,
      actualBackend: _bindings.currentBackend,
    );
  }
}

class PortraitComputeBackendRegistry {
  const PortraitComputeBackendRegistry._();

  static PortraitComputeBackendState current = const PortraitComputeBackendState(
    requestedBackend: 'CPU',
    actualBackend: 'CPU',
  );

  static void install(PortraitComputeBackendState state) {
    current = state;
  }
}
