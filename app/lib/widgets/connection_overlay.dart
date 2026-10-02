import 'package:flutter/material.dart';

/// 连接状态 / 重连 / 性能指标覆盖层（第 4.9 段）。
///
/// 叠加在视频区域上方，可切换显示：
/// - 重连状态（"正在重连… 第 2/5 次"）
/// - 实时性能指标（FPS、延迟、码率）
///
/// 仅在调试 / 开发者模式下显示。
class ConnectionOverlay extends StatelessWidget {
  const ConnectionOverlay({
    super.key,
    required this.reconnecting,
    required this.reconnectAttempt,
    required this.maxAttempts,
    this.fps,
    this.latencyMs,
    this.bitrateKbps,
    this.showMetrics = false,
  });

  /// 是否正在重连。
  final bool reconnecting;

  /// 当前重试次数（从 1 开始）。
  final int reconnectAttempt;

  /// 最大重试次数。
  final int maxAttempts;

  /// 实时帧率（可选）。
  final double? fps;

  /// 端到端延迟 ms（可选）。
  final int? latencyMs;

  /// 码率 kbps（可选）。
  final int? bitrateKbps;

  /// 是否显示性能指标。
  final bool showMetrics;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final children = <Widget>[];

    if (reconnecting) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在重连… ($reconnectAttempt/$maxAttempts)',
                    style: textTheme.labelLarge?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (showMetrics) {
      children.add(
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _buildMetricsText(),
              style: textTheme.labelSmall?.copyWith(
                color: Colors.limeAccent,
              ),
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: reconnecting ? Colors.black.withValues(alpha: 0.4) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  String _buildMetricsText() {
    final parts = <String>[];
    if (fps != null) parts.add('${fps!.toStringAsFixed(1)} fps');
    if (latencyMs != null) parts.add('${latencyMs}ms');
    if (bitrateKbps != null) parts.add('${(bitrateKbps! / 1000).toStringAsFixed(1)}Mbps');
    return parts.join(' · ');
  }
}
