import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'package:emote/src/rust/frb_generated.dart';

import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'services/settings_controller.dart';
import 'theme/app_theme.dart';
import 'theme/dynamic_color.dart';
import 'theme/window_size_class.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 Dart ↔ Rust 桥接（flutter_rust_bridge）。
  await RustLib.init();
  // 从本地存储加载主题设置（模式 / 种子色 / 动态颜色）。
  await SettingsController().load();
  runApp(const EmoteApp());
}

class EmoteApp extends StatelessWidget {
  const EmoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsController();

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        // Android：用 DynamicColorBuilder 从系统壁纸异步汲取 Material You 色板。
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final ColorScheme? dynamicScheme =
                settings.dynamicColorEnabled ? (lightDynamic ?? darkDynamic) : null;

            return MaterialApp(
              title: 'Emote',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(PlatformAccent.resolve(
                brightness: Brightness.light,
                dynamicScheme: dynamicScheme,
                fallbackSeed: settings.seedColor,
              )),
              darkTheme: AppTheme.build(PlatformAccent.resolve(
                brightness: Brightness.dark,
                dynamicScheme: dynamicScheme,
                fallbackSeed: settings.seedColor,
              )),
              themeMode: settings.mode,
              home: const AppShell(),
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

    final body = _index == 0 ? const HomePage() : const SettingsPage();

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