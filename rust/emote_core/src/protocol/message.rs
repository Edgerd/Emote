//! `protocol::message` —— 统一二进制消息头、心跳规则与 QUIC/TCP 参数（第 2.1 段）。

use serde::{Deserialize, Serialize};

//
// ---- 心跳规则 ----
//

/// 心跳发送间隔（秒）。两端每隔该时长发送一次心跳。
pub const HEARTBEAT_INTERVAL_SECS: u64 = 3;
/// 心跳超时阈值（秒）。超过该时长未收到对端心跳即判定断线。
pub const HEARTBEAT_TIMEOUT_SECS: u64 = 10;

// ---- 统一二进制消息头魔数与版本 ----

/// 消息魔数，固定 4 字节：`EMOT`。
pub const MESSAGE_MAGIC: [u8; 4] = *b"EMOT";

/// 当前协议版本号。
pub const MESSAGE_VERSION: u8 = 1;

/// 固定消息头字节长度（magic 4 + version 1 + type 1 + length 4 = 10 字节）。
pub const MESSAGE_HEADER_LEN: usize = 10;

//
// ---- 帧类型 ----
//

/// 统一消息类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum MessageType {
    /// 心跳（双向）。
    Heartbeat = 0x01,
    /// 通用控制消息（如握手、会话协商）。
    Control = 0x02,
    /// 视频数据流（第 3 段起使用）。
    Video = 0x03,
    /// 输入注入命令（第 3 段起使用）。
    Input = 0x04,
}

impl MessageType {
    pub fn from_u8(v: u8) -> Self {
        match v {
            0x01 => MessageType::Heartbeat,
            0x02 => MessageType::Control,
            0x03 => MessageType::Video,
            0x04 => MessageType::Input,
            _ => MessageType::Control,
        }
    }
}

//
// ---- 统一消息头 ----
//

/// 统一二进制消息头：`magic(4) + version(1) + type(1) + length(4, LE)`，固定 10 字节。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MessageHeader {
    /// 魔数，恒为 `EMOT`。
    pub magic: [u8; 4],
    /// 协议版本。
    pub version: u8,
    /// 帧类型。
    pub frame_type: MessageType,
    /// payload 字节长度（little-endian u32）。
    pub length: u32,
}

impl MessageHeader {
    /// 组装一个 message 类型帧头。
    pub fn new(frame_type: MessageType, length: u32) -> Self {
        MessageHeader {
            magic: MESSAGE_MAGIC,
            version: MESSAGE_VERSION,
            frame_type,
            length,
        }
    }

    /// 序列化为固定 10 字节（big-endian magic + LE length）。
    pub fn to_bytes(&self) -> [u8; MESSAGE_HEADER_LEN] {
        let mut buf = [0u8; MESSAGE_HEADER_LEN];
        buf[0..4].copy_from_slice(&self.magic);
        buf[4] = self.version;
        buf[5] = self.frame_type as u8;
        buf[6..MESSAGE_HEADER_LEN].copy_from_slice(&self.length.to_le_bytes());
        buf
    }

    /// 从 10 字节解析消息头；魔数不匹配时返回 None。
    pub fn from_bytes(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < MESSAGE_HEADER_LEN {
            return None;
        }
        let mut magic = [0u8; 4];
        magic.copy_from_slice(&bytes[0..4]);
        if magic != MESSAGE_MAGIC {
            return None;
        }
        let mut len_buf = [0u8; 4];
        len_buf.copy_from_slice(&bytes[6..MESSAGE_HEADER_LEN]);
        Some(MessageHeader {
            magic,
            version: bytes[4],
            frame_type: MessageType::from_u8(bytes[5]),
            length: u32::from_le_bytes(len_buf),
        })
    }
}

//
// ---- 心跳消息体 ----
//

/// 心跳负载。携带本地时间戳（毫秒）用于测量往返延迟。
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Heartbeat {
    /// 发送方本地毫秒级时间戳（自程序启动或 epoch）。
    pub timestamp_ms: u64,
}

impl Heartbeat {
    pub fn now() -> Self {
        Heartbeat {
            timestamp_ms: now_millis(),
        }
    }
}

/// 当前 epoch 毫秒（供心跳往返测量）。
pub fn now_millis() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_millis() as u64,
        Err(_) => 0,
    }
}

//
// ---- QUIC / TCP 连接参数 ----
//

/// QUIC 连接参数。
pub struct QuicParams {
    /// ALPN 协议名。
    pub alpn: &'static [u8],
    /// 握手超时（秒）。
    pub handshake_timeout_secs: u64,
    /// 空闲超时（秒），大于心跳间隔以保证保活。
    pub idle_timeout_secs: u64,
    /// 是否尝试 0-RTT。
    pub support_0rtt: bool,
}

impl Default for QuicParams {
    fn default() -> Self {
        QuicParams {
            alpn: crate::protocol::QUIC_ALPN,
            handshake_timeout_secs: 5,
            idle_timeout_secs: 15,
            support_0rtt: true,
        }
    }
}

/// TCP 回退连接参数。
pub struct TcpParams {
    /// 连接超时（秒）。
    pub connect_timeout_secs: u64,
    /// 是否启用 TCP_NODELAY（禁用 Nagle）。
    pub nodelay: bool,
    /// 连接失败后的重试次数。
    pub retry_count: u32,
}

impl Default for TcpParams {
    fn default() -> Self {
        TcpParams {
            connect_timeout_secs: 5,
            nodelay: true,
            retry_count: 1,
        }
    }
}