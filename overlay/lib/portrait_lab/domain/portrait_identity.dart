class PortraitIdentityPolicy {
  const PortraitIdentityPolicy({
    required this.enabled,
    required this.strength,
    required this.minSimilarity,
    required this.minImprovement,
  })  : assert(strength >= 0 && strength <= 1),
        assert(minSimilarity >= -1 && minSimilarity <= 1),
        assert(minImprovement >= 0 && minImprovement <= 2);

  static const standard = PortraitIdentityPolicy(
    enabled: true,
    strength: 0.88,
    minSimilarity: 0.40,
    minImprovement: 0.08,
  );

  static const disabled = PortraitIdentityPolicy(
    enabled: false,
    strength: 0,
    minSimilarity: 0.40,
    minImprovement: 0.08,
  );

  final bool enabled;
  final double strength;
  final double minSimilarity;
  final double minImprovement;

  Map<String, Object?> toMap() => <String, Object?>{
        'enabled': enabled,
        'strength': strength,
        'minSimilarity': minSimilarity,
        'minImprovement': minImprovement,
      };

  @override
  bool operator ==(Object other) =>
      other is PortraitIdentityPolicy &&
      other.enabled == enabled &&
      other.strength == strength &&
      other.minSimilarity == minSimilarity &&
      other.minImprovement == minImprovement;

  @override
  int get hashCode => Object.hash(
        enabled,
        strength,
        minSimilarity,
        minImprovement,
      );
}

class PortraitIdentityDiagnostics {
  const PortraitIdentityDiagnostics({
    required this.preSimilarity,
    required this.postSimilarity,
    required this.lockMillis,
    required this.packVersion,
    required this.passed,
  });

  factory PortraitIdentityDiagnostics.fromMap(Map<Object?, Object?> map) {
    double readDouble(String key) {
      final value = map[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int readInt(String key) {
      final value = map[key];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return PortraitIdentityDiagnostics(
      preSimilarity: readDouble('preSimilarity'),
      postSimilarity: readDouble('postSimilarity'),
      lockMillis: readInt('lockMillis'),
      packVersion: map['packVersion']?.toString() ?? 'unknown',
      passed: map['passed'] == true,
    );
  }

  final double preSimilarity;
  final double postSimilarity;
  final int lockMillis;
  final String packVersion;
  final bool passed;

  double get improvement => postSimilarity - preSimilarity;

  @override
  bool operator ==(Object other) =>
      other is PortraitIdentityDiagnostics &&
      other.preSimilarity == preSimilarity &&
      other.postSimilarity == postSimilarity &&
      other.lockMillis == lockMillis &&
      other.packVersion == packVersion &&
      other.passed == passed;

  @override
  int get hashCode => Object.hash(
        preSimilarity,
        postSimilarity,
        lockMillis,
        packVersion,
        passed,
      );
}
