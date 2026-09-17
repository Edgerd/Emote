import 'dart:io';

import 'package:flutter/material.dart' hide ConnectionState;

import '../services/connection_service.dart';
import '../services/discovery_service.dart';
import '../src/rust/protocol/types.dart';
import '../theme/app_theme.dart';
import 'connection_status_page.dart';

/// 设备列表页（第 2.5 段）：展示已发现的局域网设备，可连接/断开并进入状态页。
///
/// 依赖 [DiscoveryService]（轮询设备列表）与 [ConnectionService]（连接管理），
/// 二者均通过 `ChangeNotifier` 驱动本页随状态刷新。
class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  final DiscoveryService _discovery = DiscoveryService();
  final ConnectionService _connections = ConnectionService();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _discovery.removeListener(_noop);
    super.dispose();
  }

  void _noop() {}

  /// 初始化连接服务并启动发现。
  Future<void> _bootstrap() async {
    await _connections.init();
    final started = await _discovery.start(
      deviceName: _hostLabel(),
      system: _currentSystem(),
    );
    if (!started && mounted) {
      // 启动失败时显示错误态（由页面 UI 依据 discovery.error 呈现）。
      debugPrint('设备发现启动失败');
    }
  }

  static String _hostLabel() {
    try {
      final host = Platform.localHostname.split('.').first;
      return host.isEmpty ? 'Emote' : host;
    } catch (_) {
      return 'Emote';
    }
  }

  static DeviceSystem _currentSystem() {
    if (Platform.isAndroid) return DeviceSystem.android;
    if (Platform.isWindows) return DeviceSystem.windows;
    if (Platform.isLinux) return DeviceSystem.linux;
    return DeviceSystem.unknown;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([_discovery, _connections]),
        builder: (context, _) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              if (_discovery.error != null)
                SliverToBoxAdapter(child: _buildErrorBanner(context)),
              ..._buildDeviceSlivers(context),
            ],
          );
        },
      ),
    );
  }

  /// 顶部：发现状态指示 + 启停按钮。
  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (stateLabel, stateIcon, stateColor) = _discoveryStateUi(
      _discovery.state,
      scheme,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(spacingX3, spacingX3, spacingX3, spacingX2),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: stateColor,
              shape: BoxShape.circle,
            ),
            child: Icon(stateIcon, color: scheme.onSurface, size: 22),
          ),
          const SizedBox(width: spacingX2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('局域网设备发现', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(stateLabel, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          IconButton(
            tooltip: _discovery.running ? '重新扫描' : '开始扫描',
            onPressed: () async {
              if (_discovery.running) {
                await _discovery.stop();
                await _discovery.start(
                  deviceName: _hostLabel(),
                  system: _currentSystem(),
                );
              } else {
                await _discovery.start(
                  deviceName: _hostLabel(),
                  system: _currentSystem(),
                );
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: spacingX3, vertical: spacingX1),
      child: Card(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(spacingX2),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: spacingX2),
              Expanded(
                child: Text(
                  _discovery.error ?? '未知错误',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDeviceSlivers(BuildContext context) {
    final devices = _discovery.devices;

    if (_discovery.error != null && devices.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text('发现启动失败，请检查网络权限。',
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ];
    }

    if (devices.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: _discovery.running
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: spacingX3),
                      Text('正在扫描局域网设备…',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: spacingX2),
                      Text('暂未发现设备', style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
          ),
        ),
      ];
    }

    final tiles = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: spacingX3),
        sliver: SliverToBoxAdapter(
          child: Text('已发现 ${devices.length} 台设备',
              style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(spacingX3, spacingX2, spacingX3, spacingX4),
        sliver: SliverList.separated(
          itemCount: devices.length,
          separatorBuilder: (_, _) => const SizedBox(height: spacingX2),
          itemBuilder: (context, index) => _DeviceCard(
            device: devices[index],
            connectionService: _connections,
            discoveryService: _discovery,
          ),
        ),
      ),
    ];
    return tiles;
  }

  /// 渲染发现状态对应的标签 / 图标 / 底色。
  static (String, IconData, Color) _discoveryStateUi(
    DiscoveryState state,
    ColorScheme scheme,
  ) {
    switch (state) {
      case DiscoveryState.running:
        return ('发现中（运行中）', Icons.radar, scheme.tertiaryContainer);
      case DiscoveryState.starting:
        return ('正在启动…', Icons.hourglass_top, scheme.secondaryContainer);
      case DiscoveryState.error:
        return ('发现出错', Icons.error_outline, scheme.errorContainer);
      case DiscoveryState.stopped:
        return ('未在扫描', Icons.radar, scheme.surfaceContainerHighest);
    }
  }
}

/// 单台设备卡片。
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.connectionService,
    required this.discoveryService,
  });

  final DeviceInfo device;
  final ConnectionService connectionService;
  final DiscoveryService discoveryService;

  @override
  Widget build(BuildContext context) {
    final connState = connectionService.stateOf(device.id);
    final connected = connState == ConnectionState.connected;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConnectionStatusPage(device: device),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(spacingX3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SystemIcon(system: device.system),
                  const SizedBox(width: spacingX2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.name.isEmpty ? '(未命名)' : device.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          '${device.ip} · ${_systemLabel(device.system)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(state: connState ?? ConnectionState.disconnected),
                ],
              ),
              const SizedBox(height: spacingX2),
              Wrap(
                spacing: spacingX1,
                runSpacing: spacingX1,
                children: [
                  for (final t in device.supportedTransports)
                    _TransportChip(transport: t),
                  _PortChip(label: 'QUIC ${device.quicPort}'),
                  _PortChip(label: 'TCP ${device.tcpPort}'),
                ],
              ),
              const SizedBox(height: spacingX2),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (connected)
                    OutlinedButton.icon(
                      onPressed: () =>
                          connectionService.disconnect(device.id),
                      icon: const Icon(Icons.link_off),
                      label: const Text('断开'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () async {
                        await connectionService.connect(device);
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ConnectionStatusPage(device: device),
                          ),
                        );
                      },
                      icon: const Icon(Icons.lan_outlined),
                      label: const Text('连接'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _systemLabel(DeviceSystem system) {
    switch (system) {
      case DeviceSystem.windows:
        return 'Windows';
      case DeviceSystem.linux:
        return 'Linux';
      case DeviceSystem.android:
        return 'Android';
      case DeviceSystem.unknown:
        return '未知系统';
    }
  }
}

class _SystemIcon extends StatelessWidget {
  const _SystemIcon({required this.system});
  final DeviceSystem system;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (system) {
      DeviceSystem.windows => (Icons.desktop_windows, Colors.lightBlue),
      DeviceSystem.linux => (Icons.terminal, Colors.orange),
      DeviceSystem.android => (Icons.smartphone, Colors.green),
      DeviceSystem.unknown => (Icons.device_unknown, Colors.grey),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// 连接状态徽章。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});
  final ConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (state) {
      ConnectionState.connected => (
          '已连接',
          Theme.of(context).colorScheme.tertiaryContainer,
          Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      ConnectionState.connecting ||
      ConnectionState.reconnecting => (
          '连接中',
          Theme.of(context).colorScheme.secondaryContainer,
          Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ConnectionState.error => (
          '错误',
          Theme.of(context).colorScheme.errorContainer,
          Theme.of(context).colorScheme.onErrorContainer,
        ),
      ConnectionState.disconnected => (
          '未连接',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12)),
    );
  }
}

class _TransportChip extends StatelessWidget {
  const _TransportChip({required this.transport});
  final Transport transport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        transport == Transport.quic ? 'QUIC' : 'TCP',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _PortChip extends StatelessWidget {
  const _PortChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.outline),
    );
  }
}