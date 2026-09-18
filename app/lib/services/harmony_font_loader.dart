import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// HarmonyOS Sans 字体管理器。
///
/// 背景：Windows 7 用兼容层运行、或系统缺少中文字体时，Flutter 自带 Roboto
/// 没有 CJK 字形，中文会整体消失、只剩英文。解决办法：应用启动后后台下载
/// 华为 HarmonyOS Sans 并动态注册，让中文能正常渲染（win7 中文不再显示方框）。
///
/// 规则（内存 / 存储 / 网络友好）：
/// 1. 若已解压过字体（缓存命中），直接用缓存，**不重复下载**（避免反复拉取约 50MB 包）；
/// 2. 否则后台**流式**下载 zip 到临时文件（按块写盘，而非一次性整包进内存），
///    通过 [downloadProgress] 实时暴露进度供 UI 淡入淡出展示；
/// 3. 从临时 zip 解密到应用资源目录后**立即删除该临时 zip**，不占用多余磁盘；
/// 4. 下载/解压失败或超时 → 回退系统默认字体（不做任何覆盖）；
/// 5. 加载成功后通过 [fontFamily] 暴露，触发主题重建。
class FontManager extends ChangeNotifier {
  FontManager._();

  /// 当前应使用的字体族；null 表示使用系统默认字体。
  String? _fontFamily;
  bool _loading = false;

  // ---- 下载进度状态（供 UI 淡入淡出展示）----
  bool _downloading = false;
  double _progress = 0; // 0..1；<0 表示总长未知（不确定进度）
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  final Stopwatch _reportGauge = Stopwatch()..start();

  static final FontManager _instance = FontManager._();
  factory FontManager() => _instance;

  String? get fontFamily => _fontFamily;
  bool get isReady => _fontFamily != null;
  bool get isLoading => _loading;

  /// 是否正在下载字体分发包。
  bool get isDownloading => _downloading;

  /// 下载进度 0..1；返回 -1 表示总大小未知（显示不确定进度）。
  double get downloadProgress => _progress;

  /// 已下载字节数。
  int get downloadedBytes => _downloadedBytes;

  /// 应答头里的总字节数（可能为 0，表示未知）。
  int get totalBytes => _totalBytes;

  static const String kDownloadUrl =
      'https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip';
  static const Duration kTimeout = Duration(seconds: 60);
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
      _setDownloading(false);
      notifyListeners();
    }
  }

  /// 设置下载状态并立即通知（进入时置零，供 UI 淡入）。
  void _enterDownloading() {
    _downloading = true;
    _downloadedBytes = 0;
    _totalBytes = 0;
    _progress = -1;
    _reportGauge
      ..reset()
      ..start();
    notifyListeners();
  }

  void _setDownloading(bool v) {
    if (_downloading == v) return;
    _downloading = v;
    notifyListeners();
  }

  Future<String?> _load() async {
    final dir = await getApplicationSupportDirectory();
    final fontDir = Directory('${dir.path}/harmony_sans');

    // 1) 已有缓存（上次下载并解压成功）则直接用，不再二次下载。
    final cached = await _ensureCjkDirectory(fontDir);
    if (cached != null) {
      await _registerCjk(cached);
      return kHarmonyFamily;
    }

    // 2) 流式下载 zip 到临时文件（带进度、超时）；失败走回退。
    _enterDownloading();
    final zip = await _downloadToTempFile(kDownloadUrl, kTimeout);
    try {
      // 3) 解压到资源目录（覆盖旧缓存）。
      if (fontDir.existsSync()) fontDir.deleteSync(recursive: true);
      fontDir.createSync(recursive: true);
      _unzipFromFile(zip, fontDir.path);

      // 若包内无 CJK 字体目录，清理垃圾并回退。
      final scDir = await _ensureCjkDirectory(fontDir);
      if (scDir == null) {
        if (fontDir.existsSync()) fontDir.deleteSync(recursive: true);
        return null;
      }
      await _registerCjk(scDir);
      return kHarmonyFamily;
    } finally {
      // 4) 存储优化：解压后立即删除临时 zip（约 50MB），不落盘缓存。
      try {
        if (zip.existsSync()) zip.deleteSync();
      } catch (_) {}
    }
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

  /// 从已下载的 zip 文件解压到 [outDir]（流式读文件，避免整包驻留内存）。
  void _unzipFromFile(File zip, String outDir) {
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
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
    } finally {
      input.close();
    }
  }

  /// 流式下载 zip 到临时文件，边收边写盘（内存占用与包大小解耦），并刷新进度。
  Future<File> _downloadToTempFile(String url, Duration timeout) async {
    final dir = await getApplicationSupportDirectory();
    final tmp = File('${dir.path}/harmony_sans_download.zip');
    if (tmp.existsSync()) {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final resp = await req.close().timeout(timeout * 2);
      if (resp.statusCode != 200) {
        throw HttpException('下载字体失败：HTTP ${resp.statusCode}', uri: req.uri);
      }
      final total =
          int.tryParse(resp.headers.value(HttpHeaders.contentLengthHeader) ?? '') ??
              0;
      _downloadedBytes = 0;
      _totalBytes = total;
      _progress = total > 0 ? 0 : -1;

      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in resp) {
          sink.add(chunk);
          received += chunk.length;
          _downloadedBytes = received;
          if (total > 0) {
            _progress = received / total;
          }
          // 节流通知：避免每个数据块都触发 UI 重建。
          if (_reportGauge.elapsedMilliseconds >= 100) {
            _reportGauge
              ..reset()
              ..start();
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }

      // 校验 zip 魔数（PK\x03\x04 / PK\x05\x06 / PK\x07\x08），非法则删除并报错。
      if (!(await _isZipFile(tmp))) {
        try {
          tmp.deleteSync();
        } catch (_) {}
        throw const FormatException('下载的字体包不是合法 zip');
      }
      return tmp;
    } finally {
      client.close(force: true);
    }
  }

  /// 读取文件头校验 ZIP 魔数。
  static Future<bool> _isZipFile(File f) async {
    try {
      final r = await f.openRead(0, 4).expand((e) => e).toList();
      if (r.length < 4) return false;
      return r[0] == 0x50 &&
          r[1] == 0x4B && // "PK"
          (r[2] == 0x03 || r[2] == 0x05 || r[2] == 0x07) &&
          (r[3] == 0x04 || r[3] == 0x06 || r[3] == 0x08);
    } catch (_) {
      return false;
    }
  }

  /// 格式化已下载 / 总大小（如 “12.0 MB / 49.7 MB”）。
  String formatProgressLabel() {
    if (_totalBytes <= 0) return '';
    return '${_mb(_downloadedBytes)} / ${_mb(_totalBytes)}';
  }

  static String _mb(int bytes) {
    final v = bytes / (1024 * 1024);
    return '${v.toStringAsFixed(1)} MB';
  }
}