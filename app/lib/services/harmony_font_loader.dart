import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'settings_controller.dart';
import 'app_log.dart';

/// HarmonyOS Sans 字体管理器。
///
/// 背景：Windows 7 用兼容层运行、或系统缺少中文字体时，Flutter 自带 Roboto
/// 没有 CJK 字形，中文会整体消失、只剩英文。解决办法：应用启动后后台下载
/// 华为 HarmonyOS Sans 并动态注册，让中文能正常渲染（win7 中文不再显示方框）。
///
/// 规则（内存 / 存储 / 网络友好）：
/// 0. **用户显式选择「HarmonyOS 字体」时始终加载并应用**（有缓存用缓存，无则下载一次）
///    ——修复「下载/安装了却没有应用」：此前系统装了中文字体就短路返回，导致字体永不生效；
///    仅在**非 HarmonyOS 选择**下，才探测系统；若系统已具备 CJK（已装任意中文字体、或已装
///    HarmonyOS 字体），直接沿用系统默认字体，不再下载——避免「系统已装字体仍下载」「每次
///    重启都重复下载」的冗余行为；
/// 1. 系统缺少 CJK 字体（如未中文化的精简 Win7）时后台**流式**下载 zip 到临时文件
///    （按块写盘，而非一次性整包进内存），通过 [downloadProgress] 实时暴露进度供 UI 淡入淡出展示；
/// 2. 若之前已成功解压并注册（缓存命中，含 `.ok` 标记），直接用缓存**不重复下载**；
/// 3. 从临时 zip 解压到应用支持目录后**立即删除该临时 zip**，不占用多余磁盘；
/// 4. 下载/解压失败或超时 → 回退系统默认字体（不做任何覆盖）；
/// 5. 加载成功后通过 [fontFamily] 暴露，触发主题重建。
class FontManager extends ChangeNotifier {
  FontManager._();

  /// 当前应使用的字体族；null 表示使用系统默认字体。
  String? _fontFamily;
  bool _loading = false;
  String? _customFontFamily;
  bool _didDownloadThisRun = false;

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

  // ---- 自定义字体（设置页「选择字体文件」）----
  static const String kCustomFamily = 'EmoteCustomFont';

  /// 已注册的自定义字体族；null 表示未加载或加载失败。
  String? get customFontFamily => _customFontFamily;

