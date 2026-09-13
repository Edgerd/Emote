import 'dart:io';

import 'package:flutter/material.dart';

/// M3E 响应式断点：Compact / Medium / Expanded。
///
/// 断点基于窗口逻辑宽度（dp）：
/// - Compact  ：width <  600
/// - Medium   ：600 <= width < 840
/// - Expanded ：width >= 840
enum WindowSizeClass { compact, medium, expanded }

extension WindowSizeClassX on WindowSizeClass {
  /// Compact 使用移动布局（NavigationBar）。
  bool get isCompact => this == WindowSizeClass.compact;
  bool get isMedium => this == WindowSizeClass.medium;
  bool get isExpanded => this == WindowSizeClass.expanded;

  /// 桌面端采用 NavigationRail + 宽布局。
  bool get isDesktopClass => isMedium || isExpanded;
}

/// 由窗口/屏幕宽度解析 [WindowSizeClass]。
class WindowSizeClassResolver {
  WindowSizeClassResolver._();

  static const double compactMax = 600;
  static const double mediumMax = 840;

  static WindowSizeClass fromWidth(double width) {
    if (width < compactMax) return WindowSizeClass.compact;
    if (width < mediumMax) return WindowSizeClass.medium;
    return WindowSizeClass.expanded;
  }

  /// 便捷工具：从 [BuildContext] 读取当前窗口尺寸并映射到断点。
  static WindowSizeClass of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);
}

/// 平台是否是桌面端（Windows / Linux）。
bool isDesktopPlatform() =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;