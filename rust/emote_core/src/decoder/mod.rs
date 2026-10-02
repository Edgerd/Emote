//! `decoder` —— H.264 软解码（第 3.4 段，后端 `openh264`；硬件解码见第 4.4 段）。
//!
//! 与 `encoder` 对称：openh264 仅桌面 target 链接，`OpenH264Decoder` 以 `#[cfg(desktop)]`
//! 隔离；Android 上 `decoder_available()` 返回 `false`，上层返回「codec_not_available」不 panic。
//!
//! 第 4.3 段：引入 `VideoDecoder` trait 抽象，允许未来替换 ffmpeg-next / 硬件后端。

use anyhow::Result;

/// 一帧解码画面（RGBA8，长度 = `width*height*4`）。
#[derive(Debug, Clone)]
pub struct DecodedFrame {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// 视频解码器统一抽象（第 4.3 段）。
///
/// 当前唯一实现：`OpenH264Decoder`（桌面 target）。
/// 未来可添加 ffmpeg-next（feature-gate）或硬件加速解码器（4.4 段）。
pub trait VideoDecoder: Send + Sync {
    /// 解码一段 AnnexB 数据，输出 RGBA8 帧（本次数据不足时返回 `None`）。
    fn decode(&mut self, annexb: &[u8]) -> Result<Option<DecodedFrame>>;

    /// 解码器名称（用于日志/调试）。
    fn name(&self) -> &'static str;
}

/// 当前 target 是否可用软解码后端（openh264 已链接）。
#[must_use]
pub fn decoder_available() -> bool {
    cfg!(desktop)
}

#[cfg(desktop)]
mod desktop_impl {
    use openh264::decoder::Decoder;
    use openh264::OpenH264API;

    use super::{DecodedFrame, VideoDecoder};

    /// 基于 openh264 的 H.264 软解码器（输入 AnnexB，输出 RGBA8）。
    pub struct OpenH264Decoder {
        inner: Decoder,
    }

    impl OpenH264Decoder {
        /// 创建解码器（自动从流中识别分辨率）。
        pub fn new() -> anyhow::Result<Self> {
            let api = OpenH264API::from_source();
            let inner =
                Decoder::new(api).map_err(|e| anyhow::anyhow!("openh264 解码器初始化失败: {e}"))?;
            Ok(Self { inner })
        }

        /// 解码一段 AnnexB 数据。
        ///
        /// 返回 [`DecodedFrame`]（RGBA8）；本次数据不足以产出画面时返回 `Ok(None)`。
        pub fn decode(&mut self, annexb: &[u8]) -> anyhow::Result<Option<DecodedFrame>> {
            let decoded = self
                .inner
                .decode(annexb)
                .map_err(|e| anyhow::anyhow!("openh264 解码失败: {e}"))?;
            Ok(match decoded {
                Some(yuv) => {
                    let (w, h) = yuv.dimension_rgb();
                    let mut rgba = vec![0u8; w * h * 4];
                    yuv.write_rgba8(&mut rgba);
                    Some(DecodedFrame {
                        width: w as u32,
                        height: h as u32,
                        rgba,
                    })
                }
                None => None,
            })
        }

        /// 依 SPS 提取分辨率（复用 `codec`/scrcpy 的 h264 解析）。
        pub fn resolution_from_sps(sp: &[u8]) -> Option<(u32, u32)> {
            scrcpy_protocol::h264::extract_resolution_from_stream(sp)
        }
    }

    /// 通过 `VideoDecoder` trait 使用（第 4.3 段抽象）。
    impl VideoDecoder for OpenH264Decoder {
        fn decode(&mut self, annexb: &[u8]) -> anyhow::Result<Option<DecodedFrame>> {
            OpenH264Decoder::decode(self, annexb)
        }
        fn name(&self) -> &'static str {
            "openh264"
        }
    }
}

#[cfg(desktop)]
pub use desktop_impl::OpenH264Decoder;

#[cfg(desktop)]
#[cfg(test)]
mod tests {
    use super::desktop_impl::OpenH264Decoder;
    use crate::capture::{ScreenSource, SyntheticSource};
    use crate::encoder::{I420Frame, OpenH264Encoder, EncoderOptions};

    /// 完整软编解码 round-trip：合成帧 → 编码 → 解码 → 校验分辨率与亮度。
    #[test]
    fn encode_decode_roundtrip() {
        let w = 160u32;
        let h = 120u32;
        let frames = 3u32;

        let mut src = SyntheticSource::new(w, h, frames);
        let mut encoder = OpenH264Encoder::new(&EncoderOptions {
            width: w,
            height: h,
            bitrate_bps: 300_000,
            max_fps: 15.0,
        })
        .expect("编码器");
        let mut decoder = OpenH264Decoder::new().expect("解码器");

        let mut got = 0usize;
        for i in 0..frames {
            let f = src.next_frame().expect("合成帧");
            // 记录本帧的期望亮度（合成源 Y = 16 + i）。
            let expected_y = 16u8 + (i % 239) as u8;
            let annexb = encoder
                .encode_i420(&I420Frame {
                    width: f.width,
                    height: f.height,
                    i420: f.i420.clone(),
                })
                .expect("编码");
            assert!(!annexb.is_empty());

            let out = decoder.decode(&annexb).expect("解码");
            let frame = out.expect("应能解出一帧");
            assert_eq!(frame.width, w, "解码宽度应匹配");
            assert_eq!(frame.height, h, "解码高度应匹配");
            assert_eq!(frame.rgba.len(), (w * h * 4) as usize);

            // 中性 Cb/Cr 时 R≈Y：取首像素 R 通道与期望亮度做宽容差比较。
            let r = frame.rgba[0] as i32;
            let expected = expected_y as i32;
            assert!(
                (r - expected).abs() <= 40,
                "解码亮度 {r} 与源 {expected} 偏差过大"
            );
            got += 1;
        }
        assert_eq!(got, frames as usize, "应解出全部帧");
    }
}
