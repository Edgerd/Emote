import 'dart:io';

import 'package:flutter/material.dart';

import '../services/settings_controller.dart';
import '../theme/app_theme.dart';

/// 预设色板：可用于自定义种子色的可选颜色。
const List<Color> kPresetSeedColors = [
  Color(0xFF6750A4), // M3 基准紫
  Color(0xFF0061A4), // 蓝
  Color(0xFF00696B), // 青
  Color(0xFF006D3A), // 绿
  Color(0xFF8C4E00), // 橙
  Color(0xFFB3261E), // 红
  Color(0xFF7D5260), // 粉
  Color(0xFF625B71), // 灰紫
  Color(0xFF0B57D0), // 亮蓝
  Color(0xFF224C00), // 深绿
];

/// 主题设置页：主题模式、自定义种子色、动态颜色开关。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsController();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(spacingX3),
        children: [
          _SectionTitle(title: '外观'),
          SizedBox(height: spacingX2),

          // 主题模式：Light / Dark / System
          _SettingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: spacingX2),
                ListenableBuilder(
                  listenable: settings,
                  builder: (context, _) {
                    return SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('深色'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text('跟随系统'),
                        ),
                      ],
                      selected: {settings.mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          settings.setThemeMode(selection.first),
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: spacingX2),

          // 自定义种子色
          _SettingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('自定义主题色', style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: spacingX1),
                Text(
                  '选取一种颜色作为主题种子色。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: spacingX2),
                ListenableBuilder(
                  listenable: settings,
                  builder: (context, _) {
                    return Wrap(
                      spacing: spacingX1,
                      runSpacing: spacingX1,
                      children: [
                        for (final color in kPresetSeedColors)
                          _ColorChip(
                            color: color,
                            selected: settings.seedColor == color,
                            onTap: () => settings.setSeedColor(color),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: spacingX2),

          // 动态颜色开关
          _SettingCard(
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) {
                final bool isAndroid = Platform.isAndroid;
                return SwitchListTile(
                  value: settings.dynamicColorEnabled,
                  onChanged: settings.setDynamicColorEnabled,
                  title: const Text('开启动态颜色'),
                  subtitle: Text(
                    isAndroid
                        ? '从系统壁纸汲取 Material You 配色。'
                        : '从系统强调色汲取主题配色。',
                  ),
                  secondary: const Icon(Icons.palette_outlined),
                );
              },
            ),
          ),
          SizedBox(height: spacingX4),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(spacingX3),
        child: child,
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : null,
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}