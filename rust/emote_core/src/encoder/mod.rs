//! `encoder` —— H.264 软编码（第 3.4 段，后端 `openh264`）。
//!
//! openh264 只在**桌面 target** 链接（见 `Cargo.toml` 的 target-gated 依赖与 `build.rs`
//! 的 `desktop` cfg）。`OpenH264Encoder` 及其实现因此用 `#[cfg(desktop)]` 隔离；
//! Android target 不编译 openh264，`encoder_available()` 返回 `false`，上层据此
//! 返回「codec_not_available」而非 panic。

/// 当前 target 是否可用软编码后端（openh264 已链接）。
#[must_use]
pub fn encoder_available() -> bool {
    cfg!(desktop)
}

/// 编码器配置。
#[derive(Debug, Clone)]
pub struct EncoderOptions {
    /// 像素宽度（偶数）。
    pub width: u32,
    /// 像素高度（偶数）。
    pub height: u32,
    /// 目标码率（bps）。
    pub bitrate_bps: u32,
    /// 目标帧率（0 = 不限）。
    pub max_fps: f32,
}

impl Default for EncoderOptions {
    fn default() -> Self {
        Self {
            width: 320,
            height: 240,
            bitrate_bps: 500_000,
            max_fps: 15.0,
        }
    }
}

/// 面向软编码的 I420 源（宽高需为偶数）。
#[derive(Debug, Clone)]
pub struct I420Frame {
    pub width: u32,
    pub height: u32,
    pub i420: Vec<u8>,
}

#[cfg(desktop)]
mod desktop_impl {
    use openh264::encoder::{Encoder, EncoderConfig, RateControlMode};
    use openh264::formats::YUVSource;
    use openh264::OpenH264API;

    use super::{I420Frame, EncoderOptions};

    impl YUVSource for I420Frame {
        fn width(&self) -> i32 {
            self.width as i32
        }
        fn height(&self) -> i32 {
            self.height as i32
        }
        fn y(&self) -> &[u8] {
            let n = (self.width * self.height) as usize;
            &self.i420[..n]
        }
        fn u(&self) -> &[u8] {
            let y = (self.width * self.height) as usize;
            let u = y / 4;
            &self.i420[y..y + u]
        }
        fn v(&self) -> &[u8] {
            let y = (self.width * self.height) as usize;
            let u = y / 4;
            &self.i420[y + u..]
        }
        fn y_stride(&self) -> i32 {
            self.width as i32
        }
        fn u_stride(&self) -> i32 {
            (self.width / 2) as i32
        }
        fn v_stride(&self) -> i32 {
            (self.width / 2) as i32
        }
    }

    /// 基于 openh264 的 H.264 软编码器（输出 AnnexB 流）。
    pub struct OpenH264Encoder {
        inner: Encoder,
    }

    impl OpenH264Encoder {
        /// 依配置创建编码器。
        pub fn new(options: &EncoderOptions) -> anyhow::Result<Self> {
            let api = OpenH264API::from_source();
            let mut config = EncoderConfig::new(options.width, options.height).set_bitrate_bps(options.bitrate_bps);
            if options.max_fps > 0.0 {
                config = config.max_frame_rate(options.max_fps);
            }
            config = config.rate_control_mode(RateControlMode::Bitrate);
            let inner =
                Encoder::with_config(api, config).map_err(|e| anyhow::anyhow!("openh264 初始化失败: {e}"))?;
            Ok(Self { inner })
        }

        /// 编码一帧 I420，返回该帧的 AnnexB 输出（首帧含 SPS/PPS + IDR）。
        pub fn encode_i420(&mut self, i420: &I420Frame) -> anyhow::Result<Vec<u8>> {
            let bitstream = self
                .inner
                .encode(i420)
                .map_err(|e| anyhow::anyhow!("openh264 编码失败: {e}"))?;
            Ok(bitstream.to_vec())
        }
    }
}

#[cfg(desktop)]
pub use desktop_impl::OpenH264Encoder;

#[cfg(desktop)]
#[cfg(test)]
mod tests {
    use super::{desktop_impl::OpenH264Encoder, I420Frame, EncoderOptions};
    use crate::capture::{Frame, ScreenSource, SyntheticSource};

    fn synth_i420() -> I420Frame {
        let mut src = SyntheticSource::new(320, 240, 1);
        let f: Frame = src.next_frame().expect("合成帧");
        I420Frame {
            width: f.width,
            height: f.height,
            i420: f.i420,
        }
    }

    #[test]
    fn encoder_produces_annexb_with_sps() {
        let opts = EncoderOptions {
            width: 320,
            height: 240,
            bitrate_bps: 500_000,
            max_fps: 15.0,
        };
        let mut enc = OpenH264Encoder::new(&opts).expect("编码器初始化");
        let out = enc.encode_i420(&synth_i420()).expect("编码");
        assert!(!out.is_empty(), "编码输出不应为空");
        // AnnexB：首帧含 SPS（NAL 类型 7，前缀 00 00 00 01 67）。
        let mut found_sps = false;
        for i in 0..out.len().saturating_sub(4) {
            if &out[i..i + 4] == &[0, 0, 0, 1] && out[i + 4] & 0x1f == 7 {
                found_sps = true;
                break;
            }
        }
        assert!(found_sps, "输出应含 SPS NAL（0x67）");
    }

    #[test]
    fn encoder_multiple_frames() {
        let opts = EncoderOptions {
            width: 160,
            height: 120,
            bitrate_bps: 200_000,
            max_fps: 10.0,
        };
        let mut enc = OpenH264Encoder::new(&opts).expect("编码器初始化");
        let mut src = SyntheticSource::new(160, 120, 5);
        let mut total_bytes = 0usize;
        while let Some(f) = src.next_frame() {
            let frame = I420Frame {
                width: f.width,
                height: f.height,
                i420: f.i420.clone(),
            };
            let out = enc.encode_i420(&frame).expect("编码");
            total_bytes += out.len();
            assert!(!out.is_empty());
        }
        assert!(total_bytes > 0, "多帧累计应有编码输出");
    }
}
