import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/app_log.dart';
import '../services/dev_settings_controller.dart';
import '../services/harmony_font_loader.dart';
import '../services/settings_controller.dart';

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
              _SectionHeader('个性化'),
              _PersonalizationCard(),
              SizedBox(height: 24),
              _SectionHeader('系统'),
              _ResetCard(),
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

  /// 批量挑选中文字体文件（可多选）→ 自动推断字重分派到 4 槽位 →
  /// 弹出预览确认框，让用户核对/调整后正式应用。
  Future<void> _pickCustomFonts(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf', 'ttc'],
      allowMultiple: true,
      dialogTitle: '选择中文字体文件（可多选，按字重区分）',
    );
    if (result == null) return; // 用户取消
    final paths = result.files
        .map((f) => f.path ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('无法读取所选字体文件路径')),
      );
      return;
    }
    // 文件选择跨异步间隙，先确保 context 仍有效再使用。
    if (!context.mounted) return;
    // 先按文件名自动推断字重、分派到 4 槽位（regular/medium/bold/black）。
    final slots = FontManager().autoAssignRoles(paths);
    final previewFamily = 'EmoteCustomFont_Preview_${DateTime.now().microsecond}';
    await _showCustomFontConfirm(
      context,
      sourcePaths: paths,
      initialSlots: slots,
      previewFamily: previewFamily,
    );
  }

  /// 预览确认框：注册临时预览族、展示样例、允许调整 4 槽位归属，确认后正式应用。
  Future<void> _showCustomFontConfirm(
    BuildContext context, {
    required List<String> sourcePaths,
    required List<String> initialSlots,
    required String previewFamily,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final applied = await showGeneralDialog<List<String>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '确认自定义字体',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => _CustomFontConfirmDialog(
        sourcePaths: sourcePaths,
        initialSlots: initialSlots,
        previewFamily: previewFamily,
      ),
    );
    if (applied == null) return; // 用户取消，不做任何改动
    final settings = SettingsController();
    final ok = await FontManager().loadCustomFontSlots(applied);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('字体加载失败，请确认是有效的 TTF/OTF 文件')),
      );
      return;
    }
    await settings.setFontChoice(FontChoice.custom);
    messenger.showSnackBar(
      const SnackBar(content: Text('自定义字体（多字重）已应用')),
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
                onTap: () => _pickCustomFonts(context),
                icon: Icons.insert_drive_file_outlined,
                title: '自定义字体',
                subtitle: customLoaded
                    ? '已应用所选字体'
                    : '选择本地 TTF/OTF 文件（可多选按字重区分）',
                chipLabel: '选择字体',
              ),
              if (choice == FontChoice.custom &&
                  settings.customFontPaths.any((p) => p.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < 4; i++)
                        if (settings.customFontPaths[i].isNotEmpty)
                          Row(
                            key: ValueKey('slot-$i'),
                            children: [
                              Icon(Icons.folder_open,
                                  size: 16, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Text(
                                _slotRoleLabel(i),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: scheme.primary),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _baseName(settings.customFontPaths[i]),
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
    this.chipLabel = '选择文件',
  });

  final FontChoice value;
  final bool isSelected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// 选择类选项的行尾按钮文案（默认「选择文件」；自定义字体为「选择字体」）。
  final String chipLabel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap != null
          ? ChoiceChip(
              label: Text(chipLabel),
              selected: isSelected,
              onSelected: (_) => onTap?.call(),
            )
          : Radio<FontChoice>(value: value),
      onTap: onTap,
    );
  }
}

/// 4 槽位（regular/medium/bold/black）的本地化角色标签。
String _slotRoleLabel(int index) {
  switch (index) {
    case 0:
      return 'Regular';
    case 1:
      return 'Medium';
    case 2:
      return 'Bold';
    default:
      return 'Black';
  }
}

/// 取文件路径末段（去目录与扩展名）作为展示名。
String _baseName(String path) {
  final last = path.split(Platform.pathSeparator).last;
  final dot = last.lastIndexOf('.');
  return dot > 0 ? last.substring(0, dot) : last;
}

/// 自定义字体「多字重预览确认」对话框。
///
/// 先用临时预览族渲染样例文本（不影响正式族 [FontManager.kCustomFamily]），
/// 让用户核对/调整 4 槽位（regular/medium/bold/black）各自的字体文件归属；
/// 确认后返回 4 槽位路径数组（按 [FontRole] 顺序），取消返回 null。
class _CustomFontConfirmDialog extends StatefulWidget {
  const _CustomFontConfirmDialog({
    required this.sourcePaths,
    required this.initialSlots,
    required this.previewFamily,
  });

  /// 用户本次挑选到的源文件路径集合（用于槽位下拉选择）。
  final List<String> sourcePaths;

  /// [FontManager.autoAssignRoles] 自动推断得到的初始 4 槽位分配。
  final List<String> initialSlots;

  /// 临时预览族名（与正式族分离，避免预览期误写正式字体）。
  final String previewFamily;

  @override
  State<_CustomFontConfirmDialog> createState() => _CustomFontConfirmDialogState();
}

class _CustomFontConfirmDialogState extends State<_CustomFontConfirmDialog> {
  late List<String> _slots;
  bool _previewReady = false;

