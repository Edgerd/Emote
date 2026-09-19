import 'package:flutter/foundation.dart';

/// 日志级别。
enum AppLogLevel {
  debug(0, 'D'),
  info(1, 'I'),
  warn(2, 'W'),
  error(3, 'E');

  const AppLogLevel(this.priority, this.tag);
  final int priority;
  final String tag;
}

/// 一条运行日志。
class AppLogEntry {
  AppLogEntry({
    required this.time,
    required this.level,
    required this.module,
    required this.message,
  });

  final DateTime time;
  final AppLogLevel level;
  final String module;
  final String message;

  String get formatted =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}.${_three(time.millisecond)} '
      '[${level.tag}] ${module.isEmpty ? '' : '$module '}$message';

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _three(int n) => n.toString().padLeft(3, '0');
}

/// 应用运行日志服务（环形缓冲，供开发者选项页展示）。
///
/// - 在内存中保留最近 [_maxEntries] 条日志；
/// - 每次写入同时通过 [debugPrint] 镜像到控制台，方便调试；
/// - 实现 [ChangeNotifier]，日志查看页用 `ListenableBuilder` 实时刷新。
class AppLog extends ChangeNotifier {
  AppLog._();
  static final AppLog _instance = AppLog._();
  factory AppLog() => _instance;

  static const int _maxEntries = 2000;
  final List<AppLogEntry> _entries = [];

  /// 当前缓存的日志（不可变视图，尾部为最新）。
  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  void _write(AppLogLevel level, String module, String message) {
    if (message.isEmpty) return;
    final entry = AppLogEntry(
      time: DateTime.now(),
      level: level,
      module: module,
      message: message,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    // 镜像到控制台。
    debugPrint(entry.formatted);
    notifyListeners();
  }

  void debug(String module, String message) =>
      _write(AppLogLevel.debug, module, message);
  void info(String module, String message) =>
      _write(AppLogLevel.info, module, message);
  void warn(String module, String message) =>
      _write(AppLogLevel.warn, module, message);
  void error(String module, String message) =>
      _write(AppLogLevel.error, module, message);

  /// 清空运行日志。
  void clear() {
    _entries.clear();
    notifyListeners();
  }
}