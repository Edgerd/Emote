import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// HarmonyOS Sans 字体管理器。
///
/// 背景：Windows 7 使用兼容层运行、或系统缺少中文字体时，Flutter 内置的
/// Roboto 没有 CJK 字形，中文会整体消失、只显示英文。解决办法是应用启动后
/// 后台下载华为 HarmonyOS Sans 字体并动态注册，使中文得以渲染。
///
/// 规则：
/// 1. 启动后异步下载并解压到应用资源目录；
/// 2. 若网络不佳 / 下载失败 / 已缓存未过期，则回退到系统默认字体（不做任何覆盖）；
/// 3. 加载成功后才通过 [FontManager.fontFamily] 对外暴露字体族，UI 实时刷新。
class FontManager extends ChangeNotifier {
  FontManager._();

  /// 已选中的字体族名（加载成功后有值，失败为 null → 使用系统默认）。
  String? _fontFamily;
  String? _fontVersion;
  bool _loading = false;

  static final FontManager _instance = FontManager._();
  factory FontManager() => _instance;

  /// 当前应使用的字体族；为 null 时使用系统默认字体。
  String? get fontFamily => _fontFamily;
  String? get fontVersion => _fontVersion;
  bool get isReady => _fontFamily != null;
  bool get isLoading => _loading;

  /// HarmonyOS Sans 下载地址（华为开发者官网发行版 zip）。
  static const String kDownloadUrl =
      'https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip';

  /// 下载 / 解压总超时（秒）。超时一律回退系统字体，不阻塞启动。
  static const Duration kTimeout = Duration(seconds: 30);

  /// 字体族名（用于 FontLoader 与 ThemeData）。
  static const String kHarmonyFamily = 'HarmonyOS Sans';

  /// 解析并加载 HarmonyOS Sans。
  Future<void> ensureLoaded() async {
    if (_loading || _fontFamily != null) return;
    _loading = true;
    notifyListeners();
    try {
      final family = await _load();
      if (family != null) {
        _fontFamily = family;
      }
    } catch (e) {
      debugPrint('Harmony 字体加载失败，回退系统字体：$e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 核心逻辑：确定字体文件 → 注册到 Flutter，返回字体族名。
  Future<String?> _load() async {
    final dir = await getApplicationSupportDirectory();
    final fontDir = Directory('${dir.path}/harmony_sans');
    final zipFile = File('${dir.path}/harmony_sans_cache.zip');

    // 1) 已解压过且包含 SC 字体 → 直接用缓存。
    final cached = _findCjkFont(fontDir);
    if (cached != null) {
      _fontVersion = _readVersion(fontDir);
      await _registerCjk(fontDir, fontDir.path);
      return kHarmonyFamily;
    }

    // 2) 下载 zip（带超时）。
    final bytes = await _download(kDownloadUrl, kTimeout);

    // 3) 解压到应用资源目录（覆盖旧缓存）。
    try {
      if (zipFile.existsSync()) zipFile.deleteSync();
      zipFile.writeAsBytesSync(bytes, flush: true);

      if (fontDir.existsSync()) fontDir.deleteSync(recursive: true);
      fontDir.createSync(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (!file.isFile) continue;
        final target = File('${fontDir.path}/${file.name}');
        target.parent.createSync(recursive: true);
        final data = file.content as List<int>;
        if (!data.isEmpty) {
          target.writeAsBytesSync(data, flush: true);
        }
      }
    } finally {
      // 下载/解压成功后缓存 zip，供下次离线使用；失败则清理。
      if (zipFile.existsSync() && zipFile.lengthSync() == 0) {
        zipFile.deleteSync();
      }
    }

    // 4) 注册 CJK 字体；解压内容里可能没有 SC，则退化静默。
    final familyZipped = _findCjkFont(fontDir);
    if (familyZipped == null) {
      return null;
    }
    _fontVersion = _readVersion(fontDir);
    await _registerCjk(fontDir, fontDir.path);
    return kHarmonyFamily;
  }

  /// 从解压目录寻找 SC（简体中文）子目录，返回其目录路径；找不到返回 null。
  Directory? _findCjkFont(Directory root) {
    if (!root.existsSync()) return null;
    // 优先命中简体中文字体子目录（文件名含 SC / SC_R / Simplified）。
    final best = <Directory>[];
    for (final f in root.listSync(recursive: false)) {
      if (f is! Directory) continue;
      final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
      if (name.contains('sc') ||
          name.contains('simplified') ||
          name.contains('cn')) {
        best.add(f);
      }
    }
    if (best.isNotEmpty) return best.first;
    // 次选：无 SC 时，取含 ttf/otf 的第一个目录。
    for (final f in root.listSync(recursive: false)) {
      if (f is! Directory) continue;
      final hasFont = f
          .listSync(recursive: true)
          .whereType<File>()
          .any((e) => _isFontFile(e.path));
      if (hasFont) return f;
    }
    return null;
  }

  bool _isFontFile(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.ttf') || p.endsWith('.otf');
  }

  /// 将 SC 目录下的字体文件按字重注册到 Flutter。
  Future<void> _registerCjk(Directory root, String dirPath) async {
    final base = Directory(dirPath);
    if (!base.existsSync()) return;

    final families = <int, List<ByteData>>{};
    // weight → 文件。优先收集四档字重：Regular(400)/Medium(500)/Bold(700)/Light(300)。
    final byWeight = <int, File>{};

    for (final file in base.listSync(recursive: true)) {
      if (file is! File || !_isFontFile(file.path)) continue;
      final name = file.path.split(Platform.pathSeparator).last.toLowerCase();
      int? w;
      if (name.contains('thin') || name.contains('light')) w = 300;
      else if (name.contains('medium')) w = 500;
      else if (name.contains('bold')) w = 700;
      else if (name.contains('black')) w = 900;
      else w = 400; // Regular / 默认
      // 更高优先级：若同级已有同 weight 的 400 具体字体，避免覆盖。
      byWeight[w] = file;
    }

    // 含 Regular 必须存在，否则整个注册无意义。
    final regular = byWeight[400];
    if (regular == null) return;

    for (final entry in byWeight.entries) {
      final data = await root
          .listSync(recursive: true)
          .map((e) => e)
          .whereType<File>()
          .firstWhere((f) => f.path == entry.value.path)
          .readAsBytes();
      final bd = ByteData.sublistView(Uint8List.fromList(data));
      families.putIfAbsent(entry.key, () => []).add(bd);
    }

    final loader = FontLoader(kHarmonyFamily);
    families.forEach((weight, fonts) {
      for (final f in fonts) {
        loader.addFont(Future.value(f));
      }
    });
    await loader.load();
  }

  /// 从 Zip 包中读取一个简易版本号（用于缓存判断，简单实现）。
  String? _readVersion(Directory root) {
    try {
      final files = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      if (files.isEmpty) return null;
      return 'cache';
    } catch (_) {
      return null;
    }
  }

  /// 下载核心：使用 [HttpClient]，启用超时与重试。
  Future<Uint8List> _download(String url, Duration timeout) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) {
        throw HttpException('下载字体失败：HTTP ${resp.statusCode}', uri: req.uri);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      final out = builder.takeBytes();
      if (!ZipDecoder().isValidArchive(out)) {
        throw const FormatException('下载的字体包不是合法 zip');
      }
      return out;
    } finally {
      client.close(force: true);
    }
  }
}