  @override
  void initState() {
    super.initState();
    _slots = [
      for (var i = 0; i < 4; i++)
        (i < widget.initialSlots.length && widget.initialSlots[i].isNotEmpty)
            ? widget.initialSlots[i]
            : '',
    ];
    // 注册临时预览族（失败不影响对话框使用）。
    FontManager().loadCustomFontPreview(
      widget.initialSlots.where((s) => s.isNotEmpty).toList(),
      widget.previewFamily,
    ).then((_) {
      if (mounted) setState(() => _previewReady = true);
    });
  }

  void _setSlot(int index, String path) {
    setState(() {
      _slots[index] = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 样例文本用预览族渲染，直观对比各字重效果。
    final previewFamily = widget.previewFamily;

    return Dialog(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('应用自定义字体（多字重）',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // 预览区：用临时预览族渲染样例，字重从 Regular 到 Black。
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var w = 0; w < 4; w++)
                    Text(
                      '汉水相融 · 字重 ${_slotRoleLabel(w)}',
                      style: TextStyle(
                        fontFamily: _previewReady ? previewFamily : null,
                        fontWeight: [
                          FontWeight.w400,
                          FontWeight.w500,
                          FontWeight.w700,
                          FontWeight.w900
                        ][w],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 4 槽位归属调整（下拉选择本批次文件，或留空）。
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        _slotRoleLabel(i),
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: scheme.primary),
                      ),
                    ),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _slots[i],
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text('（不使用）'),
                          ),
                          for (final p in widget.sourcePaths)
                            DropdownMenuItem<String>(
                              value: p,
                              child: Text(_baseName(p),
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => _setSlot(i, v ?? ''),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    // 至少要有一个槽位非空才允许应用。
                    if (!_slots.any((s) => s.isNotEmpty)) {
                      return;
                    }
                    Navigator.of(context).pop(_slots);
                  },
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 个性化设置：减少动画、内容显示密度、默认传输层。
class _PersonalizationCard extends StatelessWidget {
  const _PersonalizationCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsController(),
      builder: (context, _) {
        final settings = SettingsController();
        return _SettingsGroup(
          children: [
            SwitchListTile(
              value: settings.reduceMotion,
              onChanged: settings.setReduceMotion,
              title: const Text('减少动画'),
              subtitle: const Text('弱化界面转场与隐式动画（无障碍）'),
              secondary: const _IconBox(Icons.animation),
            ),
            const Divider(height: 1, indent: 72),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const _IconBox(Icons.density_small),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('内容显示密度',
                            style: Theme.of(context).textTheme.bodyLarge),
                        Text('宽松 / 紧凑',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 8, 16, 4),
              child: SegmentedButton<ContentDensity>(
                segments: const [
                  ButtonSegment(
                    value: ContentDensity.comfortable,
                    label: Text('宽松'),
                  ),
                  ButtonSegment(
                    value: ContentDensity.compact,
                    label: Text('紧凑'),
                  ),
                ],
                selected: {settings.contentDensity},
                showSelectedIcon: true,
                onSelectionChanged: (s) =>
                    settings.setContentDensity(s.first),
              ),
            ),
            const Divider(height: 1, indent: 72),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const _IconBox(Icons.swap_vert),
                  const SizedBox(width: 16),
                  Text('默认传输层',
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SegmentedButton<TransportPref>(
                segments: const [
                  ButtonSegment(
                    value: TransportPref.auto,
                    label: Text('自动'),
                  ),
                  ButtonSegment(
                    value: TransportPref.quic,
                    label: Text('QUIC'),
                  ),
                  ButtonSegment(
                    value: TransportPref.tcp,
                    label: Text('TCP'),
                  ),
                ],
                selected: {settings.transportPref},
                showSelectedIcon: true,
                onSelectionChanged: (s) =>
                    settings.setTransportPref(s.first),
              ),
            ),
            const Divider(height: 1, indent: 72),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
              title: const Text('纯局域网模式'),
              subtitle: const Text(
                  '禁止任何公网下载（含 HarmonyOS 字体包），仅使用系统默认字体'),
              secondary: const Icon(Icons.cloud_off_outlined),
              value: settings.lanOnly,
              onChanged: (v) => settings.setLanOnly(v),
            ),
          ],
        );
      },
    );
  }
}

/// 设定项旁的方形图标容器（MD3 secondaryContainer 弱对比）。
class _IconBox extends StatelessWidget {
  const _IconBox(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: scheme.onSecondaryContainer, size: 22),
    );
  }
}

/// 重置全部设置（确认弹窗后复位主题/字体/个性化/开发者模式与字体缓存）。
class _ResetCard extends StatelessWidget {
  const _ResetCard();

  Future<void> _confirmReset(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置全部设置'),
        content: const Text(
          '将恢复默认主题、字体来源、个性化设置，并清除开发者模式与字体缓存。重启后按需重新下载字体。确定继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await SettingsController().resetAll();
    await DevSettingsController().setDeveloperMode(false);
    await FontManager().resetFontCache();
    AppLog().info('设置', '已重置全部设置');
    messenger.showSnackBar(
      const SnackBar(content: Text('已重置全部设置，重启后完全生效')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SettingsGroup(
      children: [
        ListTile(
          leading: Icon(Icons.restart_alt,
              color: scheme.onSurfaceVariant),
          title: const Text('重置全部设置'),
          subtitle: const Text('恢复默认主题 / 字体 / 个性化，清除缓存'),
          onTap: () => _confirmReset(context),
        ),
      ],
    );
  }
}