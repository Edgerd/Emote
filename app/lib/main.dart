import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'package:emote/src/rust/frb_generated.dart';

import 'pages/device_list_page.dart';
import 'pages/settings_page.dart';
import 'services/harmony_font_loader.dart';
import 'services/settings_controller.dart';
import 'theme/app_theme.dart';
import 'theme/dynamic_color.dart';
import 'theme/window_size_class.dart';

/// Windows：直接从可执行文件同目录加载 Rust 动态库。
///
/// flutter_rust_bridge 默认用 [kDefaultExternalLibraryLoaderConfig.ioDirectory]
/// 的相对路径（`../rust/emote_core/target/release/`），打包后运行的 CWD 是
/// exe 所在目录，该路径解析不到 `emote_core.dll`，会导致 `RustLib.init()` 失败、
/// 首帧永不出现而窗口无法显示。改为从 exe 同目录显式加载。
ExternalLibrary? _resolveRustLib() {
  if (Platform.isWindows) {
    // Windows：DLL 与可执行文件同目录。
    return ExternalLibrary.open('emote_core.dll');
  }
  if (Platform.isLinux) {
    // Linux：libemote_core.so 打进 bundle 的 lib/ 目录，CMake 已设置
    // RPATH $ORIGIN/lib，dlopen 按文件名可解析到。
    return ExternalLibrary.open('libemote_core.so');
  }
  // Android / Web 保持 flutter_rust_bridge 默认加载方式。
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 Dart ↔ Rust 桥接（flutter_rust_bridge）。
  // 兜底：若 Rust 库初始化失败，不能再阻塞 runApp——否则首帧永不完成，
  // Windows 窗口不会显示，只剩一个驻留在后台、看不到任何报错的进程。
  try {
    await RustLib.init(externalLibrary: _resolveRustLib());
  } catch (e) {
    debugPrint('RustLib.init() 失败，应用降级继续：$e');
  }
  // 从本地存储加载主题设置（模式 / 种子色 / 动态颜色）。
  try {
    await SettingsController().load();
  } catch (e) {
    debugPrint('加载主题设置失败：$e');
  }
  runApp(const EmoteApp());

  // 后台下载并注册 HarmonyOS 中文字体，不阻塞首帧；失败时主题回退系统字体。
  // 必须先于 runApp 之后调用，确保 WidgetsBinding 可用且首帧立即出现。
  FontManager().ensureLoaded();
}

class EmoteApp extends StatelessWidget {
  const EmoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsController();

    // 监听设置与字体加载：任一变化都会触发重建，切换深浅色 / 动态色 /
    // 字体下载完成时界面实时刷新。
    return ListenableBuilder(
      listenable: Listenable.merge([settings, FontManager()]),
      builder: (context, _) {
        // 开启动态颜色只负责更换色板（Material You），绝不决定深浅色状态。
        // 深浅色由 settings.mode 独立控制；若动态色未启用或桌面端无可汲取，
        // 则 dynamicScheme 为 null，回退到 fallbackSeed 生成的固定色板。
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            // 浅色主题：优先汲取系统浅色壁纸色。
            final ColorScheme? lightScheme = settings.dynamicColorEnabled
                ? (lightDynamic ?? darkDynamic)
                : null;
            // 深色主题：优先汲取系统深色壁纸色。
            final ColorScheme? darkScheme = settings.dynamicColorEnabled
                ? (darkDynamic ?? lightDynamic)
                : null;

            // 万一 HarmonyOS 字体尚未下载完成，回退系统默认字体（不会阻塞首帧）。
            final String? fontFamily =
                FontManager().isReady ? FontManager().fontFamily : null;

            return MaterialApp(
              title: 'Emote',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(
                PlatformAccent.resolve(
                  brightness: Brightness.light,
                  dynamicScheme: lightScheme,
                  fallbackSeed: settings.seedColor,
                ),
                fontFamily: fontFamily,
              ),
              darkTheme: AppTheme.build(
                PlatformAccent.resolve(
                  brightness: Brightness.dark,
                  dynamicScheme: darkScheme,
                  fallbackSeed: settings.seedColor,
                ),
                fontFamily: fontFamily,
              ),
              themeMode: settings.mode,
              home: const AppShell(),
              // 在 Navigator 上层叠加字体下载进度条：出现/消失时淡入淡出。
              builder: (context, child) => Stack(
                children: [
                  if (child != null) child,
                  const _FontDownloadOverlay(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 应用外壳：根据窗口尺寸类选择 NavigationBar（移动）或 NavigationRail（桌面）。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _titles = ['设备发现', '设置'];

  @override
  Widget build(BuildContext context) {
    final sizeClass = WindowSizeClassResolver.of(context);
    final desktop = sizeClass.isDesktopClass;

    final body = _index == 0 ? const DeviceListPage() : const SettingsPage();

    final destinations = const [
      NavigationDestination(
        icon: Icon(Icons.radar_outlined),
        selectedIcon: Icon(Icons.radar),
        label: '设备发现',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置',
      ),
    ];

    // 桌面端：NavigationRail + 快捷键；移动端：底部 NavigationBar。
    final Widget scaffold;
    if (desktop) {
      scaffold = Scaffold(
        appBar: AppBar(
          title: Text(_titles[_index]),
          centerTitle: false,
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              leading: const SizedBox(height: spacingX2),
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.radar_outlined),
                  selectedIcon: Icon(Icons.radar),
                  label: Text('设备发现'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('设置'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    } else {
      scaffold = Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: destinations,
        ),
      );
    }

    // 桌面端：NavigationRail + AppBar；移动端：底部 NavigationBar。
    return scaffold;
  }
}

/// 字体包下载进度浮层：随 [FontManager.isDownloading] 状态**淡入淡出**。
///
/// - 未下载：完全透明、不拦截任何手势；
/// - 开始下载：淡入，显示 进度条 + 百分比 + 已下载/总大小；
/// - 下载结束：淡出后不可见（控件仍驻留以保证退场动画完整播放）。
class _FontDownloadOverlay extends StatelessWidget {
  const _FontDownloadOverlay();

  @override
  Widget build(BuildContext context) {
    final mgr = FontManager();
    return AnimatedBuilder(
      animation: mgr,
      builder: (context, _) {
        final downloading = mgr.isDownloading;
        final hasProgress = mgr.downloadProgress >= 0;
        final p = mgr.downloadProgress;

        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: IgnorePointer(
              ignoring: !downloading,
              child: AnimatedOpacity(
                opacity: downloading ? 1 : 0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _FontProgressCard(
                    hasProgress: hasProgress,
                    progress: p,
                    label: mgr.formatProgressLabel(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 进度卡片主体。
class _FontProgressCard extends StatelessWidget {
  const _FontProgressCard({
    required this.hasProgress,
    required this.progress,
    required this.label,
  });

  final bool hasProgress;
  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = hasProgress ? progress.clamp(0.0, 1.0).toDouble() : null;
    final pct = value == null ? null : (value * 100).round();

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.downloading, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('正在下载中文字体…',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pct == null
                    ? (label.isEmpty ? '准备中…' : '已下载 $label')
                    : '$pct%  ·  $label',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}