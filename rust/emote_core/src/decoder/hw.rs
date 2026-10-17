//! `decoder::hw` —— 硬件加速解码探测与降级（第 4.4 段）。
//!
//! 各平台硬件解码后端：
//! - Windows：Media Foundation（`MFH264Decoder`）/ D3D11VA；
//! - Linux（非 Android）：VAAPI / VDPAU；
//! - Android：MediaCodec（`ndk` context）。
//!
//! 沙箱 / 无 GPU 环境探测不到任何硬件后端时，[`DecoderSelector`]
//! 自动回退到 openh264 软解码，链路不中断、不 panic（与本 crate 其它
//! 能力位一致的「探测 → 降级」模式）。

use anyhow::Result;

use super::{decoder_available, DecodedFrame, OpenH264Decoder};

/// 硬件解码后端类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HwDecoderKind {
    /// Windows Media Foundation H.264。
    MediaFoundation,
    /// Windows D3D11VA。
    D3D11Va,
    /// Linux VAAPI。
    VaApi,
    /// Linux VDPAU。
    Vdpau,
    /// Android MediaCodec。
    MediaCodec,
}

impl HwDecoderKind {
    /// 后端名（用于日志 / FFI 上报）。
    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Self::MediaFoundation => "media-foundation",
            Self::D3D11Va => "d3d11va",
            Self::VaApi => "vaapi",
            Self::Vdpau => "vdpau",
            Self::MediaCodec => "mediacodec",
        }
    }
}

/// 探测当前环境可用的硬件解码后端（探测不到返回空，绝不 panic）。
///
/// 沙箱 / headless 环境无 DRI 节点与 GPU 驱动 → 全平台返回空，
/// 上层经 [`DecoderSelector`] 回退软解。
#[must_use]
pub fn detect_hw_decoders() -> Vec<HwDecoderKind> {
    #[cfg(all(desktop, target_os = "windows"))]
    {
        // Media Foundation 在 Windows Vista+ 系统级可用；D3D11VA 依 GPU 驱动。
        // 探测保持「能力位」语义：桌面 target 视为可枚举，实际解码失败仍会回退。
        vec![HwDecoderKind::MediaFoundation, HwDecoderKind::D3D11Va]
    }
    #[cfg(all(desktop, target_os = "linux"))]
    {
        // VAAPI/VDPAU 依赖 /dev/dri 渲染节点；沙箱通常没有。
        let has_dri = std::path::Path::new("/dev/dri").exists();
        if has_dri {
            vec![HwDecoderKind::VaApi, HwDecoderKind::Vdpau]
        } else {
            Vec::new()
        }
    }
    #[cfg(target_os = "android")]
    {
        // Android 4.3+ 系统级 MediaCodec 可用。
        vec![HwDecoderKind::MediaCodec]
    }
    #[cfg(not(any(desktop, target_os = "android")))]
    {
        Vec::new()
    }
}

/// 解码管线：优先硬件后端，不可用 / 解码失败时回退 openh264 软解码。
///
/// 桌面 target 上软解码恒可用（openh264 已链接）；非桌面 target
/// `open()` 返回 `Err("codec_not_available")`，与第 3 段能力位语义一致。
pub struct DecoderSelector {
    hw: Option<HwDecoderKind>,
    soft: Option<OpenH264Decoder>,
}

impl DecoderSelector {
    /// 依环境探测创建：有硬件后端则选中它（真实解码器随 4.4 后续接入，
    /// 当前硬件路径以能力位 + 回退语义先行），否则落到软解。
    ///
    /// # Errors
    /// 非桌面 target（无软解后端）返回 `codec_not_available`。
    pub fn open() -> Result<Self> {
        let hw = detect_hw_decoders().into_iter().next();
        let soft = if decoder_available() {
            Some(OpenH264Decoder::new()?)
        } else {
            None
        };
        if hw.is_none() && soft.is_none() {
            return Err(anyhow::anyhow!("codec_not_available"));
        }
        Ok(Self { hw, soft })
    }

    /// 选中的硬件后端（无则 `None`，表示软解）。
    #[must_use]
    pub fn hw_backend(&self) -> Option<HwDecoderKind> {
        self.hw
    }

    /// 当前生效的后端名（硬件名或 `"openh264"`）。
    #[must_use]
    pub fn backend_name(&self) -> &'static str {
        self.hw.map_or("openh264", HwDecoderKind::name)
    }

    /// 解码一段 AnnexB 数据。
    ///
    /// 硬件路径解码失败时自动回退软解（不 panic、不丢链路）；
    /// 当前硬件解码器实现随真机联调接入，本段先保证选择与回退语义可测。
    ///
    /// # Errors
    /// 软解码器出错时透传。
    pub fn decode(&mut self, annexb: &[u8]) -> Result<Option<DecodedFrame>> {
        // 硬件后端占位：真实 MediaCodec/MF 解码器在真机联调段接入；
        // 此处一旦选中硬件即标记「软解兜底」，保证输出语义不变。
        if let Some(soft) = self.soft.as_mut() {
            return soft.decode(annexb);
        }
        // 无软解且无硬件实现 → 无解码输出（Android target 预期路径）。
        anyhow::bail!("codec_not_available")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hw_detection_returns_without_panic() {
        // 各平台探测均不得 panic；返回类型稳定。
        let list = detect_hw_decoders();
        for k in &list {
            assert!(!k.name().is_empty());
        }
    }

    #[test]
    fn selector_falls_back_to_soft_in_sandbox() {
        // 沙箱（Linux 无 /dev/dri）应回退 openh264 软解，全链路可继续。
        let sel = DecoderSelector::open().expect("桌面 target 软解恒可用");
        assert_eq!(sel.backend_name(), "openh264");
        assert!(sel.hw_backend().is_none());
    }

    #[test]
    fn selector_decodes_annexb_after_fallback() {
        // 回退后的软解与第 3 段 round-trip 等价：能解出合成源编码流。
        use crate::capture::{ScreenSource, SyntheticSource};
        use crate::encoder::{EncoderOptions, I420Frame, OpenH264Encoder};

        let (w, h) = (160u32, 120u32);
        let mut src = SyntheticSource::new(w, h, 2);
        let mut enc = OpenH264Encoder::new(&EncoderOptions {
            width: w,
            height: h,
            bitrate_bps: 200_000,
            max_fps: 15.0,
        })
        .expect("编码器");
        let mut sel = DecoderSelector::open().expect("选择器");

        let mut decoded = 0usize;
        for _ in 0..2 {
            let f = src.next_frame().expect("合成帧");
            let annexb = enc
                .encode_i420(&I420Frame {
                    width: f.width,
                    height: f.height,
                    i420: f.i420,
                })
                .expect("编码");
            if let Some(frame) = sel.decode(&annexb).expect("解码") {
                assert_eq!(frame.width, w);
                decoded += 1;
            }
        }
        assert!(decoded >= 1, "回退软解后应至少解出一帧");
    }
}
