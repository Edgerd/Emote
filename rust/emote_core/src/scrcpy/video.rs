//! `scrcpy::video` —— 视频流读取与 H.264 包解析（第 3.1 段）。
//!
//! 复用 `scrcpy-protocol` 的 [`VideoPacket`] 帧格式（`8B(pts|flags) + 4B(len) + payload`），
//! 从任意 `std::io::Read`（如 ADB 端口转发的 `TcpStream`）逐包解析 H.264。本段不解码。

use std::io::Read;

use scrcpy_protocol::protocol::video::VideoPacket;
use scrcpy_protocol::Result as ScrcpyResult;

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
    pub fn read_packet(&mut self) -> ScrcpyResult<VideoPacket> {
        VideoPacket::read_from(&mut self.reader)
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
