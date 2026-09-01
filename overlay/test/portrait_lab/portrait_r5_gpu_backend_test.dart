import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_compute_backend.dart';

class _FakeBindings implements PortraitComputeBackendBindings {
  _FakeBindings({required this.actualBackend});

  final String actualBackend;
  final List<String> requested = <String>[];

  @override
  void initialize(String backend) {
    requested.add(backend);
  }

  @override
  String get currentBackend => actualBackend;
}

void main() {
  test('R5 requests Vulkan first and reports GPU when Vulkan loads', () {
    final bindings = _FakeBindings(actualBackend: 'Vulkan');
    final state = PortraitComputeBackendSelector(bindings).activateFastPath();

    expect(bindings.requested, <String>['Vulkan']);
    expect(state.actualBackend, 'Vulkan');
    expect(state.isGpuAccelerated, isTrue);
    expect(state.displayLabel, contains('GPU'));
  });

  test('R5 reports CPU fallback when Vulkan loader falls back internally', () {
    final bindings = _FakeBindings(actualBackend: 'CPU');
    final state = PortraitComputeBackendSelector(bindings).activateFastPath();

    expect(bindings.requested, <String>['Vulkan']);
    expect(state.actualBackend, 'CPU');
    expect(state.isGpuAccelerated, isFalse);
    expect(state.displayLabel, contains('CPU'));
  });
}
