import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// 字体来源选择。
enum FontChoice {
  /// 系统默认字体（不下载、不加载任何自定义字体）。
  system,

  /// HarmonyOS 字体：系统缺中文字体时自动后台下载并应用。
  harmony,

  /// 用户自选字体文件。
  custom,
}

/// 主题与字体设置的可变状态 + SharedPreferences 持久化。
///
/// 负责：主题模式（Light / Dark / System）、自定义种子色、动态颜色开关、
/// 字体来源（系统 / HarmonyOS / 自定义文件）与自定义字体路径。
/// Android 默认开启动态颜色；桌面端（Windows / Linux）默认关闭。
class SettingsController extends ChangeNotifier {
  SettingsController._();
  factory SettingsController() => _instance;

  static final SettingsController _instance = SettingsController._();

  static const _kThemeMode = 'settings.themeMode';
  static const _kSeedColor = 'settings.seedColor';
  static const _kDynamicColor = 'settings.dynamicColor';
  static const _kFontChoice = 'settings.fontChoice';
  static const _kCustomFontPath = 'settings.customFontPath';

  ThemeMode _mode = ThemeMode.system;
  Color _seedColor = kDefaultSeedColor;
  late bool _dynamicColor;
  FontChoice _fontChoice = FontChoice.harmony;
  String _customFontPath = '';

  ThemeMode get mode => _mode;
  Color get seedColor => _seedColor;
  bool get dynamicColorEnabled => _dynamicColor;
  FontChoice get fontChoice => _fontChoice;
  String get customFontPath => _customFontPath;

  /// 桌面端默认关闭动态颜色，Android 默认开启。
  bool _defaultDynamicColor() {
    if (Platform.isAndroid) return true;
    // Windows / Linux / 其他：默认关闭。
    return false;
  }

  /// 从本地存储（SharedPreferences）读取主题与字体设置。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_kThemeMode);
    final seed = prefs.getInt(_kSeedColor);
    final dynamicColor = prefs.getBool(_kDynamicColor);
    final choiceIndex = prefs.getInt(_kFontChoice);

    _mode = _modeFromIndex(modeIndex);
    _seedColor = Color(seed ?? kDefaultSeedColor.toARGB32());
    _dynamicColor = dynamicColor ?? _defaultDynamicColor();
    _fontChoice = _choiceFromIndex(choiceIndex);
    _customFontPath = prefs.getString(_kCustomFontPath) ?? '';
    notifyListeners();
  }

  FontChoice _choiceFromIndex(int? index) {
    switch (index) {
      case 0:
        return FontChoice.system;
      case 1:
        return FontChoice.harmony;
      case 2:
        return FontChoice.custom;
      default:
        return FontChoice.harmony;
    }
  }

  int _choiceToIndex(FontChoice choice) {
    switch (choice) {
      case FontChoice.system:
        return 0;
      case FontChoice.harmony:
        return 1;
      case FontChoice.custom:
        return 2;
    }
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
    await prefs.setInt(_kFontChoice, _choiceToIndex(_fontChoice));
    await prefs.setString(_kCustomFontPath, _customFontPath);
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

  Future<void> setFontChoice(FontChoice value) async {
    if (_fontChoice == value) return;
    _fontChoice = value;
    notifyListeners();
    await _save();
  }

  Future<void> setCustomFontPath(String value) async {
    if (_customFontPath == value) return;
    _customFontPath = value;
    await _save();
  }
}