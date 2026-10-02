import 'package:flutter/material.dart';

import '../pages/remote_session_page.dart';
import '../theme/app_theme.dart';

/// Android 端多会话页面栈管理（第 4.2 段）。
///
/// 每个会话一个独立 `Navigator` 页面，返回键关闭最上层会话。
/// 桌面端使用 [SessionContainerPage] 标签页，此组件仅限移动端。
class MobileSessionStack extends StatefulWidget {
  const MobileSessionStack({super.key, required this.sessionIds});

  /// 已打开的会话 ID（栈顺序，最后一个在最上层）。
  final List<String> sessionIds;

  @override
  State<MobileSessionStack> createState() => _MobileSessionStackState();
}

class _MobileSessionStackState extends State<MobileSessionStack> with RouteAware {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Navigator(
        key: _navKey,
        onGenerateRoute: (settings) {
          return MaterialPageRoute<void>(
            builder: (_) => _StackBody(navKey: _navKey, sessionIds: widget.sessionIds),
          );
        },
      ),
      bottomNavigationBar: widget.sessionIds.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(spacingX1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '会话 ${widget.sessionIds.length}',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    FilledButton(
                      onPressed: _popTop,
                      child: const Text('关闭当前'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _popTop() {
    _navKey.currentState?.pop();
  }
}

/// 栈内主体：显示当前最上层会话 + 会话切换按钮。
class _StackBody extends StatelessWidget {
  const _StackBody({required this.navKey, required this.sessionIds});

  final GlobalKey<NavigatorState> navKey;
  final List<String> sessionIds;

  @override
  Widget build(BuildContext context) {
    if (sessionIds.isEmpty) {
      return const Center(
        child: Text('无活跃会话', style: TextStyle(color: Colors.white54)),
      );
    }

    // IndexedStack 保活所有会话画面（切换不中断）。
    final topId = sessionIds.last;
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: spacingX1),
            children: [
              for (final id in sessionIds)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ActionChip(
                    label: Text(id),
                    avatar: Icon(
                      id == topId ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16,
                    ),
                    onPressed: () => navKey.currentState?.pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => _StackBody(navKey: navKey, sessionIds: sessionIds),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: sessionIds.indexOf(topId),
            children: [
              for (final id in sessionIds)
                RemoteSessionPage(sessionId: id),
            ],
          ),
        ),
      ],
    );
  }
}
