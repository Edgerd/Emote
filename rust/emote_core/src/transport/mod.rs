//! transport —— 传输层入口（第 2.3 段）。
//!
//! 默认传输层 QUIC，回退传输层 TCP。`mod.rs` 提供统一的数据面：
//! - [`ActiveTransport`]：当前生效传输层的稳定标识。
//! - [`Frame`]：链路上承载的一帧（类型 + payload），供上层 handler 消费。
//! - [`Link`]：对单一连接统一的读/写句柄（QUIC 与 TCP 共用），并配套帧编解码。
//!
//! 帧格式与 2.1 段 `MessageHeader` 一致：`magic(4)+version(1)+type(1)+length(4 LE)=10 字节`。

pub mod quic;
pub mod tcp;

use bytes::Bytes;
use quinn::SendStream;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::tcp::OwnedWriteHalf;
use tokio::sync::mpsc;

use crate::protocol::{MessageHeader, MessageType, MESSAGE_HEADER_LEN};

/// 当前生效的传输层。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActiveTransport {
    Quic,
    Tcp,
}

impl ActiveTransport {
    pub fn as_str(&self) -> &'static str {
        match self {
            ActiveTransport::Quic => "quic",
            ActiveTransport::Tcp => "tcp",
        }
    }
}

impl std::fmt::Display for ActiveTransport {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// 链路上读取到的一帧。
#[derive(Debug, Clone)]
pub struct Frame {
    pub msg_type: MessageType,
    pub payload: Bytes,
}

/// 连接的可写半（统一 QUIC/TCP 写路径）。
pub enum SendHalf {
    Tcp { write: OwnedWriteHalf },
    Quic { tx: SendStream },
}

impl SendHalf {
    /// 向对端写入一帧。
    pub async fn send(&mut self, msg_type: MessageType, payload: &[u8]) -> std::io::Result<()> {
        match self {
            SendHalf::Tcp { write } => write_frame(write, msg_type, payload).await,
            SendHalf::Quic { tx } => write_frame(tx, msg_type, payload).await,
        }
    }
}

/// 对单条连接统一的句柄：写半 + 由后台读取任务填充的帧通道。
pub struct Link {
    pub transport: ActiveTransport,
    pub send: SendHalf,
    pub rx: mpsc::Receiver<Frame>,
}

impl Link {
    /// 拆分为写半与读通道（读通道由对应传输层的后台任务持续填充）。
    pub fn split(self) -> (SendHalf, mpsc::Receiver<Frame>) {
        (self.send, self.rx)
    }
}

/// 将一帧写入任意 async writer（TCP 流或 QUIC send stream）。
pub(crate) async fn write_frame<W: AsyncWrite + Unpin>(
    w: &mut W,
    msg_type: MessageType,
    payload: &[u8],
) -> std::io::Result<()> {
    let header = MessageHeader::new(msg_type, payload.len() as u32);
    w.write_all(&header.to_bytes()).await?;
    w.write_all(payload).await?;
    Ok(())
}

/// 单帧 payload 上限，防止对端用伪造的超大 `length` 触发巨量内存分配导致 OOM（DoS）。
/// 远程桌面编码帧远小于该值；256 MiB 足够承载常规媒体帧，又能封死 `0xFFFFFFFF` 等恶意长度。
const MAX_FRAME_LEN: usize = 256 << 20;

/// 从任意 async reader 读取一帧；对端优雅关闭时返回 `Ok(None)`。
pub(crate) async fn read_frame<R: AsyncRead + Unpin>(r: &mut R) -> std::io::Result<Option<Frame>> {
    let mut hbuf = [0u8; MESSAGE_HEADER_LEN];
    if !read_exact_or_eof(r, &mut hbuf).await? {
        return Ok(None);
    }
    let header = MessageHeader::from_bytes(&hbuf).ok_or_else(|| {
        std::io::Error::new(std::io::ErrorKind::InvalidData, "协议头魔数不匹配")
    })?;
    let plen = header.length as usize;
    if plen > MAX_FRAME_LEN {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("帧长度 {plen} 超过上限 {MAX_FRAME_LEN}，拒绝读取以免耗尽内存"),
        ));
    }
    let mut payload = vec![0u8; plen];
    r.read_exact(&mut payload).await?;
    Ok(Some(Frame {
        msg_type: header.frame_type,
        payload: Bytes::from(payload),
    }))
}

/// 读满 buf，或在首字节前遇 EOF 返回 false；中途 EOF 视为协议错误。
async fn read_exact_or_eof<R: AsyncRead + Unpin>(r: &mut R, buf: &mut [u8]) -> std::io::Result<bool> {
    let mut n = 0usize;
    while n < buf.len() {
        match r.read(&mut buf[n..]).await? {
            0 => {
                if n == 0 {
                    return Ok(false);
                }
                return Err(std::io::Error::new(
                    std::io::ErrorKind::UnexpectedEof,
                    "帧未完整即断开",
                ));
            }
            k => n += k,
        }
    }
    Ok(true)
}

/// 后台读取任务：把任意 async reader（TCP 流或 QUIC ReceiveStream）解析出的
/// 帧送入通道，收流结束或出错则关闭通道（链路断开）。
pub(crate) async fn pump_frames<R: AsyncRead + Unpin>(
    mut reader: R,
    tx: mpsc::Sender<Frame>,
) {
    loop {
        match read_frame(&mut reader).await {
            Ok(Some(frame)) => {
                if tx.send(frame).await.is_err() {
                    break;
                }
            }
            Ok(None) => break,
            Err(_) => break,
        }
    }
}