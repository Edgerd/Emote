import 'dart:io';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 三端系统主题色（M3E 动态颜色）读取与回退。
///
/// Android 端真正的动态取色由 main.dart 里的 `DynamicColorBuilder`
/// 异步读取系统壁纸 Material You 色板；本文件负责平台分发 + 统一回退。
class PlatformAccent {
  PlatformAccent._();

  /// 返回 nil 即表示该平台未能提供动态色，调用方必须以 [kDefaultSeedColor] 回退。
  static Future<ColorScheme?> read({
    Brightness brightness = Brightness.light,
  }) async {
    if (Platform.isAndroid) {
      // Android：交给 main.dart 的 DynamicColorBuilder（异步可空）。
      return null;
    }
    // Windows：本应读取 UISettings.GetColorValue()。该值为系统强调色，
    // 需原生 MethodChannel；在原生通道就绪前，统一回退默认种子色、不报错。
    if (Platform.isWindows) {
      return _windowsAccent(brightness);
    }
    // Linux：本应读取 GTK 主题强调色（gtk-settings 或 portal）。同理回退。
    if (Platform.isLinux) {
      return _linuxAccent(brightness);
    }
    return null;
  }

  /// Windows 强调色读取端点（原生通道实现预留，当前返回 null → 回退）。
  static Future<ColorScheme?> _windowsAccent(Brightness brightness) async => null;

  /// Linux GTK 强调色读取端点（evaluate GTK / portal，当前返回 null → 回退）。
  static Future<ColorScheme?> _linuxAccent(Brightness brightness) async => null;

  /// 统一的“动态色可用则用之，否则回退种子色”构造器。
  static ColorScheme resolve({
    ColorScheme? dynamicScheme,
    Color fallbackSeed = kDefaultSeedColor,
    required Brightness brightness,
  }) =>
      dynamicScheme ?? ColorScheme.fromSeed(seedColor: fallbackSeed, brightness: brightness);
}