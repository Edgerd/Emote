import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 桌面端交互适配工具：窗口尺寸、鼠标悬停、右键菜单、快捷键。
///
/// 仅影响交互参数，不改变三端共用的 M3E 颜色与排版。
class DesktopAdaptation {
  DesktopAdaptation._();

  /// 桌面端窗口最小尺寸建议值（dp）。
  /// 如需在 runner 原生层真正 clamp，Linux 改 my_application.cc 的尺寸，
  /// Windows 改 main.cpp 的 `Win32Window::Size`；这里作为约束常量供 UI 层参考。
  static const Size minDesktopSize = Size(720, 480);

  /// 鼠标悬停包装：进入/退出时回调，并同时切换光标。
  static Widget hover({
    required Widget child,
    void Function(PointerHoverEvent)? onHover,
    void Function()? onEnter,
    void Function()? onExit,
    MouseCursor cursor = SystemMouseCursors.basic,
  }) {
    return MouseRegion(
      cursor: cursor,
      onEnter: (_) => onEnter?.call(),
      onExit: (_) => onExit?.call(),
      onHover: onHover,
      child: child,
    );
  }

  /// 在给定指针位置弹出一个右键（secondary-tap）上下文菜单。
  static void showContextMenu(
    BuildContext context, {
    required Offset position,
    required List<ContextMenuItem> items,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(position);
    final rect = RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      overlay.size.width - local.dx,
      overlay.size.height - local.dy,
    );
    showMenu<void>(
      context: context,
      position: rect,
      items: [
        for (final it in items)
          PopupMenuItem<void>(
            height: 40,
            onTap: it.onSelected,
            child: Text(it.label),
          ),
      ],
    );
  }

  /// 桌面端常用快捷键（Shortcuts + Actions）。
  /// 用 [Shortcuts.manager] 包住可聚焦子树即可生效。
  static Map<ShortcutActivator, Intent> defaultShortcuts() => {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveIntent(),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _ToggleSidebarIntent(),
      };
}

/// 右键菜单单条。
class ContextMenuItem {
  ContextMenuItem({required this.label, this.onSelected});
  final String label;
  final void Function()? onSelected;
}

class _SaveIntent extends Intent {}

class _ToggleSidebarIntent extends Intent {}

/// 把桌面端快捷键（Shortcuts + Actions）绑定到子树。
class DesktopShortcuts extends StatelessWidget {
  const DesktopShortcuts({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: DesktopAdaptation.defaultShortcuts(),
      child: Actions(
        actions: {
          _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) {
            // 占位：保存当前设置。
            return null;
          }),
          _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(onInvoke: (_) {
            // 占位：切换侧边栏/导航条显隐。
            return null;
          }),
        },
        child: child,
      ),
    );
  }
}