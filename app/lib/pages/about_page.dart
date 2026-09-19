import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_log.dart';
import '../services/dev_settings_controller.dart';
import 'developer_options_page.dart';

/// 关于界面。
///
/// 顶部展示应用图标、名称与「可点击的版本号」；连续点击版本号
/// [DevSettingsController.clickToUnlock] 次即解锁开发者模式（成功后直接进入
/// 开发者选项）。已解锁时版本条目下方会出现「开发者选项」入口。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  int _clicks = 0;
  String _version = '—';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    });
  }

  Future<void> _onVersionTap() async {
    final dev = DevSettingsController();
    final remaining = _clicks + 1 - DevSettingsController.clickToUnlock;
    if (remaining < 0) {
      setState(() => _clicks++);
      // 前 19 次：给出剩余提示，便于用户感知进度。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 400),
          content: Text('还有 ${-remaining} 次解锁开发者选项'),
        ),
      );
      return;
    }

    // 第 20 次：解锁并进入开发者选项。
    setState(() => _clicks = DevSettingsController.clickToUnlock);
    AppLog().info('关于', '已解锁开发者选项');
    await dev.setDeveloperMode(true);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeveloperOptionsPage()),
    );
  }

  Future<void> _openDevOptions() async {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeveloperOptionsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dev = DevSettingsController();
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: [
              _Header(clicks: _clicks),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerLow,
                child: ListenableBuilder(
                  listenable: dev,
                  builder: (context, _) => Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.tag),
                        title: const Text('版本'),
                        subtitle: Text(
                          dev.developerMode
                              ? '点击版本号可再次进入开发者选项'
                              : '点击版本号 ${DevSettingsController.clickToUnlock} 次可解锁开发者选项',
                        ),
                        trailing: Text(
                          'v$_version',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: _onVersionTap,
                      ),
                      if (dev.developerMode)
                        ListTile(
                          leading: Icon(Icons.developer_mode,
                              color: scheme.primary),
                          title: const Text('开发者选项'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _openDevOptions,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Emote 是一款面向纯局域网·跨平台远程控制软件，'
                '端到端在同一局域网内完成设备发现、连接与控制。',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 应用头：图标、名称与可点击版本号（实现 20 连击解锁）。
class _Header extends StatelessWidget {
  const _Header({required this.clicks});
  final int clicks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.lan_outlined,
              size: 48, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 16),
        Text(
          'Emote',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '局域网远程控制',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (clicks >= DevSettingsController.clickToUnlock)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Chip(
              label: const Text('开发者模式已解锁'),
              avatar: Icon(Icons.developer_mode,
                  size: 16, color: scheme.primary),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}