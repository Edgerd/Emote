import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 开发者设置的持久化状态。
///
/// 目前仅管理「开发者模式」开关：在关于页连续点击版本号 [_clickToUnlock] 次后
/// 开启，之后设置页会显示「开发者选项」入口。
class DevSettingsController extends ChangeNotifier {
  DevSettingsController._();
  factory DevSettingsController() => _instance;

  static final DevSettingsController _instance = DevSettingsController._();

  /// 解锁开发者模式所需点击版本号的次数。
  static const int clickToUnlock = 20;

  static const String _kDeveloperMode = 'dev.developerMode';

  bool _developerMode = false;

  bool get developerMode => _developerMode;

  /// 从本地存储读取开发者模式状态。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _developerMode = prefs.getBool(_kDeveloperMode) ?? false;
    notifyListeners();
  }

  Future<void> setDeveloperMode(bool value) async {
    if (_developerMode == value) return;
    _developerMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDeveloperMode, _developerMode);
  }
}