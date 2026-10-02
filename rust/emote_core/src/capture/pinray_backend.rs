//! `capture::pinray_backend` —— pinray 真机屏幕捕获（`capture` feature；默认不编译）。
//!
//! 仅在具备 `capture` feature 时编译。pinray 依赖系统显示后端（X11/Wayland），
//! 沙箱/无显示环境无法验证——真机显示器上跑 `cargo build --features capture` 校验。

use pinray::{Display, Frame as PinrayFrame, PixelFormat};

use super::{Frame, ScreenSource};

/// pinray 屏幕捕获源。
pub struct PinraySource {
    display: u32,
    size: (u32, u32),
}

impl PinraySource {
    /// 构造：探测默认主显示器尺寸；无显示器时返回错误（降级，不 panic）。
    pub fn new(display: u32) -> anyhow::Result<Self> {
        let d = Display::default_or(display as i32).ok_or_else(|| {
            anyhow::anyhow!("pinray: 无可用显示器 display={display}（本环境无显示后端）")
        })?;
        let size = d.size();
        Ok(Self {
            display,
            size: (size.width() as u32, size.height() as u32),
        })
    }

    fn capture_once(&self) -> Option<PinrayFrame> {
        PinrayFrame::capture(self.display, PixelFormat::Yuv420, 50).ok()
    }
}

impl ScreenSource for PinraySource {
    fn next_frame(&mut self) -> Option<Frame> {
        let pf = self.capture_once()?;
        Some(Frame {
            width: self.size.0,
            height: self.size.1,
            i420: pf.data().to_vec(),
        })
    }

    fn size(&self) -> (u32, u32) {
        self.size
    }
}
