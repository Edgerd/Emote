import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log.dart';

/// 运行日志查看器：实时展示 [AppLog] 捕获的程序日志。
class LogViewerPage extends StatelessWidget {
  const LogViewerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          ListenableBuilder(
            listenable: AppLog(),
            builder: (context, _) => IconButton(
              tooltip: '复制日志',
              onPressed: AppLog().isEmpty
                  ? null
                  : () => _copyLogs(context),
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
          final entries = AppLog().entries;
          if (entries.isEmpty) {
            return Center(
              child: Text(
                '暂无日志',
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

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});
  final AppLogEntry entry;

  static const _levelColors = <AppLogLevel, Color>{
    AppLogLevel.debug: Color(0xFF546E7A),
    AppLogLevel.info: Color(0xFF1976D2),
    AppLogLevel.warn: Color(0xFFF57C00),
    AppLogLevel.error: Color(0xFFC62828),
  };

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
              text:
                  '${_ts(entry.time)} [${entry.level.tag}] ',
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