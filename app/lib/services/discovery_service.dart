import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../src/rust/api/discovery.dart';
import '../src/rust/protocol/types.dart';
import 'android_connectivity.dart';

/// 设备发现服务（第 2.4 段）：封装 Rust `DiscoveryHandle` 的 FFI 调用。
///
/// - 启动后同时打开 mDNS 广播（让本机被发现）与浏览（发现局域网设备）；
/// - 用定时器轮询 Rust 侧的共享缓存/状态，刷新设备列表与发现状态；
/// - 对外通过 `ChangeNotifier` 通知 UI 刷新。
class DiscoveryService extends ChangeNotifier {
  DiscoveryService._();
  factory DiscoveryService() => _instance;

  static final DiscoveryService _instance = DiscoveryService._();

  static const String kProtocolVersion = '1.0.0';

  /// 广播/连接使用的默认端口（本 MVP 暂无真正的服务端监听，仅作发现信息公布）。
  static const int kDefaultQuicPort = 5201;
  static const int kDefaultTcpPort = 5202;

  DiscoveryHandle? _handle;
  List<DeviceInfo> _devices = const [];
  DiscoveryState _state = DiscoveryState.stopped;
  String? _error;
  Timer? _timer;
  int _pollIntervalMs = 2000;
  bool _multicastEnabled = false;

  DiscoveryHandle? get handle => _handle;
  List<DeviceInfo> get devices => _devices;
  DiscoveryState get state => _state;
  bool get running => _state == DiscoveryState.running;
  String? get error => _error;

  /// Android 上是否成功获取 MulticastLock（mDNS 可用的前置条件）。
  bool get multicastEnabled => _multicastEnabled;

  /// 启动发现：先建 handle，再开广播与浏览，最后起轮询。
  Future<bool> start({
    required String deviceName,
    required DeviceSystem system,
    String? deviceId,
    String? hostIp,
    int quicPort = kDefaultQuicPort,
    int tcpPort = kDefaultTcpPort,
  }) async {
    if (_handle != null) {
      return true; // 已启动，幂等
    }
    try {
      // Android：mDNS 依赖 UDP 组播，先持有 MulticastLock 才能接收组播包。
      final multicastHeld = await AndroidConnectivity.acquireMulticastLock();
      _multicastEnabled = multicastHeld;
      final id = (deviceId == null || deviceId.isEmpty)
          ? generateDeviceId()
          : deviceId;
      final ip = hostIp ?? (await _detectLanHostIp()) ?? '127.0.0.1';

      final handle = await DiscoveryHandle.newInstance();
      await handle.startBroadcast(
        cfg: BroadcastConfig(
          id: id,
          name: deviceName.isEmpty ? _defaultName() : deviceName,
          system: system,
          quicPort: quicPort,
          tcpPort: tcpPort,
          preferredTransport: Transport.quic,
          protocolVersion: kProtocolVersion,
        ),
        hostIp: ip,
      );
      await handle.startBrowse();
      _handle = handle;
      await _refresh();
      _timer = Timer.periodic(
        Duration(milliseconds: _pollIntervalMs),
        (_) => _refresh(),
      );
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _state = DiscoveryState.error;
      notifyListeners();
      return false;
    }
  }

  /// 停止发现并释放资源。
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;

    final handle = _handle;
    _handle = null;
    _devices = const [];
    _state = DiscoveryState.stopped;

    if (handle != null) {
      try {
        await handle.stopBrowse();
        await handle.stopBroadcast();
      } catch (e) {
        debugPrint('DiscoveryService.stop() 忽略错误：$e');
      }
    }

    // Android：释放 mDNS 组播锁。
    await AndroidConnectivity.releaseMulticastLock();
    _multicastEnabled = false;
    notifyListeners();
  }

  Future<void> _refresh() async {
    final handle = _handle;
    if (handle == null) return;
    try {
      final devices = await handle.listDevices();
      final state = await handle.state();
      _devices = devices;
      _state = state;
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  /// 生成本机设备 ID（时间戳 + 随机后缀的轻量实现）。
  static String generateDeviceId() =>
      'emo-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}'
      '-${_randHex(6)}';

  static String _randHex(int len) {
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      buf.write((0xFF & (DateTime.now().microsecondsSinceEpoch >> (i * 4) ^ i))
          .toRadixString(16));
    }
    return buf.toString();
  }

  String _defaultName() =>
      '${Platform.operatingSystem}-${_shortHost(_hostName())}';

  String _hostName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'device';
    }
  }

  String _shortHost(String host) {
    final parts = host.split('.');
    return parts.isEmpty ? 'device' : parts.first;
  }

  /// 探测本机首选局域网 IPv4（跳过回环 / 链路本地）。
  static Future<String?> _detectLanHostIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('枚举本机网卡失败：$e');
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}