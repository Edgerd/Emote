import 'dart:async';

import 'package:flutter/foundation.dart';

// 以下生成文件由 `frb generate`（flutter_rust_bridge 2.13）产出，需在 Flutter 主机上运行后存在。
import '../src/rust/api/session.dart';
import '../src/rust/session.dart';

/// 远控会话服务（第 3.6 段）：封装 Rust `SessionHandle` 的 FFI 调用。
///
/// - 管理一个三方向会话（默认 `DesktopFrom`，本机合成源管线可离线演示）；
/// - 用定时器轮询拉取解码帧，经 `ChangeNotifier` 通知 UI（[RemoteView]）刷新；
/// - 提供输入下发（键/触摸/滚动），缺能力时 Rust 侧优雅降级，UI 不崩溃。
class RemoteSessionService extends ChangeNotifier {
  RemoteSessionService._();
  factory RemoteSessionService() => _instance;

  static final RemoteSessionService _instance = RemoteSessionService._();

  SessionHandle? _handle;
  Timer? _poll;
  String _id = 'dev-local';
  int _width = 320;
  int _height = 240;

  SessionState? _state;
  Uint8List _rgba = Uint8List(0);
  int _frameWidth = 0;
  int _frameHeight = 0;
  int _frames = 0;
  String _inputBackend = '';

  SessionState? get state => _state;
  bool get running => _state == SessionState.running;
  int get frames => _frames;
  String get inputBackend => _inputBackend;

  /// 最近一帧画面（用于 [RemoteView] 渲染）。
  (int, int, Uint8List) get latestFrame => (_frameWidth, _frameHeight, _rgba);

  /// 启动会话（惰性创建 `SessionHandle`，按合成源离线演示管线）。
  Future<void> start({
    String? id,
    int width = 320,
    int height = 240,
    SessionDirection direction = SessionDirection.desktopFrom,
  }) async {
    _id = id ?? _id;
    _width = width;
    _height = height;
    _handle ??= await SessionHandle.newInstance();
    await _handle!.create(
      id: _id,
      direction: direction,
      width: _width,
      height: _height,
    );
    await _handle!.start(id: _id);
    _state = await _handle!.state(id: _id);
    _inputBackend = await _handle!.probeInputBackend();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) => _pullFrame());
    notifyListeners();
  }

  /// 停止会话并停止轮询。
  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    if (_handle != null) {
      try {
        await _handle!.stop(id: _id);
        _state = await _handle!.state(id: _id);
      } catch (e) {
        debugPrint('RemoteSessionService.stop() 忽略错误：$e');
      }
    }
    notifyListeners();
  }

  /// 拉取并缓存一帧解码画面。
  Future<void> _pullFrame() async {
    final h = _handle;
    if (h == null) return;
    try {
      final frame = await h.nextFrame(id: _id);
      if (frame != null) {
        _frameWidth = frame.width;
        _frameHeight = frame.height;
        _rgba = Uint8List.fromList(frame.data);
        _frames += 1;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('拉取远程帧失败（$_id）：$e');
    }
  }

  /// 下发按键（keycode 用 Android/Linux EV 码，`down` 为按下/抬起）。
  Future<void> sendKey(int keycode, bool down) =>
      _guard((h) => h.inputKey(id: _id, keycode: keycode, down: down));

  /// 下发触摸（`action`：0=Down，1=Move，2=Up；坐标为屏幕像素）。
  Future<void> sendTouch(int x, int y, int action) =>
      _guard((h) => h.inputTouch(id: _id, x: x, y: y, action: action));

  /// 下发滚动。
  Future<void> sendScroll(int x, int y, double hScroll, double vScroll) =>
      _guard((h) => h.inputScroll(id: _id, x: x, y: y, hscroll: hScroll, vscroll: vScroll));

  Future<void> _guard(Future<void> Function(SessionHandle h) op) async {
    final h = _handle ?? await SessionHandle.newInstance();
    _handle ??= h;
    try {
      await op(h);
    } catch (e) {
      debugPrint('RemoteSessionService 输入下发忽略错误：$e');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
