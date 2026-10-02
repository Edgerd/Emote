//! `codec` —— H.264 帧模型与编解码后端（第 3.4 段；编解码器本体见 Batch 2）。
//!
//! 软编解码后端为 `openh264`（Apache-2.0）。openh264 只在**桌面 target**（Windows /
//! Linux 非 Android）链接：`build.rs` 为这些 target 发 `desktop` cfg，Android target
//! 不拉取 openh264，故这里以 `codec_backend_linked()` 提供可探测的「后端是否可用」。

/// H.264 帧类型（与 `openh264` 及 scrcpy 帧标志语义一致）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum H264FrameType {
    /// 关键帧（IDR / Idr，可独立解码）。
    Idr,
    /// 非关键帧（P 帧）。
    NonIdr,
    /// 未知 / 未标记。
    #[default]
    Unknown,
}

/// 一帧原始视频数据（捕获帧的 YUV I420 或 AnnexB 压缩流，视 `kind` 而定）。
#[derive(Debug, Clone)]
pub struct H264VideoFrame {
    /// 像素宽度。
    pub width: u32,
    /// 像素高度。
    pub height: u32,
    /// 帧类型。
    pub frame_type: H264FrameType,
    /// 原始字节（I420 平面或 AnnexB 流）。
    pub data: Vec<u8>,
}

/// 当前 target 是否链接了 openh264 软编解码后端。
///
/// 桌面 target 恒为 `true`；Android target（不链接 openh264）为 `false`，
/// 上层据此返回「codec_not_available」而非 panic。
#[must_use]
pub fn codec_backend_linked() -> bool {
    cfg!(desktop)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_type_default_is_unknown() {
        assert_eq!(H264FrameType::default(), H264FrameType::Unknown);
        let f = H264VideoFrame {
            width: 320,
            height: 240,
            frame_type: H264FrameType::Idr,
            data: vec![0x00, 0x01, 0x02],
        };
        assert_eq!(f.frame_type, H264FrameType::Idr);
        assert_eq!(f.data.len(), 3);
    }
}
