import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// HarmonyOS Sans 字体管理器。
///
/// 背景：Windows 7 用兼容层运行、或系统缺少中文字体时，Flutter 自带 Roboto
/// 没有 CJK 字形，中文会整体消失、只剩英文。解决办法：应用启动后后台下载
/// 华为 HarmonyOS Sans 并动态注册，让中文能正常渲染。
///
/// 规则：
/// 1. 若已解压过字体，则直接使用缓存（无需联网）；
/// 2. 否则后台下载 zip 并解压到应用资源目录（ApplicationSupport）；
/// 3. 下载/解压失败或超时 → 回退系统默认字体（不做任何覆盖）；
/// 4. 加载成功后通过 [fontFamily] 暴露，触发主题重建。
class FontManager extends ChangeNotifier {
  FontManager._();

  /// 当前应使用的字体族；null 表示使用系统默认字体。
  String? _fontFamily;
  bool _loading = false;

  static final FontManager _instance = FontManager._();
  factory FontManager() => _instance;

  String? get fontFamily => _fontFamily;
  bool get isReady => _fontFamily != null;
  bool get isLoading => _loading;

  static const String kDownloadUrl =
      'https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip';
  static const Duration kTimeout = Duration(seconds: 30);
  static const String kHarmonyFamily = 'HarmonyOS Sans';

  /// 解析并加载 HarmonyOS Sans（幂等；失败即回退，永不抛错）。
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

  Future<String?> _load() async {
    final dir = await getApplicationSupportDirectory();
    final fontDir = Directory('${dir.path}/harmony_sans');

    // 1) 已有缓存则直接用。
    final cached = await _ensureCjkDirectory(fontDir);
    if (cached != null) {
      await _registerCjk(cached);
      return kHarmonyFamily;
    }

    // 2) 下载 zip，带超时；失败抛错走回退。
    final bytes = await _download(kDownloadUrl, kTimeout);

    // 3) 解压到资源目录（覆盖旧缓存）。
    try {
      if (fontDir.existsSync()) fontDir.deleteSync(recursive: true);
      fontDir.createSync(recursive: true);
      _unzip(bytes, fontDir.path);
    } catch (e) {
      // 解压失败：清理半成品，回退系统字体。
      if (fontDir.existsSync()) fontDir.deleteSync(recursive: true);
      rethrow;
    }

    // 4) 注册 CJK 字体；包内若无中文字体则静默回退。
    final scDir = await _ensureCjkDirectory(fontDir);
    if (scDir == null) return null;
    await _registerCjk(scDir);
    return kHarmonyFamily;
  }

  /// 递归查找并确保包含 CJK 字体的目录存在，返回该目录；找不到返回 null。
  Future<Directory?> _ensureCjkDirectory(Directory root) async {
    if (!root.existsSync()) return null;
    final dirs = <Directory>[];
    root.listSync(recursive: true).whereType<Directory>().forEach(dirs.add);
    // 也把根目录算进去，避免字体文件直接放在根下。
    dirs.insert(0, root);

    // 优先：目录名含简体中文标识（sc / simplified / cn）。
    for (final d in dirs) {
      final name = d.path.toLowerCase();
      if (name.contains('sc') ||
          name.contains('simplified') ||
          name.contains('cn')) {
        if (_dirHasFont(d)) return d;
      }
    }
    // 次选：任意含 ttf/otf 的目录。
    for (final d in dirs) {
      if (_dirHasFont(d)) return d;
    }
    return null;
  }

  bool _dirHasFont(Directory d) => d
      .listSync(recursive: true)
      .whereType<File>()
      .any((f) => _isFontFile(f.path));

  bool _isFontFile(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.ttf') || p.endsWith('.otf');
  }

  /// 按字重收集目录下字体并注册到 Flutter，供 TextStyle(fontFamily:) 使用。
  Future<void> _registerCjk(Directory dir) async {
    final byWeight = <int, File>{};
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!_isFontFile(file.path)) continue;
      final name = file.path.split(Platform.pathSeparator).last.toLowerCase();
      int w;
      if (name.contains('thin') || name.contains('light')) {
        w = 300;
      } else if (name.contains('medium')) {
        w = 500;
      } else if (name.contains('bold') || name.contains('semibold')) {
        w = 700;
      } else if (name.contains('black')) {
        w = 900;
      } else {
        w = 400; // Regular / 默认
      }
      // 同字重时后写覆盖（保留更具体的 SC 版本）。
      byWeight[w] = file;
    }

    // 必须存在 Regular，否则整个注册无意义。
    final regular = byWeight[400];
    if (regular == null) return;

    final loader = FontLoader(kHarmonyFamily);
    for (final entry in byWeight.entries) {
      final data = await entry.value.readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(data)));
    }
    await loader.load();
  }

  /// 将 zip 字节解压到 [outDir]。
  void _unzip(List<int> bytes, String outDir) {
    final archive = ZipDecoder().decodeBytes(Uint8List.fromList(bytes));
    for (final file in archive) {
      if (!file.isFile) continue;
      // 防 zip 路径穿越：统一用 / 规范化后拼接到 outDir。
      final rel = file.name.split('/').join(Platform.pathSeparator);
      final target = File('$outDir$Platform.pathSeparator$rel');
      if (!target.path.startsWith(outDir)) continue; // 越界跳过
      target.parent.createSync(recursive: true);
      final data = file.content as List<int>;
      if (data.isNotEmpty) target.writeAsBytesSync(data, flush: true);
    }
  }

  /// 带超时与重试的下载，校验为合法 zip 后返回字节。
  Future<Uint8List> _download(String url, Duration timeout) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final resp = await req.close().timeout(timeout * 2);
      if (resp.statusCode != 200) {
        throw HttpException('下载字体失败：HTTP ${resp.statusCode}', uri: req.uri);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      final out = builder.takeBytes();
      // 校验 zip 魔数（PK\x03\x04 / PK\x05\x06 / PK\x07\x08），非法则报错。
      if (!_isZipBytes(out)) {
        throw const FormatException('下载的字体包不是合法 zip');
      }
      return Uint8List.fromList(out);
    } finally {
      client.close(force: true);
    }
  }

  /// ZIP 文件魔数校验。
  static bool _isZipBytes(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 && bytes[1] == 0x4B && // "PK"
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
        (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
  }
}