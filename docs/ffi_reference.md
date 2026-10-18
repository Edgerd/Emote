# FFI 接口清单

> 与代码同步基线：`emote_core` 0.1.0（Dev-5.0，FRB 2.13.0）。
> 所有接口位于 `rust/emote_core/src/api/`，Dart 绑定由 `flutter_rust_bridge_codegen generate` 生成到 `app/lib/src/rust/`（`api/*.dart` + `session.dart` 公共类型）。**本文只列已实现的导出，与代码一一对应。**

## simple 模块（`api/simple.rs`）

| 函数 | 参数 | 返回 | Dart 调用 | 用途 |
| --- | --- | --- | --- | --- |
| `greet` | `name: String` | `String` | `greet(name: name)`（`src/rust/api/simple.dart`） | 验证 FRB 同步调用链路的最小演示接口 |

## discovery 模块（`api/discovery.rs`）

句柄类：`DiscoveryHandle`（不透明句柄，Dart 侧 `DiscoveryHandle`）。

| 函数 | 参数 | 返回 | Dart 调用 | 用途 |
| --- | --- | --- | --- | --- |
| `DiscoveryHandle.new` | 无 | `DiscoveryHandle` | `DiscoveryHandle.newInstance()` | 创建空句柄（未广播/未浏览） |
| `start_broadcast` | `cfg: BroadcastConfig`、`host_ip: String` | `Result<()>`（Dart 抛异常） | `startBroadcast(cfg: cfg, hostIp: hostIp)` | 启动 mDNS 广播使本机可被发现（幂等） |
| `stop_broadcast` | 无 | `()` | `stopBroadcast()` | 停止 mDNS 广播 |
| `start_browse` | 无 | `Result<()>` | `startBrowse()` | 启动 mDNS 浏览局域网设备（幂等） |
| `stop_browse` | 无 | `()` | `stopBrowse()` | 停止 mDNS 浏览 |
| `list_devices` | 无 | `Vec<DeviceInfo>` | `listDevices()` | 返回当前已发现设备列表（按名称排序） |
| `state` | 无 | `DiscoveryState` | `state()` | 当前发现状态 |

`BroadcastConfig` 字段：`id: String`、`name: String`、`system: DeviceSystem`、`quic_port: u16`、`tcp_port: u16`、`preferred_transport: Transport`、`protocol_version: String`。

## connection 模块（`api/connection.rs`）

句柄类：`ConnectionHandle`（内部持有 tokio 运行时与多连接表）。

| 函数 | 参数 | 返回 | Dart 调用 | 用途 |
| --- | --- | --- | --- | --- |
| `ConnectionHandle.new` | 无 | `Result<Self>` | `ConnectionHandle.newInstance()` | 创建连接管理器（惰性启动 tokio） |
| `connect` | `dev: &DeviceInfo` | `Result<ConnectionState>` | `connect(dev: dev)` | 建立连接：QUIC 优先，失败回退 TCP |
| `disconnect` | `id: String` | `Result<()>` | `disconnect(id: id)` | 断开指定设备连接 |
| `state` | `id: String` | `ConnectionState` | `state(id: id)` | 查询连接状态 |
| `active_transport` | `id: String` | `Option<ActiveTransport>` | `activeTransport(id: id)` | 当前生效传输层（未连接为 `null`） |
| `send` | `id: String`、`msg_type: MessageType`、`payload: Vec<u8>` | `Result<()>` | `send(id: id, msgType: msgType, payload: payload)` | 发送一帧控制消息 |

## session 模块（`api/session.rs`）

句柄类：`SessionHandle`（内部持有 `SessionManager`，Dart 侧 `RemoteSessionService` 使用）。

