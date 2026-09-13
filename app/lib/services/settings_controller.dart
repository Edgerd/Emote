import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// 主题设置的可变状态 + SharedPreferences 持久化。
///
/// 负责：主题模式（Light / Dark / System）、自定义种子色、动态颜色开关。
/// Android 默认开启动态颜色；桌面端（Windows / Linux）默认关闭。
class SettingsController extends ChangeNotifier {
  SettingsController._();
  factory SettingsController() => _instance;

  static final SettingsController _instance = SettingsController._();

  static const _kThemeMode = 'settings.themeMode';
  static const _kSeedColor = 'settings.seedColor';
  static const _kDynamicColor = 'settings.dynamicColor';

  ThemeMode _mode = ThemeMode.system;
  Color _seedColor = kDefaultSeedColor;
  late bool _dynamicColor;

  ThemeMode get mode => _mode;
  Color get seedColor => _seedColor;
  bool get dynamicColorEnabled => _dynamicColor;

  /// 桌面端默认关闭动态颜色，Android 默认开启。
  bool _defaultDynamicColor() {
    if (Platform.isAndroid) return true;
    // Windows / Linux / 其他：默认关闭。
    return false;
  }

  /// 从本地存储（SharedPreferences）读取主题设置。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_kThemeMode);
    final seed = prefs.getInt(_kSeedColor);
    final dynamicColor = prefs.getBool(_kDynamicColor);

    _mode = _modeFromIndex(modeIndex);
    _seedColor = Color(seed ?? kDefaultSeedColor.toARGB32());
    _dynamicColor = dynamicColor ?? _defaultDynamicColor();
    notifyListeners();
  }

  ThemeMode _modeFromIndex(int? index) {
    switch (index) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  int _modeToIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 0;
      case ThemeMode.dark:
        return 1;
      case ThemeMode.system:
        return 2;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeMode, _modeToIndex(_mode));
    await prefs.setInt(_kSeedColor, _seedColor.toARGB32());
    await prefs.setBool(_kDynamicColor, _dynamicColor);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    await _save();
  }

  Future<void> setSeedColor(Color value) async {
    if (_seedColor == value) return;
    _seedColor = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDynamicColorEnabled(bool value) async {
    if (_dynamicColor == value) return;
    _dynamicColor = value;
    notifyListeners();
    await _save();
  }
}