import 'package:flutter_test/flutter_test.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_request.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_generation_state.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_identity.dart';
import 'package:local_diffusion/portrait_lab/domain/portrait_style.dart';

void main() {
  test('R11 standard identity policy is enabled and independent from style strength', () {
    const policy = PortraitIdentityPolicy.standard;

    expect(policy.enabled, isTrue);
    expect(policy.strength, closeTo(0.88, 0.0001));
    expect(policy.minSimilarity, closeTo(0.40, 0.0001));
    expect(policy.minImprovement, closeTo(0.08, 0.0001));
  });

  test('R11 style request enables identity lock without changing style preset', () {
    final request = PortraitGenerationRequest.fromStyle(
      portraitPath: '/photos/me.jpg',
      modelPath:
          'qnn://standalone?model_id=cyber_realistic_v10_dmd2&path=%2Fmodels%2Fcyber&type=sdxl&size=1024',
      style: PortraitStyle.manga,
    );

    expect(request.identityPolicy, const PortraitIdentityPolicy.standard);
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
}
