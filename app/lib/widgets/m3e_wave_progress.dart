import 'dart:math' as math;

import 'package:flutter/material.dart';

/// M3E（Material Design 3 Expressive）波浪进度条。
///
/// 用两个相位差固定 π/2 的正弦波叠加出「液面」动效，随 [value] 在 0~1 间
/// 平滑升降；[value] 为空时为不确定（indeterminate）态，做循环波动。
///
/// 无障碍对齐：
/// - 开启「减少动画」时（`MediaQuery.disableAnimations`）停止持续波动，
///   仅按 [value] 绘制静态液面；
/// - 展示宽度、主色与背景色均可由 [color] / [backgroundColor] 覆盖。
class M3eWaveProgress extends StatefulWidget {
  const M3eWaveProgress({
    super.key,
    this.value,
    this.height = 8,
    this.color,
    this.backgroundColor,
    this.waveCount = 2,
    this.speed = const Duration(milliseconds: 1500),
  });

  /// 确定的进度值（0~1）；`null` 表示不确定态。
  final double? value;

  /// 进度条高度。
  final double height;

  /// 液面波峰主色；为空时取主题 `primary`。
  final Color? color;

  /// 底部背景色；为空时取主题 `surfaceContainerHighest`。
  final Color? backgroundColor;

  /// 叠加的波浪层数（≥1），层数越多起伏越细腻。
  final int waveCount;

  /// 每层波浪单个周期耗时（相位滚动一周）。
  final Duration speed;

  @override
  State<M3eWaveProgress> createState() => _M3eWaveProgressState();
}

class _M3eWaveProgressState extends State<M3eWaveProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _controller.duration = widget.speed;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(M3eWaveProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _controller.duration = widget.speed;
    }
    _syncAnimation();
  }

  /// 视觉上还需要波动时保持动画运行，否则停止以省电：
  /// 不确定态（[value] 为空）或尚未完成（<1）时波动，完成即静止。
  void _syncAnimation() {
    final needsWave = widget.value == null || widget.value! < 1.0;
    if (needsWave) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: Container(
        height: widget.height,
        color: widget.backgroundColor ?? scheme.surfaceContainerHighest,
        child: AnimatedBuilder(
          animation: disableAnimations ? AlwaysStoppedAnimation(0.0) : _controller,
          builder: (context, _) {
            if (disableAnimations) {
              // 减少动画：画一张静态「液面」快照，不随时间变化。
              return CustomPaint(
                size: Size.infinite,
                painter: _WavePainter(
                  progress: widget.value ?? 0.5,
                  color: widget.color ?? scheme.primary,
                  phase: 0,
                  layers: widget.waveCount,
                ),
              );
            }
            return CustomPaint(
              size: Size.infinite,
              painter: _WavePainter(
                progress: widget.value ?? 0.5,
                color: widget.color ?? scheme.primary,
                phase: _controller.value * 2 * math.pi,
                layers: widget.waveCount,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.progress,
    required this.color,
    required this.phase,
    required this.layers,
  });

  final double progress;
  final Color color;
  final double phase;
  final int layers;

  @override
  void paint(Canvas canvas, Size size) {
    final waveHeight = size.height * 0.25;
    final stillLevel = (1 - progress) * size.height;

    // 层数不足 1 时兜底。
    final layerCount = math.max(1, layers);

    for (var i = layerCount - 1; i >= 0; i--) {
      // 每层相位各偏移 π/2，中心波长反向、略扁平，叠加出自然波纹。
      final layerPhase = phase + (i * math.pi / 2);
      final opacity = 0.45 + 0.30 * (layerCount - i) / layerCount;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      final path = Path()..moveTo(0, stillLevel);
      final step = size.width / 48;
      for (double x = 0; x <= size.width; x += step) {
        final y = stillLevel +
            math.sin(x / size.width * 2 * math.pi * (1.5) + layerPhase) * waveHeight;
        path.lineTo(x, y);
      }
      // 关闭底部区域，制造「液面」填充。
      path..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
      canvas.drawPath(path, paint);
    }

    // 液面顶线：给波峰一条明晰的实线，提升在浅色背景下的辨识度。
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final line = Path()..moveTo(0, stillLevel);
    for (double x = 0; x <= size.width; x += 2) {
      final y = stillLevel +
          math.sin(x / size.width * 2 * math.pi * 1.5 + phase) * waveHeight;
      line.lineTo(x, y);
    }
    canvas.drawPath(line, linePaint);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.color != color ||
      old.layers != layers;
}