| 函数 | 参数 | 返回 | Dart 调用 | 用途 |
| --- | --- | --- | --- | --- |
| `SessionHandle.new` | 无 | `Result<Self>` | `SessionHandle.newInstance()` | 创建会话管理器 |
| `create` | `id: String`、`direction: SessionDirection`、`width: u32`、`height: u32` | `Result<()>` | `create(id: id, direction: direction, width: w, height: h)` | 依方向创建会话（宽高偶数对齐） |
| `start` | `id: String` | `Result<()>` | `start(id: id)` | 启动会话 |
| `stop` | `id: String` | `Result<()>` | `stop(id: id)` | 停止会话 |
| `state` | `id: String` | `Option<SessionState>` | `state(id: id)` | 查询会话状态（无会话为 `null`） |
| `next_frame` | `id: String` | `Option<VideoFrame>` | `nextFrame(id: id)` | 拉取一帧解码画面 RGBA8（无帧为 `null`） |
| `input_key` | `id: String`、`keycode: u32`、`down: bool` | `Result<()>` | `inputKey(id: id, keycode: k, down: d)` | 下发按键（EV 键码） |
| `input_touch` | `id: String`、`x: u32`、`y: u32`、`action: u8` | `Result<()>` | `inputTouch(id: id, x: x, y: y, action: a)` | 下发触摸（0=Down 1=Move 2=Up） |
| `input_scroll` | `id: String`、`x: u32`、`y: u32`、`hscroll: f32`、`vscroll: f32` | `Result<()>` | `inputScroll(...)` | 下发滚轮 |
| `codec_available` | 无 | `bool` | `codecAvailable()` | 当前 target 是否具备软编解码后端 |
| `probe_input_backend` | 无 | `String` | `probeInputBackend()` | 当前输入注入后端名（无则 `"null"`） |
| `probe_hw_decoder` | 无 | `Option<String>` | `probeHwDecoder()` | 首个可用硬件解码后端名（无则 `null`，上层回退软解） |
| `set_bitrate` | `id: String`、`bps: u32` | `Result<()>` | `setBitrate(id: id, bps: bps)` | 设定会话目标码率（仅编码方向有效） |
| `qos_bitrate` | `id: String` | `Option<u32>` | `qosBitrate(id: id)` | 查询 QoS 目标码率（无编码方向为 `null`） |

## 跨语言数据类型（`src/rust/session.dart`）

| 类型 | 定义位置 | 字段/枚举值 |
| --- | --- | --- |
| `VideoFrame` | `session/mod.rs` | `width: u32`、`height: u32`、`frame_type: H264FrameType`、`data: Vec<u8>`（RGBA8 或 AnnexB，`is_decoded` 区分）、`is_decoded: bool` |
| `SessionState` | `session/mod.rs` | `Stopped` / `Running` / `Reconnecting` / `Ended` |
| `SessionDirection` | `session/mod.rs` | `Scrcpy` / `DesktopSelf` / `DesktopFrom` |
| `DeviceInfo` | `protocol/types.rs` | `id`、`name`、`system`、`ip`、`quic_port`、`tcp_port`、`supported_transports`、`online`、`preferred_transport`、`protocol_version` |
| `DeviceSystem` | `protocol/types.rs` | `Windows` / `Linux` / `Android` / `Unknown`（序列化为 `win`/`linux`/`android`/`unknown`） |
| `Transport` | `protocol/types.rs` | `Quic` / `Tcp` |
| `DiscoveryState` | `protocol/types.rs` | `Stopped` / `Starting` / `Running` / `Error` |
| `ConnectionState` | `protocol/types.rs` | `Disconnected` / `Connecting` / `Connected` / `Reconnecting` / `Error` |
| `MessageType` | `protocol/message.rs` | `Heartbeat=0x01` / `Control=0x02` / `Video=0x03` / `Input=0x04` |

## 线程安全约定

`SessionHandle` 内部 `SessionManager`（`DashMap<String, Box<dyn RemoteSession>>`）满足 `Send + Sync`（编译期测试 `session_manager_is_send_and_sync` 保证），可安全跨 Rust/Dart 线程边界传递。所有输入/会话方法在能力缺失时返回 `Ok`（no-op）或 `None`，不 panic。
