import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
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

  /// 字体包（HarmonyOS-Sans.zip，2026-10-02 固化）的 SHA-256。
  /// 下载完成后校验实际文件哈希，不符即丢弃回退系统字体，阻断供应链投毒/MITM 换包。
  static const String kExpectedSha256 =
      'fb02c86e358cd9aad8d4dfa957ee502381e7ee2e94499a9133add4324b6ce69a';

  /// 允许下载/重定向落地的域名（含 `.` 前缀匹配子域）。重定向仅允许回到这些域，
  /// 防止被 302 到任意第三方域替换包内容。
  static const List<String> kAllowedHostSuffixes = ['huawei.com'];

  /// 解析「系统默认字体」选择下应使用的字体族名（[SettingsController] 的 system 分支）。
  ///
  /// - Windows → `Microsoft YaHei`（微软雅黑，系统自带）；
  /// - Linux → 优先 `Noto Sans CJK SC`，未命中则扫描已安装的 Noto CJK 包；
  /// - 移动端（Android/iOS）→ `null`（跟随系统默认，无需指定族名）；
  /// - 其它 → `null`。
  ///
  /// 返回 null 时，[main.dart] 保持 `ThemeData.fontFamily` 为 null，引擎回退到
  /// 平台默认字体，避免在 Windows/Linux 上错误回退到 Roboto（无 CJK 字形）。
  static String? defaultFamilyForPlatform() {
    // 缓存：build() 每次重建都会调用本方法，而 Linux 分支会触发 `fc-match` 子进程，
    // 绝不能每帧都跑——首次解析后缓存结果，后续直接返回。
    if (_defaultFamilyCache != null || _defaultFamilyComputed) {
      return _defaultFamilyCache;
    }
    _defaultFamilyCache = _resolveDefaultFamily();
    _defaultFamilyComputed = true;
    return _defaultFamilyCache;
  }

  static String? _defaultFamilyCache;
  static bool _defaultFamilyComputed = false;

  static String? _resolveDefaultFamily() {
    if (Platform.isWindows) return 'Microsoft YaHei';
    if (Platform.isLinux) {
      // 常见发行版默认安装的 Noto CJK 包：优先 SC，其次任一可用。
      const preferred = ['Noto Sans CJK SC', 'Noto Sans CJK', 'Noto CJK'];
      for (final family in preferred) {
        if (_linuxHasFontFamily(family)) return family;
      }
      // 均未命中：仍返回首选族名，字体引擎按最近匹配处理（Noto CJK 已装但未命中
      // fc-match 时可回退到系统默认渲染，不阻塞启动）。
      return preferred.first;
    }
    // Android / iOS / macOS / 其它：跟随系统。
    return null;
  }

  /// Linux 下通过 `fc-match` 探测某字体族是否已安装（失败视为无）。
  static bool _linuxHasFontFamily(String family) {
    try {
      final result = Process.runSync(
        'fc-match',
        ['-f', '%{family}', family],
        runInShell: false,
      );
      // fc-match 总是返回「最接近」的族名；与请求相同才说明该族已安装。
      final out = result.stdout.toString().trim();
      return out.isNotEmpty && out == family;
    } catch (_) {
      return false;
    }
  }

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

  /// 启动时按 4 槽位加载已保存的自定义字体（[SettingsController.customFontPaths]）。
  ///
  /// 仅当存在可读的槽位文件时才注册；全空则静默返回（不误报）。与 [loadCustomFontSlots]
  /// 不同，本方法「只读」不做落盘回写，避免启动时重复复制与持久化抖动。
  Future<void> loadSavedCustomFontSlots(List<String> paths) async {
    final present = paths
        .where((p) => p.isNotEmpty && File(p).existsSync())
        .toList();
    if (present.isEmpty) return;
    try {
      final loader = FontLoader(kCustomFamily);
      for (final p in present) {
        final bytes = File(p).readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
      _customFontFamily = kCustomFamily;
      notifyListeners();
      AppLog().info('字体', '启动加载自定义字体 ${present.length}/4 槽位成功');
    } catch (e) {
      AppLog().error('字体', '启动加载自定义字体失败：$e');
    }
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

  /// 从多字重「角色槽位」加载自定义字体并注册到同一族 [kCustomFamily]。
  ///
  /// [sourcePaths] 按 [SettingsController] 的 4 槽位顺序（regular/medium/bold/black）
  /// 提供；空槽位跳过。各字重文件携带自身 OS/2 字重元数据，统一注册到 `EmoteCustomFont`
  /// 后，引擎按 `TextStyle.fontWeight` 自动命中最近已注册字重。成功后将缓存副本路径
  /// 回写 [SettingsController.customFontPaths]（旧单键由控制器自动镜像首槽）。
  Future<bool> loadCustomFontSlots(List<String> sourcePaths) async {
    final slots = <String>[
      for (var i = 0; i < 4; i++)
        (i < sourcePaths.length && sourcePaths[i].isNotEmpty)
            ? sourcePaths[i]
            : '',
    ];
    if (!slots.any((s) => s.isNotEmpty)) {
      clearCustomFont();
      await SettingsController().setCustomFontPaths(slots);
      return false;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${dir.path}/custom_font');
      cacheDir.createSync(recursive: true);
      final loader = FontLoader(kCustomFamily);
      var loadedAny = false;
      for (var i = 0; i < slots.length; i++) {
        final src = slots[i];
        if (src.isEmpty) continue;
        final target = File('${cacheDir.path}/custom_slot_$i.ttf');
        final bytes = File(src).readAsBytesSync();
        target.writeAsBytesSync(bytes, flush: true);
        slots[i] = target.path; // 持久化缓存副本路径
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
        loadedAny = true;
      }
      if (loadedAny) {
        await loader.load();
        _customFontFamily = kCustomFamily;
      }
      await SettingsController().setCustomFontPaths(slots);
      notifyListeners();
      AppLog().info(
        '字体',
        '自定义字体多字重加载成功：${slots.where((s) => s.isNotEmpty).length}/4 槽位',
      );
      return loadedAny;
    } catch (e) {
      AppLog().error('字体', '自定义字体多字重加载失败：$e');
      return false;
    }
  }

  /// 清除自定义字体（切回其它字体来源时调用）。
  void clearCustomFont() {
    if (_customFontFamily == null) return;
    _customFontFamily = null;
    notifyListeners();
  }

  /// 将 [sourcePaths] 按 [SettingsController] 的 4 槽位顺序（regular/medium/bold/black）
  /// 自动推断字重并分派到对应角色槽位；空槽位保持空串。
  ///
  /// 用户批量选择多个字体文件后调用：先据此预填 4 槽位，再交由确认弹窗让用户核对/调整。
  List<String> autoAssignRoles(List<String> sourcePaths) {
    const target = [400, 500, 700, 900]; // 对应 regular/medium/bold/black
    final slots = <String>['', '', '', ''];
    for (final p in sourcePaths) {
      if (p.isEmpty) continue;
      final w = inferWeight(p);
      var best = 0;
      var bestDist = 1 << 30;
      for (var i = 0; i < target.length; i++) {
        final d = (w - target[i]).abs();
        // 距离更近者优先；距离相同时优先落到仍为空的槽位，避免覆盖已填槽。
        if (d < bestDist ||
            (d == bestDist && slots[i].isEmpty && slots[best].isNotEmpty)) {
          best = i;
          bestDist = d;
        }
      }
      slots[best] = p;
    }
    return slots;
  }

  /// 依据文件名关键字推断字重数值（越接近 CSS 命名越精确）。
  static int inferWeight(String filename) {
    final name = filename.toLowerCase();
    if (name.contains('extrabold') || name.contains('black')) return 900;
    if (name.contains('semibold')) return 600;
    if (name.contains('bold')) return 700;
    if (name.contains('medium')) return 500;
    if (name.contains('extralight')) return 200;
    if (name.contains('light') || name.contains('thin')) return 300;
    return 400; // Regular / 未识别字重默认
  }

  /// 将 [sourcePaths] 以临时族名 [previewFamily] 注册（不落盘、不持久化），
  /// 供确认弹窗在应用正式 4 槽位前先「预览」效果；预览族与正式族 [kCustomFamily] 分离。
  Future<void> loadCustomFontPreview(
    List<String> sourcePaths,
    String previewFamily,
  ) async {
    final loader = FontLoader(previewFamily);
    for (final p in sourcePaths) {
      if (p.isEmpty) continue;
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
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
    // 用户已选「自定义字体」：使用用户自己的字体即可，**不再后台下载/加载 HarmonyOS**，
    // 避免在系统缺 CJK 时冗余下载约 50MB 却完全不生效（主题用的是自定义字体）。
    if (SettingsController().fontChoice == FontChoice.custom) {
      AppLog().info('字体', '已选自定义字体，跳过 HarmonyOS 加载/下载');
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
    if (SettingsController().lanOnly) {
      AppLog().info(
          '字体', '纯局域网模式（设置 → 纯局域网模式），跳过 HarmonyOS 公网下载，回退系统字体');
      return null;
    }
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
      // 注意：`noto` 这类宽匹配会误判 Noto Latin（无 CJK 字形）为「已具备 CJK」，
      // 导致 Linux 缺中文字体时跳过下载、中文方框——故收紧为「noto … cjk」等具体前缀。
      const cjkHints = <String>[
        'harmony', // 鸿蒙系统字体（SC/TC）
        'simsun', // 宋体
        'simhei', // 黑体
        'simfang', // 仿宋
        'simkai', // 楷体
        'msyh', // 微软雅黑
        'microsoftyahei',
        'msjh', // 微軟正黑體
        'dengxian', // 等线
        'noto sans cjk', // Noto Sans CJK（精确前缀，避免误判 Noto Latin）
        'noto serif cjk',
        'noto cjk',
        'sourcehansans', // 思源黑体
        'sourcehanserif', // 宋体
        'droidsansfallback',
        'wqy', // 文泉驿
        'pingfang', // 苹方
        'hiragino', // 冬青
        'heiti', // 黑体（macOS 字体名）
        'songti', // 宋体
        'kaiti', // 楷体
        'fangsong', // 仿宋
        'uming', // 文鼎宋
        'ukai', // 标楷
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

    // 加固：即便缺少 400（Regular）字重，只要存在其它字重也照常注册——引擎对
    // w400/w600 请求会自动选「最近的已注册字重」，避免因包内只有 Bold/Black 等子集
    // 就整体放弃注册、导致「下载了却不生效」。
    if (byWeight.isEmpty) return;

    final loader = FontLoader(kHarmonyFamily);
    for (final entry in byWeight.entries) {
      final data = await entry.value.readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(data)));
    }
    await loader.load();
    if (byWeight[400] == null) {
      AppLog().warn('字体', 'CJK 包缺少 Regular(400) 字重，已用其余字重注册');
    }
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
        // 防 zip 路径穿越：统一把条目名中的 `\` 视为分隔符并规范化；
      // 拒绝 `..`、绝对路径（/ 或盘符 C:\）、空段，拼接后仍做越界兜底。
      final raw = file.name.replaceAll('\\', '/');
      final segs = raw.split('/');
      final safe = !segs.contains('..') &&
          !raw.startsWith('/') &&
          !RegExp(r'^[A-Za-z]:').hasMatch(raw);
      if (!safe || segs.any((s) => s.isEmpty)) continue;
      final rel = segs.join(Platform.pathSeparator);
      final target = File('$outDir$Platform.pathSeparator$rel');
      if (!target.path.startsWith('$outDir$Platform.pathSeparator')) {
        continue; // 越界兜底：任何逃出 outDir 的路径一律跳过
      }
        target.parent.createSync(recursive: true);
        final data = file.content as List<int>;
        if (data.isNotEmpty) target.writeAsBytesSync(data, flush: true);
      }
    } finally {
      input.close();
    }
  }

  /// 流式下载 zip 到临时文件，边收边写盘（内存占用与包大小解耦），并刷新进度。
  ///
  /// 安全约束：
  /// - 重定向手动处理：每次 3xx 的 `Location` 必须落在 [kAllowedHostSuffixes] 白名单内，
  ///   否则拒绝（防止被 302 到第三方域换包）；最多跟随 3 跳；
  /// - 下载完成后校验 SHA-256 与 [kExpectedSha256] 一致，不符即删除并报错。
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
      ..idleTimeout = timeout
      ..followRedirects = false;
    try {
      final target = Uri.parse(url);
      final resp =
          await _openWhitelisted(client, target, maxRedirects: 3);
      if (resp.statusCode != 200) {
        throw HttpException('下载字体失败：HTTP ${resp.statusCode}',
            uri: resp.request.uri);
      }
      final total = int.tryParse(
          resp.headers.value(HttpHeaders.contentLengthHeader) ?? '') ??
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

      // SHA-256 完整性校验：与固化指纹不符（被换包 / 上游变更）即丢弃并回退系统字体。
      final digest = await _sha256Hex(tmp);
      if (digest != kExpectedSha256) {
        AppLog().warn('字体',
            '字体包 SHA-256 不匹配（期望 $kExpectedSha256，实际 $digest），丢弃并回退系统字体');
        try {
          tmp.deleteSync();
        } catch (_) {}
        throw const FormatException('字体包 SHA-256 校验失败，已拒绝使用');
      }
      return tmp;
    } finally {
      client.close(force: true);
    }
  }

  /// 打开请求并**按白名单**跟随重定向：每跳 3xx 校验 `Location` 主机在
  /// [kAllowedHostSuffixes] 内，越出即抛 [HttpException]；最多 `maxRedirects` 跳。
  Future<HttpClientResponse> _openWhitelisted(
    HttpClient client,
    Uri url, {
    required int maxRedirects,
  }) async {
    for (var i = 0; ; i++) {
      if (!_hostAllowed(url.host)) {
        throw HttpException('字体下载域名 ${url.host} 不在白名单内',
            uri: url);
      }
      final req = await client.getUrl(url).timeout(Duration(seconds: 30));
      final resp = await req.close().timeout(Duration(seconds: 120));
      final code = resp.statusCode;
      if (code >= 300 && code < 400) {
        final location = resp.headers.value(HttpHeaders.locationHeader);
        resp.close();
        if (location == null || i + 1 > maxRedirects) {
          throw HttpException(
              '字体下载重定向被拒绝（${location ?? '无 Location 头'}），防止跳出白名单',
              uri: url);
        }
        url = Uri.parse(location).replace(scheme: 'https'); // 强制回 https，防降级
        continue;
      }
      return resp;
    }
  }

  /// 主机是否落在允许域内（等值或 `.suffix` 子域）。
  static bool _hostAllowed(String host) {
    final h = host.toLowerCase();
    for (final suffix in kAllowedHostSuffixes) {
      if (h == suffix || h.endsWith('.$suffix')) return true;
    }
    return false;
  }

  /// 计算文件 SHA-256 小写 hex（包体约 50MB，整读参与摘要）。
  Future<String> _sha256Hex(File f) async {
    final bytes = await f.readAsBytes();
    return sha256.convert(bytes).toString();
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