import 'package:flutter/material.dart';

/// Emote 的默认种子色（M3 基准紫）。
/// 当三端系统主题色汲取失败时，回退到该色。
const Color kDefaultSeedColor = Color(0xFF6750A4);

/// 8dp 间距系统常量（M3E spacing scale）。
const double spacingX1 = 8;
const double spacingX2 = 16;
const double spacingX3 = 24;
const double spacingX4 = 32;

/// M3E 主题与 ColorScheme 构建。
class AppTheme {
  AppTheme._();

  /// 基于 [scheme] 构建完整 ThemeData（M3 + 组件主题 + M3E 排版）。
  /// [fontFamily] 传入加载成功的字体族（如 "HarmonyOS Sans"），null 时使用 Roboto。
  static ThemeData build(ColorScheme scheme, {String? fontFamily}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: fontFamily,
    );

    return base.copyWith(
      textTheme: buildM3ETextTheme(base.textTheme, scheme, fontFamily: fontFamily),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 1,
        margin: const EdgeInsets.all(0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          minimumSize: const Size(64, 44),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        indicatorColor: scheme.secondaryContainer,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w500)),
        ),
        selectedIcon: const Icon(Icons.check, size: 18),
      ),
    );
  }

  /// M3E 排版规范：display / headline / title / body / label 五层。
  static TextTheme buildM3ETextTheme(
    TextTheme base,
    ColorScheme scheme, {
    String? fontFamily,
  }) {
    final resolved = fontFamily;
    TextStyle merge(TextStyle? t, {required String role, Color? onColor}) =>
        (t ?? const TextStyle())
            .copyWith(fontFamily: resolved, color: onColor);
    return base.copyWith(
      displayLarge: merge(base.displayLarge, role: 'displayLarge', onColor: scheme.onSurface).copyWith(fontSize: 57, height: 1.12, fontWeight: FontWeight.w400, letterSpacing: -0.25),
      displayMedium: merge(base.displayMedium, role: 'displayMedium', onColor: scheme.onSurface).copyWith(fontSize: 45, height: 1.16, fontWeight: FontWeight.w400),
      displaySmall: merge(base.displaySmall, role: 'displaySmall', onColor: scheme.onSurface).copyWith(fontSize: 36, height: 1.22, fontWeight: FontWeight.w400),
      headlineLarge: merge(base.headlineLarge, role: 'headlineLarge', onColor: scheme.onSurface).copyWith(fontSize: 32, height: 1.25, fontWeight: FontWeight.w400),
      headlineMedium: merge(base.headlineMedium, role: 'headlineMedium', onColor: scheme.onSurface).copyWith(fontSize: 28, height: 1.29, fontWeight: FontWeight.w400),
      headlineSmall: merge(base.headlineSmall, role: 'headlineSmall', onColor: scheme.onSurface).copyWith(fontSize: 24, height: 1.33, fontWeight: FontWeight.w400),
      titleLarge: merge(base.titleLarge, role: 'titleLarge', onColor: scheme.onSurface).copyWith(fontSize: 22, height: 1.27, fontWeight: FontWeight.w500, letterSpacing: 0),
      titleMedium: merge(base.titleMedium, role: 'titleMedium', onColor: scheme.onSurface).copyWith(fontSize: 16, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: 0.15),
      titleSmall: merge(base.titleSmall, role: 'titleSmall', onColor: scheme.onSurface).copyWith(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, letterSpacing: 0.1),
      bodyLarge: merge(base.bodyLarge, role: 'bodyLarge', onColor: scheme.onSurface).copyWith(fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, letterSpacing: 0.5),
      bodyMedium: merge(base.bodyMedium, role: 'bodyMedium', onColor: scheme.onSurfaceVariant).copyWith(fontSize: 14, height: 1.43, fontWeight: FontWeight.w400, letterSpacing: 0.25),
      bodySmall: merge(base.bodySmall, role: 'bodySmall', onColor: scheme.onSurfaceVariant).copyWith(fontSize: 12, height: 1.33, fontWeight: FontWeight.w400, letterSpacing: 0.4),
      labelLarge: merge(base.labelLarge, role: 'labelLarge', onColor: scheme.onSurface).copyWith(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, letterSpacing: 0.1),
      labelMedium: merge(base.labelMedium, role: 'labelMedium', onColor: scheme.onSurfaceVariant).copyWith(fontSize: 12, height: 1.33, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      labelSmall: merge(base.labelSmall, role: 'labelSmall', onColor: scheme.onSurfaceVariant).copyWith(fontSize: 11, height: 1.45, fontWeight: FontWeight.w500, letterSpacing: 0.5),
    );
  }
}