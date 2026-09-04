import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/application/portrait_generation_engine.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_identity.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';
import 'package:local_diffusion/portrait_lab/infrastructure/portrait_identity_lock_engine.dart';

class _StyledEngine implements PortraitGenerationEngine {
  bool cancelled = false;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    onState(const PortraitGenerationState.loadingModel());
    onState(const PortraitGenerationState.sampling(step: 1, steps: 1));
    return '/tmp/styled.png';
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

class _FakeIdentityClient implements PortraitIdentityLockClient {
  _FakeIdentityClient({this.passed = true});

  final bool passed;
  bool prepared = false;
  bool locked = false;
  bool cancelled = false;

  @override
  Future<PortraitIdentitySession> prepare({
    required String sourcePath,
    required PortraitIdentityPolicy policy,
  }) async {
    prepared = true;
    return const PortraitIdentitySession(
      token: 'r11-session',
      packVersion: 'insightface-r11-v1',
    );
  }

  @override
  Future<PortraitIdentityLockResult> lock({
    required PortraitIdentitySession session,
    required String styledPath,
    required PortraitIdentityPolicy policy,
  }) async {
    locked = true;
    return PortraitIdentityLockResult(
      outputPath: '/tmp/locked.png',
      diagnostics: PortraitIdentityDiagnostics(
        preSimilarity: 0.24,
        postSimilarity: passed ? 0.64 : 0.31,
        lockMillis: 1370,
        packVersion: session.packVersion,
        passed: passed,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

PortraitGenerationRequest _request() => PortraitGenerationRequest.fromStyle(
      portraitPath: '/photos/me.jpg',
      modelPath:
          'qnn://standalone?model_id=cyber_realistic_v10_dmd2&path=%2Fmodels%2Fcyber&type=sdxl&size=1024',
      style: PortraitStyle.manga,
    );

void main() {
  test('R11 standard identity policy is enabled and independent from style strength', () {
    const policy = PortraitIdentityPolicy.standard;

    expect(policy.enabled, isTrue);
    expect(policy.strength, closeTo(0.88, 0.0001));
    expect(policy.minSimilarity, closeTo(0.40, 0.0001));
    expect(policy.minImprovement, closeTo(0.08, 0.0001));
  });

  test('R11 style request enables identity lock without changing style preset', () {
    final request = _request();

    expect(request.identityPolicy, PortraitIdentityPolicy.standard);
    expect(request.strength, closeTo(PortraitStyle.manga.spec.strength, 0.0001));
  });

  test('R11 identity diagnostics expose pre/post similarity and real improvement', () {
    const diagnostics = PortraitIdentityDiagnostics(
      preSimilarity: 0.27,
      postSimilarity: 0.61,
      lockMillis: 1800,
      packVersion: 'insightface-r11-v1',
      passed: true,
    );

    expect(diagnostics.improvement, closeTo(0.34, 0.0001));
    expect(diagnostics.passed, isTrue);
  });

  test('R11 identity generation states carry real diagnostics', () {
    const diagnostics = PortraitIdentityDiagnostics(
      preSimilarity: 0.25,
      postSimilarity: 0.58,
      lockMillis: 1200,
      packVersion: 'insightface-r11-v1',
      passed: true,
    );

    const locking = PortraitGenerationState.lockingIdentity();
    const verifying = PortraitGenerationState.verifyingIdentity();
    const verified = PortraitGenerationState.identityVerified(diagnostics);

    expect(locking, isA<PortraitGenerationLockingIdentity>());
    expect(verifying, isA<PortraitGenerationVerifyingIdentity>());
    expect((verified as PortraitGenerationIdentityVerified).diagnostics, diagnostics);
  });

  test('R11 locks identity after style generation and returns only locked output', () async {
    final base = _StyledEngine();
    final identity = _FakeIdentityClient();
    final engine = IdentityLockedPortraitEngine(base: base, identity: identity);
    final states = <PortraitGenerationState>[];

    final output = await engine.generate(_request(), onState: states.add);

    expect(output, '/tmp/locked.png');
    expect(identity.prepared, isTrue);
    expect(identity.locked, isTrue);
    expect(states.first, isA<PortraitGenerationDetectingIdentity>());
    expect(states.whereType<PortraitGenerationSampling>(), hasLength(1));
    expect(states.whereType<PortraitGenerationLockingIdentity>(), hasLength(1));
    expect(states.whereType<PortraitGenerationVerifyingIdentity>(), hasLength(1));
    expect(states.whereType<PortraitGenerationIdentityVerified>(), hasLength(1));
  });

  test('R11 rejects identity QA failure instead of returning styled image', () async {
    final engine = IdentityLockedPortraitEngine(
      base: _StyledEngine(),
      identity: _FakeIdentityClient(passed: false),
    );
    final states = <PortraitGenerationState>[];

    await expectLater(
      engine.generate(_request(), onState: states.add),
      throwsA(isA<PortraitIdentityLockException>()),
    );
    expect(states.whereType<PortraitGenerationIdentityLockFailed>(), hasLength(1));
  });

  test('R11 cancel propagates to style and identity runtimes', () async {
    final base = _StyledEngine();
    final identity = _FakeIdentityClient();
    final engine = IdentityLockedPortraitEngine(base: base, identity: identity);

    await engine.cancel();

    expect(base.cancelled, isTrue);
    expect(identity.cancelled, isTrue);
  });
}
