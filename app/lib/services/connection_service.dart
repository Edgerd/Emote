import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/connection.dart';
import '../src/rust/transport.dart';
import '../src/rust/protocol/message.dart';
import '../src/rust/protocol/types.dart';

/// 连接管理服务（第 2.4 段）：封装 Rust `ConnectionHandle` 的 FFI 调用。
///
/// - 对每台设备维护连接状态与当前生效传输层（QUIC 优先、TCP 回退）；
/// - 用定时器轮询 Rust 侧状态，实现 UI 层“实时”连接状态 / 心跳页面；
/// - 对外通过 `ChangeNotifier` 通知 UI 刷新。
class ConnectionService extends ChangeNotifier {
  ConnectionService._();
  factory ConnectionService() => _instance;

  static final ConnectionService _instance = ConnectionService._();

  ConnectionHandle? _handle;
  final Map<String, ConnectionState> _states = {};
  final Map<String, ActiveTransport?> _transports = {};
  Timer? _timer;
  final int _pollIntervalMs = 1000;
  bool _initialized = false;

  ConnectionHandle? get handle => _handle;
  bool get initialized => _initialized;

  /// 建立连接管理器（惰性创建，仅一次）。
  Future<void> init() async {
    if (_initialized && _handle != null) return;
    _handle = await ConnectionHandle.newInstance();
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: _pollIntervalMs),
      (_) => _pollAll(),
    );
    _initialized = true;
    notifyListeners();
  }

  /// 建立到设备的连接（QUIC 优先，TCP 回退），返回最终连接状态。
  Future<ConnectionState> connect(DeviceInfo dev) async {
    final handle = _handle ?? await _ensureHandle();
    final state = await handle.connect(dev: dev);
    _states[dev.id] = state;
    _transports[dev.id] = await handle.activeTransport(id: dev.id);
    notifyListeners();
    return state;
  }

  /// 断开指定设备连接。
  Future<void> disconnect(String id) async {
    final handle = _handle;
    if (handle != null) {
      try {
        await handle.disconnect(id: id);
      } catch (e) {
        debugPrint('ConnectionService.disconnect() 忽略错误：$e');
      }
    }
    _states[id] = ConnectionState.disconnected;
    _transports[id] = null;
    notifyListeners();
  }

  /// 向指定连接发送一帧控制消息。
  Future<void> sendControl(
    String id, {
    MessageType type = MessageType.control,
    List<int> payload = const [],
  }) async {
    final handle = _handle;
    if (handle == null) return;
    await handle.send(id: id, msgType: type, payload: payload);
  }

  ConnectionState? stateOf(String id) => _states[id];
  ActiveTransport? transportOf(String id) => _transports[id];
  bool isConnected(String id) => _states[id] == ConnectionState.connected;

  Future<ConnectionHandle> _ensureHandle() async {
    await init();
    return _handle!;
  }

  Future<void> _pollAll() async {
    final handle = _handle;
    if (handle == null) return;

    var changed = false;
    for (final id in _states.keys.toList()) {
      try {
        final s = await handle.state(id: id);
        final t = await handle.activeTransport(id: id);
        if (s != _states[id] || t != _transports[id]) {
          _states[id] = s;
          _transports[id] = t;
          changed = true;
        }
      } catch (e) {
        // 单设备查询失败不影响其他设备；记录后可续用旧值。
        debugPrint('轮询连接状态失败 ($id)：$e');
      }
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}