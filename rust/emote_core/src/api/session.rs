//! `api::session` —— 远控会话对外 FFI（第 3.6 段）。
//!
//! 把 `session::SessionManager` 封装为不透明句柄，供 Dart 侧 `RemoteSessionService` 管理
//! 三方向会话（scrcpy / 桌面自控制 / 桌面被控制）：创建、启停、下发输入、拉取解码帧。
//! 能力缺失时各方法返回 `Ok`（no-op）或 `None`，不 panic。

use anyhow::Result;

use crate::input::TouchAction;
use crate::session::{
    SessionConfig, SessionDirection, SessionManager, SessionState, VideoFrame,
};

/// 远控会话对外统一**不透明句柄**：内部持有并发会话管理器。
pub struct SessionHandle {
    mgr: SessionManager,
}

impl SessionHandle {
    /// 创建会话管理器。
    pub fn new() -> Result<Self> {
        Ok(Self {
            mgr: SessionManager::new(),
        })
    }

    /// 依方向创建会话（分辨率宽高偶数对齐）。
    pub fn create(
        &self,
        id: &str,
        direction: SessionDirection,
        width: u32,
        height: u32,
    ) -> Result<()> {
        let mut cfg = SessionConfig::default();
        cfg.direction = direction;
        cfg.width = width;
        cfg.height = height;
        self.mgr.create(id, &cfg)
    }

    /// 启动会话。
    pub fn start(&self, id: &str) -> Result<()> {
        self.mgr.start(id)
    }

    /// 停止会话。
    pub fn stop(&self, id: &str) -> Result<()> {
        self.mgr.stop(id)
    }

    /// 查询会话状态（无该会话返回 `None`）。
    #[must_use]
    pub fn state(&self, id: &str) -> Option<SessionState> {
        self.mgr.state(id)
    }

    /// 拉取一帧解码画面（RGBA8）；无则 `None`。
    #[must_use]
    pub fn next_frame(&self, id: &str) -> Option<VideoFrame> {
        self.mgr.next_decoded(id)
    }

    /// 下发按键（keycode 用 Android/Linux EV 码）。
    pub fn input_key(&self, id: &str, keycode: u32, down: bool) -> Result<()> {
        self.mgr.input(
            id,
            &crate::input::InputEvent::Key {
                keycode,
                down,
            },
        )
    }

    /// 下发触摸（`action`: 0=Down, 1=Move, 2=Up）。
    pub fn input_touch(&self, id: &str, x: u32, y: u32, action: u8) -> Result<()> {
        let act = match action {
            1 => TouchAction::Move,
            2 => TouchAction::Up,
            _ => TouchAction::Down,
        };
        self.mgr.input(
            id,
            &crate::input::InputEvent::Touch {
                x,
                y,
                action: act,
            },
        )
    }

    /// 下发滚动。
    pub fn input_scroll(&self, id: &str, x: u32, y: u32, hscroll: f32, vscroll: f32) -> Result<()> {
        self.mgr.input(
            id,
            &crate::input::InputEvent::Scroll {
                x,
                y,
                hscroll,
                vscroll,
            },
        )
    }

    /// 当前 target 是否具备软编解码后端（降级探测）。
    #[must_use]
    pub fn codec_available(&self) -> bool {
        crate::encoder::encoder_available() && crate::decoder::decoder_available()
    }

    /// 当前可用的输入注入后端名（探测降级；无则 `"null"`）。
    #[must_use]
    pub fn probe_input_backend(&self) -> String {
        crate::input::InputDispatcher::new().sink_name().to_string()
    }
}

impl Default for SessionHandle {
    fn default() -> Self {
        Self::new().expect("SessionHandle::new 不应失败")
    }
}
