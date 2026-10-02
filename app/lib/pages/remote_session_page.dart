import 'package:flutter/material.dart';

import '../services/remote_session_service.dart';
import '../src/rust/session.dart';
import '../widgets/remote_view.dart';

/// 远程会话页（第 3.6/3.10 段）：演示三方向远控会话的可测管线。
///
/// 默认以 `DesktopFrom` 方向 + 本机合成源跑通「捕获→编码→（通道）→解码→渲染」，
/// 无真机/无显示也能离线演示；输入下发经 Rust 侧探测降级（不崩溃）。
class RemoteSessionPage extends StatefulWidget {
  const RemoteSessionPage({super.key});

  @override
  State<RemoteSessionPage> createState() => _RemoteSessionPageState();
}

class _RemoteSessionPageState extends State<RemoteSessionPage> {
  final RemoteSessionService _svc = RemoteSessionService();
  bool _started = false;

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // 轮询到解码帧 / 状态变化时刷新 UI。
    _svc.addListener(_onChanged);
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    _svc.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_started) {
      await _svc.stop();
      setState(() => _started = false);
    } else {
      await _svc.start(width: 320, height: 240, direction: SessionDirection.desktopFrom);
      setState(() => _started = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (w, h, rgba) = _svc.latestFrame;

    return Scaffold(
      appBar: AppBar(
        title: const Text('远程会话'),
        actions: [
          IconButton(
            icon: Icon(_started ? Icons.stop : Icons.play_arrow, color: scheme.primary),
            onPressed: _toggle,
            tooltip: _started ? '停止会话' : '启动会话',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 会话状态与能力信息。
              Row(
                children: [
                  _StatusChip(
                    label: '状态：${_svc.state?.name ?? "stopped"}',
                    active: _svc.running,
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(label: '输入后端：${_svc.inputBackend}', active: true),
                  const SizedBox(width: 8),
                  _StatusChip(label: '已解出 ${_svc.frames} 帧', active: true),
                ],
              ),
              const SizedBox(height: 12),
              // 远控画面（RawImage 渲染；无帧时占位）。
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: w > 0 && rgba.isNotEmpty
                      ? RemoteView(bytes: rgba, width: w, height: h)
                      : Text(
                          _started ? '等待远程画面…' : '会话未启动',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // 输入下发（演示；实际远控输入在此注入）。
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InputButton(label: 'A', onTap: () => _svc.sendKey(30, true)),
                  _InputButton(label: 'B', onTap: () => _svc.sendKey(48, true)),
                  _InputButton(
                    label: '触摸(100,100)',
                    onTap: () => _svc.sendTouch(100, 100, 0),
                  ),
                  _InputButton(
                    label: '滚动',
                    onTap: () => _svc.sendScroll(100, 100, 0, -1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态小徽章。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// 输入演示按钮。
class _InputButton extends StatelessWidget {
  const _InputButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onTap, child: Text(label));
  }
}