  /// 本次运行是否真的下载过 HarmonyOS 字体（true 时才提示重启）。
  bool get didDownloadThisRun => _didDownloadThisRun;

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
      AppLog().info('字体', '加载失败，回退系统字体：$e');
    } finally {
      _loading = false;
      _setDownloading(false);
      notifyListeners();
    }
  }

  /// 在应用启动时按需加载已保存的自定义字体（若持久化路径存在且可读）。
  Future<void> loadSavedCustomFont(String path) async {
    if (path.isEmpty) return;
    final f = File(path);
    if (!f.existsSync()) {
      AppLog().warn('字体', '自定义字体文件不存在，忽略：$path');
      return;
    }
    await loadCustomFont(path);
  }

  /// 从任意路径加载自定义字体文件并注册到 Flutter；成功返回 true，失败返回 false。
  ///
  /// 为兼容各平台直接读取权限差异（Windows / Linux 可直接读源路径；Android 需
  /// 先落盘再读），统一**复制**到应用支持目录的 `custom_font/` 下再加载，保证持久化
  /// 路径跨重启可用。
  Future<bool> loadCustomFont(String sourcePath) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${dir.path}/custom_font');
      cacheDir.createSync(recursive: true);
      final target = File('${cacheDir.path}/custom_font.ttf');
      final bytes = File(sourcePath).readAsBytesSync();
      target.writeAsBytesSync(bytes, flush: true);

      final loader = FontLoader(kCustomFamily);
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _customFontFamily = kCustomFamily;
      // 持久化路径指向缓存副本，避免用户删除源文件后失效。
      await SettingsController().setCustomFontPath(target.path);
      notifyListeners();
      AppLog().info('字体', '自定义字体加载成功：${target.path}');
      return true;
    } catch (e) {
      AppLog().error('字体', '自定义字体加载失败：$e');
      return false;
    }
  }

  /// 清除自定义字体（切回其它字体来源时调用）。
  void clearCustomFont() {
    if (_customFontFamily == null) return;
    _customFontFamily = null;
    notifyListeners();
  }

  /// 开发者调试：HarmonyOS 与自定义字体的缓存目录路径（不存在则返回其应建路径）。
  Future<String> fontCacheDirPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}harmony_sans';
  }

  /// 开发者调试：删除字体缓存（含下载失败残留与自定义字体副本），并复位内存状态。
  ///
  /// 注意：重启后 [ensureLoaded] 会根据需要重新下载/注册。
  Future<void> resetFontCache() async {
    final dir = await getApplicationSupportDirectory();
    final regions = <String>[
      '${dir.path}/harmony_sans',
      '${dir.path}/custom_font',
    ];
    for (final r in regions) {
      try {
        final d = Directory(r);
        if (d.existsSync()) {
          d.deleteSync(recursive: true);
          AppLog().info('字体', '已删除字体缓存 $r');
        }
      } catch (e) {
        AppLog().error('字体', '删除字体缓存失败($r)：$e');
      }
    }
    _fontFamily = null;
    _customFontFamily = null;
    _loading = false;
    _didDownloadThisRun = false;
    notifyListeners();
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

    // 0) 优先探测系统：若系统已具备 CJK 渲染能力（任意中文字体或已装 HarmonyOS），
    //    直接沿用系统默认字体，**不下载、不注册**，避免冗余下载与重启重复下载。
    //    下载/缓存路径在日志中明确输出，便于定位（对应「下载到了哪里」问题）。
    AppLog().info('字体', '缓存/下载目录：${fontDir.path}');
    // 显式停留在「HarmonyOS 字体」选项时：始终加载 HarmonyOS（有缓存用缓存，无则下载，
    // 均在本次内应用），**不再因系统已具备中文字体而跳过**。这修复了「下载/安装了字体
    // 却一直没有应用」的问题——此前系统装过中文字体就命中 `_systemHasCjk` 短路返回 null，
    // 导致即使选了 HarmonyOS 字体、_fontFamily 仍为 null、主题永不切字体。
    final wantHarmony = SettingsController().fontChoice == FontChoice.harmony;
    if (!wantHarmony && _systemHasCjk()) {
      AppLog().info('字体', '系统已具备中文字体/CJK，跳过 HarmonyOS 下载，沿用系统默认字体');
      return null;
    }

    // 1) 已有缓存（上次下载并解压成功，含 .ok 完成标记）则直接用，不再二次下载。
    final cached = File('${fontDir.path}/.ok').existsSync()
        ? await _ensureCjkDirectory(fontDir)
        : null;
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
      // 注册成功 → 写入完成标记，供下次启动缓存命中，避免重复下载。
      _didDownloadThisRun = true;
      try {
        File('${fontDir.path}/.ok').writeAsStringSync(
          'ok-${DateTime.now().toIso8601String()}',
          flush: true,
        );
      } catch (_) {}
      return kHarmonyFamily;
    } finally {
      // 4) 存储优化：解压后立即删除临时 zip（约 50MB），不落盘缓存。
      try {
        if (zip.existsSync()) zip.deleteSync();
      } catch (_) {}
    }
  }

  /// 判定当前系统是否已具备中文字符（CJK）渲染能力。
  ///
  /// 若能渲染，则直接沿用系统默认字体，**不再下载/注册 HarmonyOS**，避免在已装
  /// 中文字体（或已装鸿蒙字体）的机器上重复拉取约 50MB 分发包。仅当系统完全缺少
  /// CJK 字体（如未中文化的精简 Win7）时才返回 false、触发下载兜底。
  bool _systemHasCjk() {
    try {
      // Android / iOS / macOS 系统自含 CJK 字体，无需下载。
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return true;

      final dirs = <String>[];
      if (Platform.isWindows) {
        dirs.add(r'C:\Windows\Fonts');
      } else if (Platform.isLinux) {
        dirs
          ..add('/usr/share/fonts')
          ..add('/usr/local/share/fonts')
          ..add('${Platform.environment['HOME'] ?? '~'}/.fonts');
      } else {
        return true; // 其它平台按已具备 CJK 处理
      }

      // 常见 CJK 字体文件名特征（小写匹配）。
      const cjkHints = <String>[
        'harmony', // 鸿蒙系统字体（SC/TC）
        'simsun', // 宋体
        'simhei', // 黑体
        'simfang', // 仿宋
        'simkai', // 楷体
        'msyh', // 微软雅黑
        'msjh', // 微軟正黑體
        'microsoftyahei',
        'deng', // 等线
        'noto', // Noto CJK
        'sourcehansans', // 思源黑体
        'droidsansfallback',
        'wqy', // 文泉驿
        'pingfang', // 苹方
        'hiragino', // 冬青
        'heiti', // 黑体
        'songti', // 宋体
        'kaiti', // 楷体
        'fangsong', // 仿宋
      ];

      for (final d in dirs) {
        final root = Directory(d);
        if (!root.existsSync()) continue;
        for (final f in root.listSync(recursive: true).whereType<File>()) {
          final n = f.path.toLowerCase();
          if (!(n.endsWith('.ttf') || n.endsWith('.ttc') || n.endsWith('.otf'))) {
            continue;
          }
          if (cjkHints.any((h) => n.contains(h))) return true;
        }
      }
      return false;
    } catch (_) {
      // 扫描失败时保守按“无 CJK”处理，可能触发下载兜底（宁可多一次也不漏）。
      return false;
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
        // 跳过 macOS 打包垃圾（__MACOSX 元数据目录、AppleDouble ._ 资源文件），
        // 否则会被当成真实 ttf 落盘，浪费磁盘并可能干扰 CJK 目录扫描。
        final name = file.name.toLowerCase();
        if (name.contains('__macosx') || name.contains('/._')) continue;
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