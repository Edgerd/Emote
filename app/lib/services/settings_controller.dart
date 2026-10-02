import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// 字体来源选择。
enum FontChoice {
  /// 系统默认字体（不下载、不加载任何自定义字体；Windows 解析为微软雅黑，
  /// Linux 解析为 Noto CJK 系或系统默认，移动端跟随系统）。
  system,

  /// HarmonyOS 字体：系统缺中文字体时自动后台下载并应用。
  harmony,

  /// 用户自选字体文件（多字重角色槽位，见 [FontRole]）。
  custom,
}

/// 自定义字体的字重角色槽位（与 UI 实际使用字重 w400/w500/w700/w900 对齐）。
///
/// 自定义字体以「同一族名 [FontManager.kCustomFamily] + 多字重」注册，
/// `TextStyle.fontWeight` 命中已注册的最近字重；`FontWeight.w600` 等中间值
/// 由引擎自动选最近已注册字重（medium）。
enum FontRole {
  /// Regular（w400）。
  regular,

  /// Medium（w500）。
  medium,

  /// Bold（w700）。
  bold,

  /// Black（w900）。
  black,
}

/// 内容显示密度。
enum ContentDensity {
  /// 宽松：更大的行距与留白（默认）。
  comfortable,

  /// 紧凑：更小的行距，一屏展示更多信息。
  compact,
}

/// 默认传输层偏好（供后续连接逻辑参考）。
enum TransportPref {
  /// 自动：由连接逻辑决定（QUIC 优先、TCP 回退）。
  auto,

  /// 强制优先使用 QUIC。
  quic,

  /// 强制优先使用 TCP。
  tcp,
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
  /// 自定义字体 4 槽位（按 [FontRole] 顺序：regular/medium/bold/black），JSON 持久化。
  static const _kCustomFontPaths = 'settings.customFontPaths';
  static const _kReduceMotion = 'settings.reduceMotion';
  static const _kContentDensity = 'settings.contentDensity';
  static const _kTransportPref = 'settings.transportPref';
  static const _kLanOnly = 'settings.lanOnly';

  ThemeMode _mode = ThemeMode.system;
  Color _seedColor = kDefaultSeedColor;
  late bool _dynamicColor;
  FontChoice _fontChoice = FontChoice.system;
  String _customFontPath = '';
  /// 自定义字体 4 槽位（按 [FontRole] 顺序，缺省槽位为空串）。
  List<String> _customFontPaths = const [''];
  bool _reduceMotion = false;
  ContentDensity _contentDensity = ContentDensity.comfortable;
  TransportPref _transportPref = TransportPref.auto;
  /// 纯局域网模式：true 时禁止任何公网下载（HarmonyOS 字体包），仅用系统默认字体。
  bool _lanOnly = false;

