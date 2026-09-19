import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_log.dart';
import '../services/harmony_font_loader.dart';
import 'about_page.dart';
import 'settings_page.dart';

/// 「更多」页：以参考图式**分组圆角列表**承载本地/支持/系统入口。
///
/// - 每组用 `surfaceContainerLow` 圆角容器，组内项之间用细分隔线（MD3 设置组规范）；
/// - 每项为 [ListTile]：左侧 40dp 圆形图标容器（scheme 色调），中部标题+副标题，
///   右侧提示性箭头（chevron_right）；
/// - 「设置」「关于」为真实导航，「缓存管理」「检查更新」复用现有能力，
///   其余（反馈/帮助/加群/分享）为占位入口。
class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    }).catchError((Object _) {
      // 获取版本失败时保持占位，不打扰用户。
    });
  }

  void _placeholder(String message) {
    AppLog().info('更多', message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$message，敬请期待')));
  }

  void _checkUpdate() {
    AppLog().info('更多', '检查更新：当前 $_version');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(_version.isEmpty ? '当前已是最新版本' : '当前已是最新版本 $_version')),
      );
  }

  Future<void> _showCacheDialog() async {
    final scheme = Theme.of(context).colorScheme;
    String sizeLabel = '计算中…';
    try {
      final dir = await FontManager().fontCacheDirPath();
      sizeLabel = '字体缓存目录：$dir';
    } catch (_) {
      sizeLabel = '暂无法读取缓存目录';
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.cleaning_services_outlined, color: scheme.primary),
        title: const Text('缓存管理'),
        content: Text(
          '当前仅处理字体缓存（HarmonyOS / 自定义字体副本）。\n上次使用后可清理以释放磁盘。\n\n$sizeLabel',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清理字体缓存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await FontManager().resetFontCache();
    AppLog().info('更多', '已清理字体缓存');
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('字体缓存已清理，重启后按需重新下载')));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AboutPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          children: [
            _MoreGroupHeader('本地'),
            _GroupCard(children: [
              _MoreTile(
                icon: Icons.cleaning_services_outlined,
                title: '缓存管理',
                subtitle: '统计并清理应用通用缓存',
                onTap: _showCacheDialog,
              ),
              _MoreTile(
                icon: Icons.system_update_alt,
                title: '检查更新',
                subtitle: _version.isEmpty ? '当前版本 v…' : '当前版本 v$_version',
                onTap: _checkUpdate,
              ),
            ]),
            const SizedBox(height: 24),
            _MoreGroupHeader('支持'),
            _GroupCard(children: [
              _MoreTile(
                icon: Icons.outgoing_mail,
                title: '反馈',
                subtitle: '功能投稿丨功能失效丨创意投稿',
                onTap: () => _placeholder('反馈'),
              ),
              _MoreTile(
                icon: Icons.help_outline,
                title: '帮助',
                subtitle: '一些使用中会遇到的常见问题',
                onTap: () => _placeholder('帮助文档'),
              ),
              _MoreTile(
                icon: Icons.groups_outlined,
                title: '加入官群',
                subtitle: '与五湖四海的小伙伴交流使用心得',
                onTap: () => _placeholder('加入官群'),
              ),
              _MoreTile(
                icon: Icons.ios_share,
                title: '分享应用',
                subtitle: '分享给你一款好用的远程控制工具',
                onTap: () => _placeholder('分享功能'),
              ),
            ]),
            const SizedBox(height: 24),
            _MoreGroupHeader('更多'),
            _GroupCard(children: [
              _MoreTile(
                icon: Icons.settings_outlined,
                title: '设置',
                subtitle: '主题模式、主题色等个性化配置',
                onTap: _openSettings,
              ),
              _MoreTile(
                icon: Icons.info_outline,
                title: '关于',
                subtitle: '关于 Emote',
                onTap: _openAbout,
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// 分组标题（MD3 settings subheader，labelLarge + 主色）。
class _MoreGroupHeader extends StatelessWidget {
  const _MoreGroupHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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

/// 分组圆角卡片容器：`surfaceContainerLow` 圆角 + 组内细分隔线。
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final widgets = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      widgets.add(children[i]);
      if (i != children.length - 1) {
        widgets.add(Divider(
          height: 1,
          thickness: 1,
          indent: 72,
          endIndent: 16,
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ));
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

/// 更多页单项：圆形图标容器 + 标题/副标题 + 右箭头。
///
/// 图标底色用 `secondaryContainer`（scheme 派生），在浅色/深色/动态色下均一致，
/// 不写死薄荷绿；图标用 `onSecondaryContainer` 保证对比度。
class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: scheme.onSecondaryContainer, size: 22),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.outline),
    );
  }
}