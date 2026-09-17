import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connection_service.dart';
import '../src/rust/protocol/message.dart';
import '../src/rust/protocol/types.dart';
import '../src/rust/transport.dart';
import '../theme/app_theme.dart';

/// 连接状态与心跳页（第 2.6 段）：展示指定设备的连接状态、生效传输层与心跳监控。
///
/// 由 [DeviceListPage] 点击设备进入。页面通过 `Timer` + [ConnectionService] 轮询
/// 连接状态/传输层，并统计心跳相关读数（此处为客户端视角的保活占位）。
class ConnectionStatusPage extends StatefulWidget {
  const ConnectionStatusPage({super.key, required this.device});

  final DeviceInfo device;

  @override
  State<ConnectionStatusPage> createState() => _ConnectionStatusPageState();
}

class _ConnectionStatusPageState extends State<ConnectionStatusPage> {
  final ConnectionService _connections = ConnectionService();

  // 心跳监控读数（客户端视角）。
  int _heartbeatsSent = 0;
  int _heartbeatsReceived = 0;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();

    // 若尚未经设备列表发起连接，这里兜底建立一次连接。
    if (!_isTracked() && _connections.handle != null) {
      _connections.connect(widget.device);
    }

    // 每秒一次的心跳点数（配合 ConnectionService 轮询，形成“实时”状态页）。
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (_connections.isConnected(widget.device.id)) {
          setState(() => _heartbeatsSent++);
          _heartbeatsReceived++;
        } else {
          // 未连接时静止计数，便于观察断线。
        }
      },
    );
  }

  bool _isTracked() => _connections.stateOf(widget.device.id) != null;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name.isEmpty ? '连接状态' : widget.device.name),
      ),
      body: ListenableBuilder(
        listenable: _connections,
        builder: (context, _) {
          final state = _connections.stateOf(widget.device.id);
          final transport = _connections.transportOf(widget.device.id);
          final connected = state == ConnectionState.connected;

          return ListView(
            padding: const EdgeInsets.all(spacingX3),
            children: [
              _buildStatusCard(context, state, transport),
              const SizedBox(height: spacingX3),
              _buildDetailCard(context),
              const SizedBox(height: spacingX3),
              _buildHeartbeatCard(context, connected),
              const SizedBox(height: spacingX3),
              _buildActions(context, state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    ConnectionState? state,
    ActiveTransport? transport,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final s = state ?? ConnectionState.disconnected;

    final (label, icon, color) = switch (s) {
      ConnectionState.connected => (
          '已连接',
          Icons.link,
          scheme.tertiaryContainer,
        ),
      ConnectionState.connecting ||
      ConnectionState.reconnecting => (
          '连接中',
          Icons.hourglass_top,
          scheme.secondaryContainer,
        ),
      ConnectionState.error => (
          '连接错误',
          Icons.error_outline,
          scheme.errorContainer,
        ),
      ConnectionState.disconnected => (
          '未连接',
          Icons.link_off,
          scheme.surfaceContainerHighest,
        ),
    };

    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(spacingX3),
        child: Row(
          children: [
            Icon(icon, size: 36, color: scheme.onSurface),
            const SizedBox(width: spacingX3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  transport == null
                      ? '尚未建立有效链路'
                      : '生效传输层：${_transportLabel(transport)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = widget.device;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(spacingX3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设备信息', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: spacingX2),
            _InfoRow(label: '名称', value: device.name),
            _InfoRow(label: '系统', value: _systemLabel(device.system)),
            _InfoRow(label: 'IP 地址', value: device.ip),
            _InfoRow(label: '协议版本', value: device.protocolVersion),
            _InfoRow(label: 'QUIC 端口', value: '${device.quicPort}'),
            _InfoRow(label: 'TCP 端口', value: '${device.tcpPort}'),
            _InfoRow(
              label: '传输能力',
              value: device.supportedTransports
                  .map(_transportLabelFor)
                  .join(', '),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeartbeatCard(BuildContext context, bool connected) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(spacingX3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('心跳监控', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                _LiveDot(connected: connected),
              ],
            ),
            const SizedBox(height: spacingX2),
            _HeartbeatRow(
              label: '已发送',
              value: '$_heartbeatsSent',
              icon: Icons.outbound,
            ),
            const SizedBox(height: spacingX1),
            _HeartbeatRow(
              label: '已接收',
              value: '$_heartbeatsReceived',
              icon: Icons.inbound,
            ),
            const SizedBox(height: spacingX1),
            _HeartbeatRow(
              label: '心跳间隔',
              value: '3s',
              icon: Icons.schedule,
            ),
            const SizedBox(height: spacingX1),
            _HeartbeatRow(
              label: '超时阈值',
              value: '10s',
              icon: Icons.timer_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, ConnectionState? state) {
    final connected = state == ConnectionState.connected;

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: connected
                ? () => _connections.disconnect(widget.device.id)
                : () => _connections.connect(widget.device),
            icon: Icon(connected ? Icons.link_off : Icons.lan_outlined),
            label: Text(connected ? '断开连接' : '连接 / 重连'),
          ),
        ),
      ],
    );
  }

  static String _transportLabel(ActiveTransport t) =>
      t == ActiveTransport.quic ? 'QUIC' : 'TCP';
  static String _transportLabelFor(Transport t) =>
      t == Transport.quic ? 'QUIC' : 'TCP';

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

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected
        ? Colors.green
        : Theme.of(context).colorScheme.outline;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(connected ? '在线' : '离线',
            style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _HeartbeatRow extends StatelessWidget {
  const _HeartbeatRow({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: spacingX1),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}