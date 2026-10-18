# 网络协议文档

> 与代码同步基线：Dev-5.0。常量与结构定义于 `rust/emote_core/src/protocol/`（`types.rs` / `message.rs`）。

## 服务发现（mDNS / DNS-SD）

| 常量 | 值 | 说明 |
| --- | --- | --- |
| `QUIC_SERVICE_TYPE` | `_emote._udp.local.` | QUIC（UDP）服务类型 |
| `TCP_SERVICE_TYPE` | `_emote._tcp.local.` | TCP 服务类型 |
| `QUIC_ALPN` | `emote/1` | QUIC TLS ALPN 协议名 |
| `SUPPORTED_TRANSPORTS` | `[Quic, Tcp]` | 支持的传输层列表 |

默认端口（Flutter 侧 `app/lib/services/discovery_service.dart` 常量）：QUIC `5201`（UDP）、TCP `5202`。发现轮询间隔 2 s。

TXT 记录 / `DeviceInfo` 字段：`id`（UUID v4，首次启动生成并持久化）、`name`、`system`（`win` / `linux` / `android`）、`ip`（IPv4）、`quic_port`、`tcp_port`、`supported_transports`（如 `["quic","tcp"]`）、`online`、`preferred_transport`（默认 `quic`）、`protocol_version`（如 `1.0.0`）。

## QUIC 连接流程

`QuicParams`（`protocol/message.rs` 默认值）：

| 参数 | 值 |
| --- | --- |
| `alpn` | `emote/1` |
| `handshake_timeout_secs` | 5 |
| `idle_timeout_secs` | 15 |
| `support_0rtt` | `true` |

流程：

1. 服务端启动：设备监听 UDP 端口，用 `rcgen` 自签证书（CN 绑定设备 ID），证书 SHA-256 指纹本地持有。
2. 客户端建连：从 mDNS 取对端 `ip:quic_port`，创建 quinn 客户端端点（当前**跳过对端证书校验**，局域网信任模型；严格校验入口 `make_client_endpoint_strict` 已实现，待 `cert=` 指纹经 mDNS TXT 发布后启用）。
3. TLS 1.3 握手（ALPN `emote/1`），5 s 内未完成即失败。
4. 握手成功后进入 `Connected`，双向心跳保活；空闲超时 15 s 大于心跳间隔 3 s，正常心跳不会触发空闲断连。
5. **0-RTT 重连**：`support_0rtt = true`，对已知对端重连时携带 0-RTT 早数据，省去一次往返。
6. 失败回退：QUIC 建连失败（含被企业网络 UDP 阻断）→ `connection/manager.rs` 自动尝试 TCP。

## TCP 回退流程

`TcpParams`（默认值）：`connect_timeout_secs = 5`、`nodelay = true`（禁用 Nagle，降低交互延迟）、`retry_count = 1`。

流程：mDNS 取 `ip:tcp_port` → TCP 三次握手（5 s 超时）→ 开启 `TCP_NODELAY` → 进入与 QUIC 相同的消息层。TCP 通道为**明文**，无 TLS；重连使用标准指数退避（见下）。

## 统一二进制消息头

所有业务消息（QUIC 流 / TCP 流）共用 10 字节定长消息头：

```text
+--------+---------+------+----------+
| magic  | version | type | length   |
| 4 B    | 1 B     | 1 B  | 4 B (LE) |
+--------+---------+------+----------+
  "EMOT"   =1        见下   payload 长度
```

| 常量 | 值 |
| --- | --- |
| `MESSAGE_MAGIC` | `EMOT`（4 字节） |
| `MESSAGE_VERSION` | `1` |
| `MESSAGE_HEADER_LEN` | `10` |

消息类型 `MessageType`：`Heartbeat = 0x01`（双向）、`Control = 0x02`（握手 / 会话协商）、`Video = 0x03`（视频流）、`Input = 0x04`（输入注入）。未知 type 解析为 `Control`（前向兼容）。

## 心跳格式与规则

| 常量 | 值 |
| --- | --- |
| `HEARTBEAT_INTERVAL_SECS` | 3（每 3 s 双向发送一次） |
| `HEARTBEAT_TIMEOUT_SECS` | 10（连续 10 s 未收到对端心跳判定断线） |

心跳 payload 为空（仅 10 B 消息头，type=0x01）。心跳同时承担 RTT 采样职责：发送→回包差值喂给 QoS（`QosController::update`）与重连判定（`SessionState::Reconnecting`）。

## 断线重连

`connection/reconnect.rs` `ReconnectPolicy` 默认值：`initial_backoff = 100 ms`、`factor = 2.0`（指数翻倍）、`max_attempts = 5`、`jitter = 0.2`（退避时长 ±20% 随机抖动，`fastrand` 实现，防止多客户端同时重连的 thundering herd）。退避序列：100 → 200 → 400 → 800 → 1600 ms。QUIC 重连优先走 0-RTT；超过 `max_attempts` 后停止并上报 `Error`。

## QUIC 拥塞控制

quinn 0.11 默认启用 **CUBIC** 拥塞控制（RFC 9002 丢包检测 + 慢启动/拥塞避免），当前未替换为 BBR。应用层配合策略：

- 视频流经独立 QUIC 流（多路复用：心跳/控制与视频互不队头阻塞）。
- 码率由 `encoder/qos.rs` 按端到端延迟在 500 kbps～20 Mbps 之间调节（1 s 冷却），与 CUBIC 的窗口调节解耦——应用层先于拥塞控制降码率，避免排队延迟堆积。

## 信任模型（重要）

- QUIC（TLS）：当前跳过对端证书校验，**同网段设备可伪造服务端**；严格校验（证书指纹比对 + CN 绑定设备 ID）代码已就绪，启用条件为 mDNS TXT 发布 `cert=` 指纹。
- TCP：明文。
- 结论：仅面向**纯局域网**使用，请勿在不可信网络或跨公网部署。
