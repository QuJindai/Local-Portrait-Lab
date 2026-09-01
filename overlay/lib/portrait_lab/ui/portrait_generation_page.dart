import 'dart:async';

import 'package:flutter/material.dart';

import '../application/portrait_generation_controller.dart';
import '../domain/portrait_generation_state.dart';
import '../domain/portrait_style.dart';
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
  StreamSubscription<PortraitGenerationState>? _subscription;
  int _step = 0;
  int _steps = 0;
  String _stage = '准备图片';
  String? _error;
  bool _cancelled = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
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
      if (mounted) {
        setState(() {
          _cancelled = true;
          _stage = '已取消';
        });
      }
    } catch (error) {
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
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSamplingProgress = _steps > 0;
    final progress = hasSamplingProgress ? (_step / _steps).clamp(0.0, 1.0) : null;
    final percent = progress == null ? null : (progress * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在本地生成'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                _cancelled ? Icons.stop_circle_outlined : Icons.auto_awesome,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                _cancelled ? '生成已取消' : '正在本地生成',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                '${widget.style.spec.displayName} · $_stage',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 14),
              if (hasSamplingProgress)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$_step / $_steps'),
                    Text('$percent%'),
                  ],
                )
              else
                const Text(
                  '等待模型真实进度回调…',
                  textAlign: TextAlign.center,
                ),
              if (_error != null) ...[
                const SizedBox(height: 22),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const Spacer(),
              OutlinedButton.icon(
                key: const Key('portrait-cancel-generation'),
                onPressed: _cancelled ? null : _cancel,
                icon: const Icon(Icons.close),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Text('取消生成'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '生成在当前设备完成，不上传照片或模型。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
