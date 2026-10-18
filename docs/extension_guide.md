# 扩展指南

> 与代码同步基线：Dev-5.0。所有路径以仓库根目录为基准。

## 如何添加新平台（iOS / macOS 预留接口）

Rust 侧已预留抽象层 `rust/emote_core/src/platform/`（iOS/macOS 为 stub）。接入步骤：

1. 在 `platform/` 下新建 `ios.rs` / `macos.rs`，实现与现有 stub 相同的 trait；在 `platform/mod.rs` 按 `#[cfg(target_os)]` 挂载。
2. `rust/emote_core/Cargo.toml` 增加 `[target.'cfg(target_os = "macos")'.dependencies]` 段（屏幕捕获与输入注入依赖在此声明，参照现有 Windows/Linux 段写法）。
3. Flutter 侧新建 `app/macos/`（`flutter create --platforms=macos .`）或 `app/ios/` Runner；`flutter_rust_bridge.yaml` 无需修改（绑定按 target 编译）。
4. 在 `app/lib/main.dart` 的平台判断处启用新平台入口；`app/lib/services/android_connectivity.dart` 仅 Android 生效，无需改动。
5. CI：在 `.github/workflows/release.yml` 仿照现有 job 增加 macos runner job（需 macos-14+ 与 Rust 目标 `aarch64-apple-darwin`）。

## 如何添加新远程控制方向

三方向会话实现在 `rust/emote_core/src/session/sessions.rs`，统一实现 `RemoteSession` trait（`session/mod.rs`）：

1. 在 `session/sessions.rs` 新建 `XxxSession`，实现 `RemoteSession` 全部方法：`direction/start/stop/state/input`，按需实现 `next_decoded`（被控端）、`set_bitrate`/`qos_bitrate`（编码端）。缺能力时返回 `Ended` / `Ok(())` no-op，禁止 panic。
2. 在 `session/mod.rs` 的 `SessionDirection` 枚举追加变体，并在 `SessionManager::create` 的 match 分支挂接新会话。
3. `api/session.rs` 无需改动（FFI 直接透传 `SessionDirection`）；执行 `flutter_rust_bridge_codegen generate` 重新生成 Dart 枚举。
4. Flutter 侧在 `app/lib/pages/remote_session_page.dart` 的方向选择与 `app/lib/widgets/session_tabs.dart` 中加入新方向入口。

## 如何替换编码器或解码器后端

- **编码器**：`rust/emote_core/src/encoder/` 中编码实现按 target cfg 组织。新后端实现与 openh264 相同的编码入口（输入 RGBA，输出 AnnexB `VideoFrame`），在 `DesktopSelfSession` 构造处切换；能力位 `encoder_available()`（`encoder/mod.rs`）需同步反映新后端可用性。
- **解码器（软件）**：`rust/emote_core/src/decoder/`，软解兜底为 openh264；替换时保持「输入 AnnexB → 输出 RGBA8 `VideoFrame`」契约。
- **解码器（硬件）**：`rust/emote_core/src/decoder/hw.rs` 的 `HwDecoderKind` 枚举追加后端（如 `D3D11VA`），实现其 `name()` 与 `detect_hw_decoders()` 中的探测逻辑；`DecoderSelector` 自动按「硬件优先、软解兜底」选择，`backend_name()` 返回实际后端名。
- 替换后在 `rust/emote_core/tests/` 补一条合成源全链路测试（参照 `segment4_qos_hwdec.rs`）。

## 如何调整 QoS 策略

QoS 控制器位于 `rust/emote_core/src/encoder/qos.rs`：

1. 调参：修改 `QosConfig::default()` —— `min_bitrate_bps: 500_000`、`max_bitrate_bps: 20_000_000`、`min_fps: 5`、`max_fps: 60`、`adjust_interval: 1s`（两次调整的最小冷却间隔）。
2. 调整算法：`QosController::update(network_delay_ms)` 内按延迟阈值输出 `IncreaseQuality / DecreaseQuality / NoChange`；阈值与步长在该方法内修改。
3. 会话侧集成点：`session/sessions.rs` 的 `DesktopSelfSession`（`on_latency_ms` 驱动、`next_encoded` 检测码率漂移重建编码器）；FFI 入口为 `api/session.rs` 的 `set_bitrate` / `qos_bitrate`。
4. 验证：`cargo test -p emote_core qos`（控制器边界）+ `cargo test --test segment4_qos_hwdec`（会话级端到端）。

## 如何添加新传输层

双传输层实现在 `rust/emote_core/src/transport/`：

1. 新建 `xxx.rs` 实现 `ActiveTransport` 同等接口（收发统一消息帧），在 `transport/mod.rs` 的 `ActiveTransport` 枚举/分发处挂接。
2. `protocol/types.rs`：`Transport` 枚举追加变体；`SUPPORTED_TRANSPORTS` 加入新传输层；`protocol/message.rs` 参照 `QuicParams`/`TcpParams` 增加新参数结构（超时/重试默认值）。
3. `connection/manager.rs` 的 `connect_to_device` 当前为「QUIC 优先 → TCP 回退」；在此插入新传输层的尝试顺序。
4. 发现侧：mDNS TXT 与 `DeviceInfo` 的端口字段（`quic_port`/`tcp_port`）为硬编码两端口；新传输层需在 `protocol/types.rs` 与 `api/discovery.rs` 的 `BroadcastConfig` 中增加对应端口字段，并同步 `app/lib/services/discovery_service.dart` 的端口常量（`kDefaultQuicPort = 5201`、`kDefaultTcpPort = 5202`）。
5. 回归：`cargo test`（transport 相关单元测试）+ 局域网双机联调。
