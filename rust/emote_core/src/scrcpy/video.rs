//! `scrcpy::video` —— 视频流读取与 H.264 包解析（第 3.1 段）。
//!
//! 复用 `scrcpy-protocol` 的 [`VideoPacket`] 帧格式（`8B(pts|flags) + 4B(len) + payload`），
//! 从任意 `std::io::Read`（如 ADB 端口转发的 `TcpStream`）逐包解析 H.264。本段不解码。
//!
//! 安全约束：`len` 字段来自不可信对端（scrcpy server 经 ADB 转发），先校验
//! [`MAX_VIDEO_PACKET_PAYLOAD`] 上限再喂给解析器，防止伪造超大长度导致内存耗尽。

use std::io::{ErrorKind, Read};

use scrcpy_protocol::protocol::video::VideoPacket;

/// scrcpy 视频包 payload 上限（16 MiB）。正常 H.264 帧远小于该值；
/// 超过即判定为恶意/异常包，拒绝解析以免大内存分配（OOM DoS）。
pub const MAX_VIDEO_PACKET_PAYLOAD: u32 = 16 << 20;

/// 视频流读取器：从既有底层流逐包解析 H.264。
pub struct ScrcpyVideoStream<R: Read> {
    reader: R,
}

impl<R: Read> ScrcpyVideoStream<R> {
    /// 以既有流（如 scrcpy 视频端口经 ADB 转发的 `TcpStream`）构造。
    pub fn connect(reader: R) -> Self {
        Self { reader }
    }

    /// 读取并解析一个视频 packet（12 字节帧头 + 压缩 payload）。
    ///
    /// 先自行读 12 字节帧头并校验 `len` 上限，再通过有界读者
    /// [`BoundedVideoReader`]（只放行帧头 + `len` 字节）调用
    /// `VideoPacket::read_from`，避免 crate 内直接按对端长度分配。
    pub fn read_packet(&mut self) -> std::io::Result<VideoPacket> {
        let mut hdr = [0u8; 12];
        self.reader.read_exact(&mut hdr)?;
        let len = u32::from_be_bytes(hdr[8..12].try_into().unwrap());
        if len > MAX_VIDEO_PACKET_PAYLOAD {
            return Err(std::io::Error::new(
                ErrorKind::InvalidData,
                format!(
                    "scrcpy 视频包长度 {len} 超过上限 {}，拒绝读取以免耗尽内存",
                    MAX_VIDEO_PACKET_PAYLOAD
                ),
            ));
        }
        let mut bounded = BoundedVideoReader::new(&mut self.reader, hdr, len as usize);
        VideoPacket::read_from(&mut bounded)
            .map_err(|e| std::io::Error::new(ErrorKind::InvalidData, format!("解析 scrcpy 视频包失败: {e}")))
    }
}

/// 有界读者：先回放已读到的 12 字节帧头，随后仅放行至多 `payload_budget` 字节，
/// 之后立即 EOF。保证 `VideoPacket::read_from` 既不会多读（越过包边界），
/// 也不会少读（读满 budget 前 EOF 即报错）。
struct BoundedVideoReader<'a, R: Read> {
    inner: &'a mut R,
    hdr: [u8; 12],
    hdr_pos: usize,
    payload_budget: usize,
    payload_read: usize,
    buf: Vec<u8>,
}

impl<'a, R: Read> BoundedVideoReader<'a, R> {
    fn new(inner: &'a mut R, hdr: [u8; 12], payload_budget: usize) -> Self {
        Self {
            inner,
            hdr,
            hdr_pos: 0,
            payload_budget,
            payload_read: 0,
            buf: Vec::new(),
        }
    }
}

impl<R: Read> Read for BoundedVideoReader<'_, R> {
    fn read(&mut self, out: &mut [u8]) -> std::io::Result<usize> {
        // 阶段一：回放帧头字节。
        if self.hdr_pos < 12 {
            let n = std::cmp::min(out.len(), 12 - self.hdr_pos);
            out[..n].copy_from_slice(&self.hdr[self.hdr_pos..self.hdr_pos + n]);
            self.hdr_pos += n;
            return Ok(n);
        }
        // 阶段二：payload，只放行预算内的字节（避免越包多读）。
        if self.payload_read >= self.payload_budget {
            return Ok(0);
        }
        let want = std::cmp::min(out.len(), self.payload_budget - self.payload_read);
        if self.buf.len() < want {
            self.buf.resize(want, 0);
        }
        self.inner.read_exact(&mut self.buf[..want])?;
        out[..want].copy_from_slice(&self.buf[..want]);
        self.payload_read += want;
        Ok(want)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 构造一个 scrcpy 视频 packet 字节流：`8B(pts|flags, BE) + 4B(len, BE) + payload`。
    fn make_packet(pts_us: u64, is_config: bool, is_keyframe: bool, payload: &[u8]) -> Vec<u8> {
        let mut flags = pts_us;
        if is_config {
            flags |= 1u64 << 63;
        }
        if is_keyframe {
            flags |= 1u64 << 62;
        }
        let mut buf = Vec::new();
        buf.extend_from_slice(&flags.to_be_bytes());
        buf.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        buf.extend_from_slice(payload);
        buf
    }

    #[test]
    fn parses_keyframe() {
        let payload: Vec<u8> = vec![0x00, 0x00, 0x00, 0x01, 0x65, 0xAA];
        let mut stream = ScrcpyVideoStream::connect(std::io::Cursor::new(make_packet(
            1000, false, true, &payload,
        )));
        let pkt = stream.read_packet().expect("解析 keyframe 失败");
        assert_eq!(pkt.pts_us, 1000);
        assert!(pkt.is_keyframe);
        assert!(!pkt.is_config);
        assert_eq!(pkt.data, payload);
        assert!(!pkt.is_empty());
        assert_eq!(pkt.total_size(), 12 + payload.len());
    }

    #[test]
    fn parses_config_flag() {
        let payload = vec![0x01];
        let mut stream = ScrcpyVideoStream::connect(std::io::Cursor::new(make_packet(
            0, true, false, &payload,
        )));
        let pkt = stream.read_packet().expect("解析 config 失败");
        assert!(pkt.is_config);
        assert!(!pkt.is_keyframe);
        assert_eq!(pkt.data, payload);
    }

    #[test]
    fn accepts_empty_payload_keyframe() {
        let mut stream =
            ScrcpyVideoStream::connect(std::io::Cursor::new(make_packet(0, false, true, &[])));
        let pkt = stream.read_packet().unwrap();
        assert!(pkt.is_empty());
        assert_eq!(pkt.data.len(), 0);
    }
}
