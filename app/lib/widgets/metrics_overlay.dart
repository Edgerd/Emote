import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 性能监控信息浮层（第 4.9 段）。
///
/// 仅在「开发者模式」下显示，叠加于视频区域：
/// 实时 FPS、延迟、码率、编/解码耗时。
class MetricsOverlay extends StatelessWidget {
  const MetricsOverlay({
    super.key,
    required this.fps,
    required this.latencyMs,
    required this.bitrateKbps,
    required this.encodeMs,
    required this.decodeMs,
  });

  final double fps;
  final int latencyMs;
  final int bitrateKbps;
  final double encodeMs;
  final double decodeMs;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: spacingX1,
      bottom: spacingX1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _formatMetrics(),
          style: TextStyle(
            color: Colors.limeAccent,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  String _formatMetrics() {
    final parts = <String>[
      '${fps.toStringAsFixed(1)}fps',
      '${latencyMs}ms',
      '${(bitrateKbps / 1000).toStringAsFixed(1)}Mbps',
      'enc ${encodeMs.toStringAsFixed(1)}ms',
      'dec ${decodeMs.toStringAsFixed(1)}ms',
    ];
    return parts.join(' · ');
  }
}
