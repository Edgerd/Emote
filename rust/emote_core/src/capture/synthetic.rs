//! `capture::synthetic` —— 确定性合成画面源（无显示环境的单测 / 全管线验证）。
//!
//! 每帧为「整帧常数亮度」的 I420，Y 值随帧序号缓慢变化（`16 + i%239`），
//! Cb/Cr 恒为 128。行为完全确定、可重复；取满 `total` 帧后 `next_frame` 返回 `None`。

use super::{Frame, ScreenSource};

/// 确定性合成源。
pub struct SyntheticSource {
    width: u32,
    height: u32,
    total: u32,
    produced: u32,
}

impl SyntheticSource {
    /// 构造：固定宽高、共 `total_frames` 帧（宽高自动向上取偶数）。
    #[must_use]
    pub fn new(width: u32, height: u32, total_frames: u32) -> Self {
        let width = width.next_multiple_of(2).max(2);
        let height = height.next_multiple_of(2).max(2);
        Self {
            width,
            height,
            total: total_frames,
            produced: 0,
        }
    }

    /// 生成第 `i` 帧（纯函数，可重复）。
    fn frame_at(&self, i: u32) -> Frame {
        let y_len = (self.width * self.height) as usize;
        let cb_len = y_len / 4;
        // Y 值随帧序号缓慢变化（限定在合法亮度范围 16..=255），保证 H.264 解码后高度接近原值。
        let y = 16u8 + (i % 239) as u8;
        let mut data = Vec::with_capacity(y_len * 3 / 2);
        data.resize(y_len, y);
        data.extend(std::iter::repeat(128u8).take(cb_len)); // Cb
        data.extend(std::iter::repeat(128u8).take(cb_len)); // Cr
        Frame {
            width: self.width,
            height: self.height,
            i420: data,
        }
    }
}

impl ScreenSource for SyntheticSource {
    fn next_frame(&mut self) -> Option<Frame> {
        if self.produced >= self.total {
            return None;
        }
        let frame = self.frame_at(self.produced);
        self.produced += 1;
        Some(frame)
    }

    fn size(&self) -> (u32, u32) {
        (self.width, self.height)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frames_are_deterministic_and_counted() {
        let mut s = SyntheticSource::new(16, 16, 4);
        let f0 = s.next_frame().unwrap();
        let f1 = s.next_frame().unwrap();
        let mut s2 = SyntheticSource::new(16, 16, 3);
        let g0 = s2.next_frame().unwrap();
        assert_eq!(f0.i420, g0.i420, "第 0 帧必须可重复");
        assert_ne!(f0.y()[0], f1.y()[0], "相邻帧 Y 值应变化");
        assert!(s2.next_frame().is_some(), "第 1 帧");
        assert!(s2.next_frame().is_some(), "第 2 帧");
        assert!(s2.next_frame().is_none(), "满 3 帧后结束");
    }
}
