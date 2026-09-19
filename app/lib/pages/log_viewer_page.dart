import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log.dart';

/// 运行日志查看器：实时展示 [AppLog] 捕获的程序日志。
///
/// - 按日志级别过滤（默认显示全部）；
/// - 支持一键复制 / 清空；
/// - 反转列表，从最新一条开始展示。
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  /// 过滤用的最低日志级别；`null` 表示显示全部。
  AppLogLevel? _minLevel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          ListenableBuilder(
            listenable: AppLog(),
            builder: (context, _) => _buildLevelFilter(context),
          ),
          ListenableBuilder(
            listenable: AppLog(),
            builder: (context, _) => IconButton(
              tooltip: '复制日志',
              onPressed: AppLog().isEmpty ? null : () => _copyLogs(context),
              icon: const Icon(Icons.copy_all_outlined),
            ),
          ),
          ListenableBuilder(
            listenable: AppLog(),
            builder: (context, _) => IconButton(
              tooltip: '清空日志',
              onPressed: AppLog().isEmpty ? null : () => AppLog().clear(),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: AppLog(),
        builder: (context, _) {
          final entries = _filtered(AppLog().entries);
          if (entries.isEmpty) {
            return Center(
              child: Text(
                '${_minLevel == null ? '' : '当前级别下'}暂无日志',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            );
          }
          return ListView.builder(
            // 反向列表：从最新一条开始显示，避免长列表定位到末尾。
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              // reverse 列表索引 0 对应最新一条。
              final entry = entries[entries.length - 1 - index];
              return _LogLine(entry: entry);
            },
          );
        },
      ),
    );
  }

  /// 按最低级别过滤日志（`null` = 全部）。
  List<AppLogEntry> _filtered(List<AppLogEntry> all) {
    if (_minLevel == null) return all;
    return all.where((e) => e.level.priority >= _minLevel!.priority).toList();
  }

  /// 级别过滤入口（PopupMenu，选中项为高亮锚点）。
  Widget _buildLevelFilter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = _minLevel;
    return Tooltip(
      message: '按级别过滤',
      child: PopupMenuButton<AppLogLevel?>(
        icon: const Icon(Icons.filter_alt_outlined),
        tooltip: '按级别过滤',
        onSelected: (v) => setState(() => _minLevel = v),
        itemBuilder: (context) => [
          PopupMenuItem<AppLogLevel?>(
            value: null,
            child: _FilterLabel(
              label: '全部',
              active: current == null,
              color: scheme.onSurface,
            ),
          ),
          for (final level in AppLogLevel.values)
            PopupMenuItem<AppLogLevel?>(
              value: level,
              child: _FilterLabel(
                label: level.name.toUpperCase(),
                active: current == level,
                color: _LogLine.levelColor(level),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copyLogs(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = AppLog().entries.map((e) => e.formatted).join('\n');
    if (text.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('暂无日志可复制')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      const SnackBar(content: Text('日志已复制到剪贴板')),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel({
    required this.label,
    required this.active,
    required this.color,
  });

  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          active ? Icons.check : Icons.circle_outlined,
          size: 18,
          color: active ? Theme.of(context).colorScheme.primary : color,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});
  final AppLogEntry entry;

  /// 各日志级别的主题色（深浅色下均保持可读）。
  static const _levelColors = <AppLogLevel, Color>{
    AppLogLevel.debug: Color(0xFF546E7A),
    AppLogLevel.info: Color(0xFF1976D2),
    AppLogLevel.warn: Color(0xFFF57C00),
    AppLogLevel.error: Color(0xFFC62828),
  };

  /// 供过滤器菜单复用：返回级别对应的展示色。
  static Color levelColor(AppLogLevel level) =>
      _levelColors[level] ?? const Color(0xFF546E7A);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _levelColors[entry.level] ?? scheme.onSurfaceVariant;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: scheme.onSurface,
          height: 1.4,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: RichText(
        text: TextSpan(
          style: textStyle,
          children: [
            TextSpan(
              text: '${_ts(entry.time)} [${entry.level.tag}] ',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: entry.module.isEmpty ? '' : '${entry.module} ',
              style: TextStyle(color: color),
            ),
            TextSpan(text: entry.message),
          ],
        ),
      ),
    );
  }

  static String _ts(DateTime t) {
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}.${p(t.millisecond, 3)}';
  }
}