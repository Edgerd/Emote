import 'package:flutter/material.dart';

import '../pages/remote_session_page.dart';
import '../theme/app_theme.dart';

/// 桌面端多会话容器页（第 4.2 段）。
///
/// 支持添加 / 关闭 / 切换会话标签；后台标签保持会话不中断（IndexedStack）。
/// Android 端使用页面栈管理（`Navigator`），此组件仅限桌面端使用。
class SessionContainerPage extends StatefulWidget {
  const SessionContainerPage({super.key});

  @override
  State<SessionContainerPage> createState() => _SessionContainerPageState();
}

class _SessionContainerPageState extends State<SessionContainerPage> {
  final List<String> _sessions = ['dev-local'];
  String _current = 'dev-local';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程会话'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加会话',
            onPressed: () {
              setState(() {
                _sessions.add('dev-${_sessions.length + 1}');
                _current = _sessions.last;
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_sessions.length > 1)
              _SessionTabStrip(
                sessions: _sessions,
                active: _current,
                onSelected: (id) => setState(() => _current = id),
                onClose: (id) {
                  if (_sessions.length <= 1) return;
                  setState(() {
                    final idx = _sessions.indexOf(id);
                    _sessions.removeAt(idx);
                    if (_current == id) _current = _sessions[idx % _sessions.length];
                  });
                },
              ),
            Expanded(
              child: IndexedStack(
                index: _sessions.indexOf(_current),
                children: [
                  for (final id in _sessions)
                    RemoteSessionPage(sessionId: id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定义标签条：圆角 chip 样式，支持关闭按钮。
class _SessionTabStrip extends StatelessWidget {
  const _SessionTabStrip({
    required this.sessions,
    required this.active,
    required this.onSelected,
    required this.onClose,
  });

  final List<String> sessions;
  final String active;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: spacingX1),
        children: [
          for (final id in sessions)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => onSelected(id),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: id == active
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: id == active ? scheme.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        id,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: id == active
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurfaceVariant,
                              fontWeight:
                                  id == active ? FontWeight.w600 : null,
                            ),
                      ),
                      if (sessions.length > 1) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.close, size: 14),
                          onPressed: () => onClose(id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '关闭 $id',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
