import 'dart:io';

import 'package:flutter/services.dart';

import '../application/portrait_generation_engine.dart';
import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';
import '../domain/portrait_identity.dart';

class PortraitIdentityLockException implements Exception {
  const PortraitIdentityLockException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PortraitIdentitySession {
  const PortraitIdentitySession({required this.token, required this.packVersion});
  final String token;
  final String packVersion;
}

class PortraitIdentityLockResult {
  const PortraitIdentityLockResult({
    required this.outputPath,
    required this.diagnostics,
  });

  final String outputPath;
  final PortraitIdentityDiagnostics diagnostics;
}

abstract interface class PortraitIdentityLockClient {
  Future<PortraitIdentitySession> prepare({
    required String sourcePath,
    required PortraitIdentityPolicy policy,
  });

  Future<PortraitIdentityLockResult> lock({
    required PortraitIdentitySession session,
    required String styledPath,
    required PortraitIdentityPolicy policy,
  });

  Future<void> cancel();
}

class AndroidPortraitIdentityLockClient implements PortraitIdentityLockClient {
  AndroidPortraitIdentityLockClient({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel(
    'com.qujindai.localportraitlab/identity_lock',
  );

  final MethodChannel _channel;

  @override
  Future<PortraitIdentitySession> prepare({
    required String sourcePath,
    required PortraitIdentityPolicy policy,
  }) async {
    if (!Platform.isAndroid) {
      throw const PortraitIdentityLockException(
        'R11 identity lock currently requires Android.',
      );
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'prepare',
      <String, Object?>{
        'sourcePath': sourcePath,
        ...policy.toMap(),
      },
    );
    final token = raw?['token']?.toString() ?? '';
    final packVersion = raw?['packVersion']?.toString() ?? 'unknown';
    if (token.isEmpty) {
      throw const PortraitIdentityLockException('本机身份分析未返回有效会话。');
    }
    return PortraitIdentitySession(token: token, packVersion: packVersion);
  }

  @override
  Future<PortraitIdentityLockResult> lock({
    required PortraitIdentitySession session,
    required String styledPath,
    required PortraitIdentityPolicy policy,
  }) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'lock',
      <String, Object?>{
        'token': session.token,
        'styledPath': styledPath,
        ...policy.toMap(),
      },
    );
    if (raw == null) {
      throw const PortraitIdentityLockException('本机身份锁定未返回结果。');
    }
    final outputPath = raw['outputPath']?.toString() ?? '';
    if (outputPath.isEmpty) {
      throw const PortraitIdentityLockException('本机身份锁定输出路径为空。');
    }
    return PortraitIdentityLockResult(
      outputPath: outputPath,
      diagnostics: PortraitIdentityDiagnostics.fromMap(raw),
    );
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}

class IdentityLockedPortraitEngine implements PortraitGenerationEngine {
  IdentityLockedPortraitEngine({
    required PortraitGenerationEngine base,
    required PortraitIdentityLockClient identity,
  })  : _base = base,
        _identity = identity;

  final PortraitGenerationEngine _base;
  final PortraitIdentityLockClient _identity;

  @override
  Future<String> generate(
    PortraitGenerationRequest request, {
    required void Function(PortraitGenerationState state) onState,
  }) async {
    if (!request.identityPolicy.enabled) {
      return _base.generate(request, onState: onState);
    }

    onState(const PortraitGenerationState.detectingIdentity());
    final session = await _identity.prepare(
      sourcePath: request.portraitPath,
      policy: request.identityPolicy,
    );
    onState(const PortraitGenerationState.extractingIdentity());

    final styledPath = await _base.generate(request, onState: onState);
    try {
      onState(const PortraitGenerationState.lockingIdentity());
      final result = await _identity.lock(
        session: session,
        styledPath: styledPath,
        policy: request.identityPolicy,
      );
      onState(const PortraitGenerationState.verifyingIdentity());
      final diagnostics = result.diagnostics;
      if (!diagnostics.passed) {
        final message =
            '身份锁定未通过：${diagnostics.preSimilarity.toStringAsFixed(3)} → ${diagnostics.postSimilarity.toStringAsFixed(3)}';
        onState(PortraitGenerationState.identityLockFailed(message));
        throw PortraitIdentityLockException(message);
      }
      onState(PortraitGenerationState.identityVerified(diagnostics));
      return result.outputPath;
    } on PortraitIdentityLockException {
      _deleteUnapproved(styledPath);
      rethrow;
    } catch (error) {
      _deleteUnapproved(styledPath);
      final message = '本机身份锁定失败：$error';
      onState(PortraitGenerationState.identityLockFailed(message));
      throw PortraitIdentityLockException(message);
    }
  }

  static void _deleteUnapproved(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup. Never turn an identity failure into success.
    }
  }

  @override
  Future<void> cancel() async {
    await Future.wait<void>(<Future<void>>[
      _base.cancel(),
      _identity.cancel(),
    ]);
  }
}
