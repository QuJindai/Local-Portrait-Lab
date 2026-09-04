import 'dart:async';

import 'package:flutter/material.dart';

import '../application/portrait_generation_controller.dart';
import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';
import '../domain/portrait_identity.dart';
import '../domain/portrait_style.dart';
import '../infrastructure/local_diffusion_runtime_profile.dart';
import '../infrastructure/portrait_compute_backend.dart';
import 'portrait_result_page.dart';

class PortraitGenerationPage extends StatefulWidget {
  const PortraitGenerationPage({
    super.key,
    required this.controller,
    required this.portraitPath,
    required this.modelPath,
    required this.style,
  });

  final PortraitGenerationController controller;
  final String portraitPath;
  final String modelPath;
  final PortraitStyle style;

  @override
  State<PortraitGenerationPage> createState() => _PortraitGenerationPageState();
}

class _PortraitGenerationPageState extends State<PortraitGenerationPage> {
  static const _brand = Color(0xFF6D4CF5);
  StreamSubscription<PortraitGenerationState>? _subscription;
  int _step = 0;
  int _steps = 0;
  String _stage = '准备图片';
  String? _error;
  PortraitIdentityDiagnostics? _identityDiagnostics;
  bool _cancelled = false;
  bool _started = false;
  late final Stopwatch _stopwatch;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _subscription = widget.controller.states.listen(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started || !mounted) return;
    _started = true;
    try {
      final outputPath = await widget.controller.generate(
        portraitPath: widget.portraitPath,
        modelPath: widget.modelPath,
        style: widget.style,
      );
      if (!mounted) return;
      _stopwatch.stop();
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PortraitResultPage(
            controller: widget.controller,
            portraitPath: widget.portraitPath,
            modelPath: widget.modelPath,
            style: widget.style,
            outputPath: outputPath,
          ),
        ),
      );
    } on PortraitGenerationCancelledException {
      _stopwatch.stop();
      if (mounted) {
        setState(() {
          _cancelled = true;
          _stage = '已取消';
        });
      }
    } catch (error) {
      _stopwatch.stop();
      if (mounted) {
        setState(() {
          _error = error.toString();
          _stage = '生成失败';
        });
      }
    }
  }

  void _onState(PortraitGenerationState state) {
    if (!mounted) return;
    setState(() {
      switch (state) {
        case PortraitGenerationPreparing():
          _stage = '准备图片';
        case PortraitGenerationDetectingIdentity():
          _stage = '检测身份';
        case PortraitGenerationExtractingIdentity():
          _stage = '提取身份';
        case PortraitGenerationLoadingModel():
          _stage = '加载本地模型';
        case PortraitGenerationSampling(:final step, :final steps):
          _step = step;
          _steps = steps;
          _stage = 'QNN 风格生成';
        case PortraitGenerationLockingIdentity():
          _stage = '锁定人物身份';
        case PortraitGenerationVerifyingIdentity():
          _stage = '验证身份';
        case PortraitGenerationIdentityVerified(:final diagnostics):
          _identityDiagnostics = diagnostics;
          _stage = '身份验证通过';
        case PortraitGenerationIdentityLockFailed(:final message):
          _error = message;
          _stage = '身份验证失败';
        case PortraitGenerationCompleted():
          _stage = '完成';
        case PortraitGenerationCancelled():
          _cancelled = true;
          _stage = '已取消';
      }
    });
  }

  Future<void> _cancel() async {
    await widget.controller.cancel();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = PortraitGenerationRequest.fromStyle(
      portraitPath: widget.portraitPath,
      modelPath: widget.modelPath,
      style: widget.style,
    );
    final runtimeProfile = LocalDiffusionRuntimeProfile.forRequest(request);
    final computeBackend = PortraitComputeBackendRegistry.current;
    final modelScheme = Uri.tryParse(widget.modelPath)?.scheme;
    final usingDream = modelScheme == 'dream';
    final usingStandaloneQnn = modelScheme == 'qnn';
    final usingQnn = usingDream || usingStandaloneQnn;
    final hasSamplingProgress = _steps > 0;
    final progress = hasSamplingProgress ? (_step / _steps).clamp(0.0, 1.0) : null;
    final percent = progress == null ? null : (progress * 100).round();
    final currentStage = _stageIndex();
    final elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;

    final backendTitle = usingStandaloneQnn
        ? '本机 QNN NPU 生成'
        : usingDream
            ? 'DREAM Host NPU 生成'
            : computeBackend.isGpuAccelerated
                ? 'GPU 本地生成'
                : '本地生成 · CPU 回退';
    final diagnosticLabel = usingStandaloneQnn
        ? 'NPU · QNN/HTP · R11 Identity Lock'
        : usingDream
            ? 'NPU · QNN/HTP · DREAM Host · R11 Identity Lock'
            : '${computeBackend.displayLabel} · R11 Identity Lock';
    final diagnosticDetail = usingStandaloneQnn
        ? 'QNN 127.0.0.1:8082 · SCRFD → ArcFace → INSwapper · ${elapsedSeconds.toStringAsFixed(1)}s'
        : usingDream
            ? 'DREAM 127.0.0.1:8081 · SCRFD → ArcFace → INSwapper · ${elapsedSeconds.toStringAsFixed(1)}s'
            : '${computeBackend.detailLabel} · ${runtimeProfile.label} · SCRFD → ArcFace → INSwapper · ${elapsedSeconds.toStringAsFixed(1)}s';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          backendTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 26),
          children: [
            Container(
              height: 190,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE9E1FF), Color(0xFFFFE6F0)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 18,
                    top: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xCCFFFFFF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        widget.style.spec.displayName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x236D4CF5),
                            blurRadius: 28,
                            offset: Offset(0, 10),
                          )
                        ],
                      ),
                      child: Icon(
                        _cancelled
                            ? Icons.stop_rounded
                            : _stage.contains('身份')
                                ? Icons.face_retouching_natural_rounded
                                : usingQnn
                                    ? Icons.bolt_rounded
                                    : Icons.auto_awesome_rounded,
                        size: 39,
                        color: _brand,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _cancelled ? '生成已取消' : '正在本地生成',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '全部计算在当前设备完成 · $_stage',
              style: const TextStyle(color: Color(0xFF817A8D), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              key: const Key('portrait-runtime-diagnostics'),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: usingQnn
                    ? const Color(0xFFEDE8FF)
                    : computeBackend.isGpuAccelerated
                        ? const Color(0xFFE8F2FF)
                        : runtimeProfile.isFastPath
                            ? const Color(0xFFEDE8FF)
                            : const Color(0xFFF3F1F6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _stage.contains('身份')
                        ? Icons.verified_user_rounded
                        : usingQnn
                            ? Icons.bolt_rounded
                            : computeBackend.isGpuAccelerated
                                ? Icons.memory_rounded
                                : Icons.speed_rounded,
                    color: _brand,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diagnosticLabel,
                          key: const Key('portrait-active-backend-label'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          diagnosticDetail,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF766F81)),
                        ),
                        if (_identityDiagnostics case final d?) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Identity PASS · ${d.preSimilarity.toStringAsFixed(3)} → ${d.postSimilarity.toStringAsFixed(3)} · Δ${d.improvement.toStringAsFixed(3)} · ${d.lockMillis}ms',
                            key: const Key('portrait-identity-diagnostics'),
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFEAE6F0)),
              ),
              child: Column(
                children: [
                  _StageRow(
                    title: '分析身份特征',
                    subtitle: 'SCRFD 检测 · ArcFace 512D 身份向量',
                    state: _stageState(0, currentStage),
                  ),
                  const _StageConnector(),
                  _StageRow(
                    title: 'QNN 风格生成',
                    subtitle: usingStandaloneQnn
                        ? '本机 QNN/HTP · 风格与身份分离控制'
                        : usingDream
                            ? 'DREAM Host QNN/HTP · 风格生成'
                            : '本地扩散模型 · 风格生成',
                    state: _stageState(1, currentStage),
                  ),
                  const _StageConnector(),
                  _StageRow(
                    title: '锁定人物身份',
                    subtitle: 'INSwapper 仅校正脸部 ROI，不重绘身体与风格',
                    state: _stageState(2, currentStage),
                  ),
                  const _StageConnector(),
                  _StageRow(
                    title: '验证身份',
                    subtitle: _identityDiagnostics == null
                        ? 'ArcFace cosine 硬门禁'
                        : '${_identityDiagnostics!.preSimilarity.toStringAsFixed(3)} → ${_identityDiagnostics!.postSimilarity.toStringAsFixed(3)}',
                    state: _stageState(3, currentStage),
                  ),
                  const _StageConnector(),
                  _StageRow(
                    title: '保存本地作品',
                    subtitle: '只有身份门禁通过才允许完成',
                    state: _stageState(4, currentStage),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: progress,
                backgroundColor: const Color(0xFFE9E5EF),
              ),
            ),
            const SizedBox(height: 10),
            if (hasSamplingProgress && _stage == 'QNN 风格生成')
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$_step / $_steps', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('$percent%', style: const TextStyle(color: _brand, fontWeight: FontWeight.w900)),
                ],
              )
            else
              Text(
                _stage.contains('身份') ? '执行真实身份流水线…' : '等待模型真实进度回调…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8B8497), fontSize: 12),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 22),
            OutlinedButton.icon(
              key: const Key('portrait-cancel-generation'),
              onPressed: _cancelled ? null : _cancel,
              icon: const Icon(Icons.close_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text('取消生成', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              usingStandaloneQnn
                  ? 'R11：QNN/HTP 只负责全图风格生成；SCRFD → ArcFace → INSwapper 独立负责身份锁定，均在本机执行。'
                  : usingDream
                      ? 'DREAM Host 仍是可选兼容路径；身份锁定在当前设备独立完成。'
                      : 'R11 fallback 同样进入独立身份门禁；照片与身份向量不上传。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF96909F), fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  int _stageIndex() {
    if (_stage == '准备图片' || _stage == '检测身份' || _stage == '提取身份') return 0;
    if (_stage == '加载本地模型' || _stage == 'QNN 风格生成') return 1;
    if (_stage == '锁定人物身份') return 2;
    if (_stage == '验证身份' || _stage == '身份验证通过' || _stage == '身份验证失败') return 3;
    if (_stage == '完成') return 4;
    if (_cancelled || _error != null) return 3;
    return 0;
  }

  _StageStatus _stageState(int index, int current) {
    if (index < current) return _StageStatus.done;
    if (index == current) return _StageStatus.active;
    return _StageStatus.pending;
  }
}

enum _StageStatus { done, active, pending }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.title, required this.subtitle, required this.state});
  final String title;
  final String subtitle;
  final _StageStatus state;

  @override
  Widget build(BuildContext context) {
    final active = state == _StageStatus.active;
    final done = state == _StageStatus.done;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active || done ? _PortraitGenerationPageState._brand : const Color(0xFFEDE9F3),
          ),
          child: Icon(
            done ? Icons.check_rounded : active ? Icons.more_horiz_rounded : Icons.circle_outlined,
            color: active || done ? Colors.white : const Color(0xFFAAA4B2),
            size: 17,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: state == _StageStatus.pending ? const Color(0xFF9D97A6) : const Color(0xFF24202A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF8D8698), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StageConnector extends StatelessWidget {
  const _StageConnector();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 14),
      child: SizedBox(
        height: 20,
        child: VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE1DDE8)),
      ),
    );
  }
}
