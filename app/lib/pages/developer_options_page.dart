import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_log.dart';
import '../services/harmony_font_loader.dart';
import 'log_viewer_page.dart';

/// 开发者选项页：程序运行日志与若干调试功能。
class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('开发者选项')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: const [
              _SectionTitle('日志'),
              _LogGroup(),
              SizedBox(height: 24),
              _SectionTitle('调试功能'),
              _DebugGroup(),
              SizedBox(height: 24),
              _SectionTitle('应用信息'),
              _AppInfoCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
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

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _LogGroup extends StatelessWidget {
  const _LogGroup();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLog(),
      builder: (context, _) {
        final count = AppLog().entries.length;
        return _Group(children: [
          _GroupTile(
            icon: Icons.receipt_long_outlined,
            title: '程序运行日志',
            subtitle: count == 0 ? '暂无日志' : '已记录 $count 条',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogViewerPage()),
            ),
          ),
        ]);
      },
    );
  }
}

class _DebugGroup extends StatelessWidget {
  const _DebugGroup();

  Future<void> _resetFontCache(BuildContext context) async {
    final log = AppLog();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置字体缓存'),
        content: const Text(
          '将删除已下载的 HarmonyOS 字体与自定义字体副本，下次启动时按需重新下载。确定继续？',
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
    await FontManager().resetFontCache();
    log.info('字体', '已重置字体缓存');
    messenger.showSnackBar(
      const SnackBar(content: Text('字体缓存已重置，重启后生效')),
    );
  }

  Future<void> _showFontDir(BuildContext context) async {
    final log = AppLog();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await FontManager().fontCacheDirPath();
      log.info('字体', '缓存目录：$path');
      messenger.showSnackBar(
        SnackBar(content: Text('字体缓存目录：$path')),
      );
    } catch (e) {
      log.error('字体', '读取缓存目录失败：$e');
      messenger
          .showSnackBar(const SnackBar(content: Text('读取目录失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Group(children: [
      _GroupTile(
        icon: Icons.refresh,
        title: '重置字体缓存',
        subtitle: '删除已下载字体，重启后重新下载',
        onTap: () => _resetFontCache(context),
      ),
      _GroupTile(
        icon: Icons.folder_outlined,
        title: '字体缓存目录',
        subtitle: '查看 HarmonyOS 字体下载位置',
        onTap: () => _showFontDir(context),
      ),
    ]);
  }
}

class _AppInfoCard extends StatelessWidget {
  const _AppInfoCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final info = snap.data;
        return _Group(children: [
          _GroupTile(
            icon: Icons.api_outlined,
            title: '版本',
            trailing: Text(info == null ? '…' : '${info.version}+${info.buildNumber}'),
          ),
          _GroupTile(
            icon: Icons.memory_outlined,
            title: '构建号 / 渠道',
            trailing: Text(info?.buildNumber ?? '…'),
          ),
          _GroupTile(
            icon: Icons.format_paint_outlined,
            title: '当前主题',
            trailing: Text(_themeLabel(Theme.of(context).brightness)),
          ),
        ]);
      },
    );
  }

  static String _themeLabel(Brightness b) =>
      b == Brightness.dark ? '深色' : '浅色';
}