  ThemeMode get mode => _mode;
  Color get seedColor => _seedColor;
  bool get dynamicColorEnabled => _dynamicColor;
  FontChoice get fontChoice => _fontChoice;
  String get customFontPath => _customFontPath;
  /// 自定义字体 4 槽位（不可变视图）。
  List<String> get customFontPaths => List.unmodifiable(_customFontPaths);
  bool get reduceMotion => _reduceMotion;
  ContentDensity get contentDensity => _contentDensity;
  TransportPref get transportPref => _transportPref;
  bool get lanOnly => _lanOnly;

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
    _customFontPaths = _migrateCustomFontPaths(prefs);
    _reduceMotion = prefs.getBool(_kReduceMotion) ?? false;
    _contentDensity = _densityFromIndex(prefs.getInt(_kContentDensity));
    _transportPref = _transportFromIndex(prefs.getInt(_kTransportPref));
    _lanOnly = prefs.getBool(_kLanOnly) ?? false;
    notifyListeners();
  }

  /// 自定义字体槽位读取（含旧单键 [settings.customFontPath] 迁移）。
  ///
  /// 新键 [settings.customFontPaths] 缺失时，若旧键非空则迁移为
  /// `[old, '', '', '']`；新键已存在则直接解析（容忍旧数据长度不齐）。
  List<String> _migrateCustomFontPaths(SharedPreferences prefs) {
    final raw = prefs.getString(_kCustomFontPaths);
    if (raw != null) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          return [
            if (decoded.isNotEmpty) _asString(decoded[0]) else '',
            if (decoded.length > 1) _asString(decoded[1]) else '',
            if (decoded.length > 2) _asString(decoded[2]) else '',
            if (decoded.length > 3) _asString(decoded[3]) else '',
          ];
        }
      } catch (_) {
        // 解析失败 → 走旧键迁移路径。
      }
      return [''];
    }
    // 旧键迁移。
    if (_customFontPath.isNotEmpty) {
      return [_customFontPath, '', '', ''];
    }
    return [''];
  }

  static String _asString(Object? v) => v?.toString() ?? '';

  FontChoice _choiceFromIndex(int? index) {
    switch (index) {
      case 0:
        return FontChoice.system;
      case 1:
        return FontChoice.harmony;
      case 2:
        return FontChoice.custom;
      default:
        return FontChoice.system;
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

  ContentDensity _densityFromIndex(int? index) {
    switch (index) {
      case 1:
        return ContentDensity.compact;
      default:
        return ContentDensity.comfortable;
    }
  }

  int _densityToIndex(ContentDensity density) {
    switch (density) {
      case ContentDensity.comfortable:
        return 0;
      case ContentDensity.compact:
        return 1;
    }
  }

  TransportPref _transportFromIndex(int? index) {
    switch (index) {
      case 1:
        return TransportPref.quic;
      case 2:
        return TransportPref.tcp;
      default:
        return TransportPref.auto;
    }
  }

  int _transportToIndex(TransportPref pref) {
    switch (pref) {
      case TransportPref.auto:
        return 0;
      case TransportPref.quic:
        return 1;
      case TransportPref.tcp:
        return 2;
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
    await prefs.setString(_kCustomFontPaths, json.encode(_customFontPaths));
    await prefs.setBool(_kReduceMotion, _reduceMotion);
    await prefs.setInt(_kContentDensity, _densityToIndex(_contentDensity));
    await prefs.setInt(_kTransportPref, _transportToIndex(_transportPref));
    await prefs.setBool(_kLanOnly, _lanOnly);
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

  /// 设置自定义字体 4 槽位（按 [FontRole] 顺序）。
  ///
  /// 同步维护旧单键 [settings.customFontPath]（取第一个非空槽位），
  /// 保持向后兼容；槽位全空时旧键也清空。
  Future<void> setCustomFontPaths(List<String> paths) async {
    final normalized = _normalizeSlots(paths);
    if (_slotEquals(normalized, _customFontPaths)) {
      return;
    }
    _customFontPaths = normalized;
    // 旧键镜像：首槽非空则存首槽，否则清空。
    _customFontPath = normalized.firstWhere((p) => p.isNotEmpty, orElse: () => '');
    notifyListeners();
    await _save();
  }

  static List<String> _normalizeSlots(List<String> paths) => [
        paths.isNotEmpty ? paths[0] : '',
        paths.length > 1 ? paths[1] : '',
        paths.length > 2 ? paths[2] : '',
        paths.length > 3 ? paths[3] : '',
      ];

  static bool _slotEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> setReduceMotion(bool value) async {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    notifyListeners();
    await _save();
  }

  Future<void> setContentDensity(ContentDensity value) async {
    if (_contentDensity == value) return;
    _contentDensity = value;
    notifyListeners();
    await _save();
  }

  Future<void> setTransportPref(TransportPref value) async {
    if (_transportPref == value) return;
    _transportPref = value;
    notifyListeners();
    await _save();
  }

  /// 设置纯局域网模式（true 时禁止公网字体下载，仅用系统默认字体）。
  Future<void> setLanOnly(bool value) async {
    if (_lanOnly == value) return;
    _lanOnly = value;
    notifyListeners();
    await _save();
  }

  /// 将「本设置控制器」的全部持久化项复位为默认值。
  ///
  /// 只负责 settings.* 键；字体缓存与开发者模式（分属 [FontManager] / 
  /// [DevSettingsController]）由调用方一并复位，避免控制器间循环依赖。
  Future<void> resetAll() async {
    _mode = ThemeMode.system;
    _seedColor = kDefaultSeedColor;
    _dynamicColor = _defaultDynamicColor();
    _fontChoice = FontChoice.system;
    _customFontPath = '';
    _customFontPaths = const [''];
    _reduceMotion = false;
    _contentDensity = ContentDensity.comfortable;
    _transportPref = TransportPref.auto;
    _lanOnly = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kThemeMode);
    await prefs.remove(_kSeedColor);
    await prefs.remove(_kDynamicColor);
    await prefs.remove(_kFontChoice);
    await prefs.remove(_kCustomFontPath);
    await prefs.remove(_kCustomFontPaths);
    await prefs.remove(_kReduceMotion);
    await prefs.remove(_kContentDensity);
    await prefs.remove(_kTransportPref);
    await prefs.remove(_kLanOnly);
  }
}