//! `protocol` —— Emote 跨语言统一协议与数据结构（第 2.1 段）
//!
//! 本模块是 **Rust ↔ Dart / Rust ↔ Rust** 的跨语言契约，仅定义数据结构与协议约定，
//! 不含任何网络 IO 实现。各字段类型明确，可供 flutter_rust_bridge 直接生成 Dart 镜像，
//! 保证两端结构体一一对应。
//!
//! 涵盖内容：
//! - mDNS 服务类型（QUIC/TCP）与常量
//! - 设备信息 `DeviceInfo`
//! - 发现状态 `DiscoveryState`、连接状态 `ConnectionState`、传输层 `Transport`
//! - 心跳规则与参数
//! - QUIC / TCP 连接参数
//! - 统一二进制消息头 `MessageHeader` 与帧类型 `MessageType`

pub mod message;
pub mod types;

pub use message::{
    MessageHeader, MessageType, HEARTBEAT_INTERVAL_SECS, HEARTBEAT_TIMEOUT_SECS, MESSAGE_HEADER_LEN,
    now_millis,
};
pub use types::{
    DeviceInfo, DeviceSystem, DiscoveryState, ConnectionState, Transport,
    QUIC_ALPN, QUIC_SERVICE_TYPE, TCP_SERVICE_TYPE, SUPPORTED_TRANSPORTS,
};