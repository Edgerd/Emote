//! `capture` —— 屏幕/画面采集（第 3.3 段）。
//!
//! 提供统一采集抽象 `ScreenSource` 与 `Frame`（I420）；
//! - `SyntheticSource`：确定性合成源，无显示环境的单测/全管线验证用它；
//! - `pinray_backend`（`capture` feature）：真机屏幕捕获，沙箱默认不编译。
//!
//! 捕获管理入口 `ScreenCapture` 负责选择后端；不可用时降级（返回 `None` 而非 panic）。

#[cfg(feature = "capture")]
pub mod pinray_backend;
pub mod synthetic;

pub use synthetic::SyntheticSource;

/// 一帧采集画面（I420 平面：`Y` + `Cb` + `Cr`，前 `w*h` 为 Y，其后 `w*h/4` 各为 Cb/Cr）。
#[derive(Debug, Clone)]
pub struct Frame {
    pub width: u32,
    pub height: u32,
    /// I420 原始像素（长度应为 `3*w*h/2`，宽高需为偶数）。
    pub i420: Vec<u8>,
}

impl Frame {
    /// Y 平面切片。
    pub fn y(&self) -> &[u8] {
        let n = (self.width * self.height) as usize;
        &self.i420[..n]
    }
    /// Cb 平面切片。
    pub fn cb(&self) -> &[u8] {
        let y = (self.width * self.height) as usize;
        let cb = y / 4;
        &self.i420[y..y + cb]
    }
    /// Cr 平面切片。
    pub fn cr(&self) -> &[u8] {
        let y = (self.width * self.height) as usize;
        let cb = y / 4;
        &self.i420[y + cb..]
    }
}

/// 屏幕画面来源。`next_frame` 在「无更多帧 / 源不可用」时返回 `None`，绝不 panic。
pub trait ScreenSource {
    /// 取下一帧画面。
    fn next_frame(&mut self) -> Option<Frame>;
    /// 当前宽高（偶数对齐）。
    fn size(&self) -> (u32, u32);
}

/// 捕获管理器：统一封装后端来源。
pub struct ScreenCapture {
    source: Box<dyn ScreenSource>,
}

impl ScreenCapture {
    /// 使用确定性合成源（无显示环境 / 单测 / 全管线验证）。
    pub fn synthetic(width: u32, height: u32, total_frames: u32) -> Self {
        Self {
            source: Box::new(SyntheticSource::new(width, height, total_frames)),
        }
    }

    /// 使用 pinray 真机捕获（需 `capture` feature；设备不可用时降级）。
    #[cfg(feature = "capture")]
    pub fn pinray(display: u32) -> anyhow::Result<Self> {
        Ok(Self {
            source: Box::new(pinray_backend::PinraySource::new(display)?),
        })
    }

    /// 取下一帧；无更多帧或源不可用时返回 `None`。
    pub fn next_frame(&mut self) -> Option<Frame> {
        self.source.next_frame()
    }

    /// 当前宽高。
    pub fn size(&self) -> (u32, u32) {
        self.source.size()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn synthetic_source_produces_deterministic_i420() {
        let mut a = SyntheticSource::new(64, 64, 3);
        let mut b = SyntheticSource::new(64, 64, 3);
        let fa = a.next_frame().expect("第 0 帧");
        let fb = b.next_frame().expect("第 0 帧");
        // 确定性：两次相同构造 → 相同数据
        assert_eq!(fa.i420, fb.i420);
        assert_eq!(fa.width, 64);
        assert_eq!(fa.height, 64);
        // I420 长度 = 3*w*h/2
        assert_eq!(fa.i420.len(), 3 * 64 * 64 / 2);
        // 取完 total 帧后结束
        let _ = a.next_frame();
        let _ = a.next_frame();
        assert!(a.next_frame().is_none(), "超过 total 帧后应无更多帧");
    }

    #[test]
    fn frame_planes_layout() {
        let f = Frame {
            width: 4,
            height: 4,
            i420: vec![1u8; 3 * 4 * 4 / 2],
        };
        assert_eq!(f.y().len(), 16);
        assert_eq!(f.cb().len(), 4);
        assert_eq!(f.cr().len(), 4);
    }
}
