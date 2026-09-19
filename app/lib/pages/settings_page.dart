import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/harmony_font_loader.dart';
import '../services/settings_controller.dart';
import 'about_page.dart';

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

/// 网格内容边距（桌面更宽，让设置面板更像 Google 系应用）。
const double _kScreenMargin = 24;
const double _kPanelMaxWidth = 720;

/// 主题设置页：主题模式、自定义种子色、动态颜色开关。
///
/// 采用 MD3 设置面板样式（参考 Google 系应用）：
/// - 分组圆角卡片（[Card] + ListTile）承载每一项设置；
/// - 分组标题用 labelLarge 主色；
/// - 每项之间用细分隔线，末尾随语义隐藏。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kPanelMaxWidth),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: _kScreenMargin,
              vertical: 8,
            ),
            children: const [
              _SectionHeader('外观'),
              _ThemeModeCard(),
              SizedBox(height: 12),
              _DynamicColorCard(),
              SizedBox(height: 24),
              _SectionHeader('字体'),
              _FontChoiceCard(),
              SizedBox(height: 24),
              _SectionHeader('关于'),
              _AboutCard(),
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组标题（MD3 settings subheader）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 分组卡片容器。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final divider = Divider(
      height: 1,
      thickness: 1,
      indent: 72,
      color: scheme.outlineVariant.withValues(alpha: 0.4),
    );
    final widgets = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      widgets.add(children[i]);
      if (i != children.length - 1) {
        widgets.add(divider);
      }
    }
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: widgets),
    );
  }
}

/// 主题模式：Light / Dark / System，用 MD3 SegmentedButton 内嵌呈现。
class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsController(),
      builder: (context, _) {
        final settings = SettingsController();
        return _SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SegmentedButton<ThemeMode>(
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
                showSelectedIcon: true,
                onSelectionChanged: (selection) =>
                    settings.setThemeMode(selection.first),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.palette_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '自定义主题色',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            _ColorGrid(settings: settings),
          ],
        );
      },
    );
  }
}

/// 主题色色板网格（允许自定义种子色）。
class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
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
    );
  }
}

/// 动态颜色开关。
class _DynamicColorCard extends StatelessWidget {
  const _DynamicColorCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsController(),
      builder: (context, _) {
        final settings = SettingsController();
        final bool isAndroid = Platform.isAndroid;
        return _SettingsGroup(
          children: [
            SwitchListTile(
              value: settings.dynamicColorEnabled,
              onChanged: settings.setDynamicColorEnabled,
              title: const Text('开启动态颜色'),
              subtitle: Text(
                isAndroid ? '从系统壁纸汲取 Material You 配色' : '从系统强调色汲取主题配色',
              ),
              secondary: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.wallpaper,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  size: 22,
                ),
              ),
            ),
          ],
        );
      },
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: scheme.onSurface, width: 3)
              : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
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

/// 字体来源设置：系统字体 / HarmonyOS 字体 / 自定义字体文件。
class _FontChoiceCard extends StatelessWidget {
  const _FontChoiceCard();

  /// 通过文件选择器挑选中文字体文件并加载应用。
  Future<void> _pickCustomFont(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final settings = SettingsController();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf', 'ttc'],
      allowMultiple: false,
      dialogTitle: '选择中文字体文件',
    );
    if (result == null) return; // 用户取消
    final path = result.files.single.path;
    if (path == null || path.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('无法读取所选字体文件路径')),
      );
      return;
    }
    final ok = await FontManager().loadCustomFont(path);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('字体加载失败，请确认是有效的 TTF/OTF 文件')),
      );
      return;
    }
    await settings.setFontChoice(FontChoice.custom);
    messenger.showSnackBar(
      const SnackBar(content: Text('自定义字体已应用')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([SettingsController(), FontManager()]),
      builder: (context, _) {
        final settings = SettingsController();
        final mgr = FontManager();
        final choice = settings.fontChoice;
        final customLoaded = mgr.customFontFamily != null;
        final customPath = settings.customFontPath;

        return RadioGroup<FontChoice>(
          groupValue: choice,
          onChanged: (v) {
            if (v != null) settings.setFontChoice(v);
          },
          child: _SettingsGroup(
            children: [
              _FontRadioTile(
                value: FontChoice.system,
                isSelected: choice == FontChoice.system,
                onTap: () => settings.setFontChoice(FontChoice.system),
                icon: Icons.language,
                title: '系统字体',
                subtitle: '使用系统默认字体，不额外加载',
              ),
              const Divider(height: 1, indent: 72),
              _FontRadioTile(
                value: FontChoice.harmony,
                isSelected: choice == FontChoice.harmony,
                onTap: () {
                  settings.setFontChoice(FontChoice.harmony);
                  // 即时加载：运行中切到 HarmonyOS 也会立刻加载/应用，无需重启。
                  FontManager().ensureLoaded();
                },
                icon: Icons.font_download_outlined,
                title: 'HarmonyOS 字体',
                subtitle: mgr.isReady
                    ? '已安装（系统缺中文字体时自动下载）'
                    : '系统缺中文字体时自动下载',
              ),
              const Divider(height: 1, indent: 72),
              _FontRadioTile(
                value: FontChoice.custom,
                isSelected: choice == FontChoice.custom,
                onTap: () => _pickCustomFont(context),
                icon: Icons.insert_drive_file_outlined,
                title: '自定义字体',
                subtitle: customLoaded
                    ? '已应用所选字体'
                    : (customPath.isEmpty ? '选择本地 TTF/OTF 文件' : '字体文件待重新加载'),
              ),
              if (choice == FontChoice.custom && customPath.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          customPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个字体来源选项行（选中态由 [RadioGroup] 祖先管理）。
class _FontRadioTile extends StatelessWidget {
  const _FontRadioTile({
    required this.value,
    required this.isSelected,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final FontChoice value;
  final bool isSelected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap != null
          ? ChoiceChip(
              label: const Text('选择文件'),
              selected: isSelected,
              onSelected: (_) => onTap?.call(),
            )
          : Radio<FontChoice>(value: value),
      onTap: onTap,
    );
  }
}

/// 关于入口：跳转到包含可点击版本号（连击解锁）的关于界面。
class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return _SettingsGroup(
      children: [
        ListTile(
          leading: Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: const Text('关于'),
          subtitle: const Text('版本信息与开发者选项'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AboutPage()),
          ),
        ),
      ],
    );
  }
}