import 'dart:async';

import 'package:flutter/material.dart';

import '../application/portrait_generation_controller.dart';
import '../domain/portrait_generation_request.dart';
import '../domain/portrait_generation_state.dart';
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
        case PortraitGenerationLoadingModel():
          _stage = '加载本地模型';
        case PortraitGenerationSampling(:final step, :final steps):
          _step = step;
          _steps = steps;
          _stage = '扩散采样';
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
    final hasSamplingProgress = _steps > 0;
    final progress = hasSamplingProgress ? (_step / _steps).clamp(0.0, 1.0) : null;
    final percent = progress == null ? null : (progress * 100).round();
    final currentStage = _stageIndex();
    final elapsedSeconds = _stopwatch.elapsedMilliseconds / 1000.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          computeBackend.isGpuAccelerated ? 'GPU 本地生成' : '本地生成 · CPU 回退',
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
                        _cancelled ? Icons.stop_rounded : Icons.auto_awesome_rounded,
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
                color: computeBackend.isGpuAccelerated
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
                    computeBackend.isGpuAccelerated
                        ? Icons.memory_rounded
                        : runtimeProfile.isFastPath
                            ? Icons.bolt_rounded
                            : Icons.speed_rounded,
                    color: computeBackend.isGpuAccelerated
                        ? const Color(0xFF3478F6)
                        : runtimeProfile.isFastPath
                            ? const Color(0xFF6D4CF5)
                            : const Color(0xFF756E80),
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${computeBackend.displayLabel} · ${runtimeProfile.isFastPath ? 'LCM FAST · ' : ''}${runtimeProfile.label}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${computeBackend.detailLabel} · 中心裁剪 ${request.width}×${request.height} RGB · 已运行 ${elapsedSeconds.toStringAsFixed(1)}s',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF766F81)),
                        ),
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
                    title: '分析人物特征',
                    subtitle: '读取并对齐本地照片',
                    state: _stageState(0, currentStage),
                  ),
                  const _StageConnector(),
                  _StageRow(
                    title: '构建人像形象',
                    subtitle: '加载本地模型',
                    state: _stageState(1, currentStage),
                  ),
                  const _StageConnector(),
                  _StageRow(
                    title: '生成最终画面',
                    subtitle: hasSamplingProgress ? '$_step / $_steps · $percent%' : '等待真实进度',
                    state: _stageState(2, currentStage),
                  ),
                  const _StageConnector(),
                  _StageRow(
                    title: '保存本地作品',
                    subtitle: '生成后自动写入应用目录',
                    state: _stageState(3, currentStage),
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
            if (hasSamplingProgress)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$_step / $_steps', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('$percent%', style: const TextStyle(color: _brand, fontWeight: FontWeight.w900)),
                ],
              )
            else
              const Text(
                '等待模型真实进度回调…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8B8497), fontSize: 12),
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
            const Text(
              'R5 展示实际 FFI backend；若看到 GPU · Vulkan，推理 isolate 也会加载 Vulkan 后端。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF96909F), fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  int _stageIndex() {
    if (_cancelled || _error != null) return 2;
    if (_stage == '准备图片') return 0;
    if (_stage == '加载本地模型') return 1;
    if (_stage == '扩散采样') return 2;
    if (_stage == '完成') return 3;
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
