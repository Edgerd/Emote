//! `protocol::types` —— 设备信息、状态枚举、传输层与连接参数（第 2.1 段）。

use serde::{Deserialize, Serialize};
use std::fmt;

//
// ---- mDNS 服务类型与域名常量 ----
//

/// QUIC 服务类型（DNS-SD）：`_emote._udp.local.`（QUIC 基于 UDP）。
pub const QUIC_SERVICE_TYPE: &str = "_emote._udp.local.";
/// TCP 服务类型（DNS-SD）：`_emote._tcp.local.`。
pub const TCP_SERVICE_TYPE: &str = "_emote._tcp.local.";
/// QUIC 传输层 ALPN 协议名。
pub const QUIC_ALPN: &[u8] = b"emote/1";
/// 支持的传输层列表（`preferred_transport` 优先）。
pub const SUPPORTED_TRANSPORTS: &[Transport] = &[Transport::Quic, Transport::Tcp];

//
// ---- 设备系统类型（小写字符串：win / linux / android）----
//

/// 设备系统类型。为便于跨语言序列化，直接以小写字符串落盘。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeviceSystem {
    Windows,
    Linux,
    Android,
    #[serde(other)]
    Unknown,
}

impl DeviceSystem {
    /// DNS-SD TXT 记录 / 消息中使用的稳定小写标识。
    pub fn as_str(&self) -> &'static str {
        match self {
            DeviceSystem::Windows => "win",
            DeviceSystem::Linux => "linux",
            DeviceSystem::Android => "android",
            DeviceSystem::Unknown => "unknown",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "win" => DeviceSystem::Windows,
            "linux" => DeviceSystem::Linux,
            "android" => DeviceSystem::Android,
            _ => DeviceSystem::Unknown,
        }
    }
}

impl fmt::Display for DeviceSystem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

//
// ---- 传输层枚举 ----
//

/// 传输层选择。`preferred_transport` 决定默认优先使用的链路。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Transport {
    Quic,
    Tcp,
}

impl Transport {
    pub fn as_str(&self) -> &'static str {
        match self {
            Transport::Quic => "quic",
            Transport::Tcp => "tcp",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "tcp" => Transport::Tcp,
            _ => Transport::Quic,
        }
    }
}

impl fmt::Display for Transport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

//
// ---- 状态枚举 ----
//

/// 设备发现状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DiscoveryState {
    Stopped,
    Starting,
    Running,
    Error,
}

/// 连接状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Error,
}

//
// ---- 设备信息（Rust 与 Dart 结构体字段一一对应）----
//

/// 一台被发现的设备实例。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeviceInfo {
    /// 设备唯一 ID，UUID v4，首次启动生成并持久化。
    pub id: String,
    /// 显示名（如 “Edgerd-Desktop”）。
    pub name: String,
    /// 系统类型：win / linux / android。
    pub system: DeviceSystem,
    /// 局域网 IP（IPv4 字符串）。
    pub ip: String,
    /// QUIC 监听端口（动态分配）。
    pub quic_port: u16,
    /// TCP 监听端口（动态分配）。
    pub tcp_port: u16,
    /// 支持的传输层列表，如 ["quic","tcp"]。
    pub supported_transports: Vec<Transport>,
    /// 登录状态：false=离线，true=在线。
    pub online: bool,
    /// 优先使用的传输层（QUIC 默认）。
    pub preferred_transport: Transport,
    /// 协议版本，如 "1.0.0"。
    pub protocol_version: String,
}

impl DeviceInfo {
    /// 从 mDNS TXT 记录可能缺失的字段构造一份占位值（用于发现阶段缺省）。
    pub fn placeholder(id: String) -> Self {
        DeviceInfo {
            id,
            name: String::new(),
            system: DeviceSystem::Unknown,
            ip: String::new(),
            quic_port: 0,
            tcp_port: 0,
            supported_transports: SUPPORTED_TRANSPORTS.to_vec(),
            online: true,
            preferred_transport: Transport::Quic,
            protocol_version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }
}

impl fmt::Display for DeviceInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}@{} [{}, quic={}, tcp={}, sys={}]",
            self.name, self.ip, self.preferred_transport, self.quic_port, self.tcp_port, self.system
        )
    }
}