//! `session` —— 三方向远控会话（第 3.6–3.9 段）。
//!
//! - `ScrcpySession`（3.7，Win/Lin→Android，复用 scrcpy + ADB）
//! - `DesktopSelfSession`（3.8，Windows→Windows 本机自控制）
//! - `DesktopFromSession`（3.9，Linux→Windows，Linux 控制 Windows）
//! - `SessionManager`：按设备 id 管理多会话（并发安全，`DashMap`）。
//!
//! 会话统一走 `capture → encode → (通道) → decode → 帧` 的**可测管线**；无真机/无显示时
//! 用合成源 + 软件编解码跑通，输入注入经 `InputDispatcher` 探测降级，绝不 panic。

pub mod sessions;

use anyhow::{anyhow, Result};
use dashmap::DashMap;

use crate::codec::H264FrameType;
use crate::input::InputEvent;

pub use sessions::{DesktopFromSession, DesktopSelfSession, ScrcpySession};

/// 会话方向（对应 3.7 / 3.8 / 3.9）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionDirection {
    /// Win/Lin 控制 Android（scrcpy + ADB）。
    Scrcpy,
    /// Windows → Windows 本机自控制。
    DesktopSelf,
    /// Linux → Windows（Linux 控制 Windows）。
    DesktopFrom,
}

/// 会话生命周期状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SessionState {
    #[default]
    Stopped,
    Running,
    /// 因缺少能力（codec/捕获/输入）而优雅结束。
    Ended,
}

/// 输入注入模式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InputMode {
    /// 仅记录，不注入。
    #[default]
    None,
    /// 经控制通道下发（scrcpy / 远端）。
    ControlOnly,
    /// 本地输入注入（桌面端，经 `InputDispatcher`）。
    Inject,
    /// 控制通道 + 本地注入。
    Both,
}

/// 视频参数。
#[derive(Debug, Clone, Copy)]
pub struct VideoOptions {
    pub max_size: u32,
    pub bit_rate: u32,
    pub max_fps: u32,
}

impl Default for VideoOptions {
    fn default() -> Self {
        Self {
            max_size: 1080,
            bit_rate: 2_000_000,
            max_fps: 0,
        }
    }
}

/// 会话配置。
#[derive(Debug, Clone)]
pub struct SessionConfig {
    pub direction: SessionDirection,
    pub input_mode: InputMode,
    pub video: VideoOptions,
    /// 目标/合成分辨率（偶数）。
    pub width: u32,
    pub height: u32,
}

impl Default for SessionConfig {
    fn default() -> Self {
        Self {
            direction: SessionDirection::DesktopFrom,
            input_mode: InputMode::ControlOnly,
            video: VideoOptions::default(),
            width: 320,
            height: 240,
        }
    }
}

/// 统一远控会话接口（三方向共用）。
///
/// `Send + Sync` 使 `SessionManager` 的 `DashMap<String, Box<dyn RemoteSession>>` 可跨线程共享
/// （FFI `SessionHandle` 不透明句柄需在 Rust/Dart 线程边界传递，`flutter_rust_bridge` 要求
/// 其内部值 `Send + Sync`）。各具体会话的字段（openh264 编解码器、输入后端、`dyn ScreenSource`）
/// 均已是 `Send + Sync`。
pub trait RemoteSession: Send + Sync {
    /// 会话方向。
    fn direction(&self) -> SessionDirection;
    /// 启动会话；缺少能力时返回 `Ended` 而非 panic。
    fn start(&mut self) -> Result<()>;
    /// 停止会话。
    fn stop(&mut self);
    /// 当前状态。
    fn state(&self) -> SessionState;
    /// 下发一个输入事件（方向不支持时降级为 `Ok` no-op，不 panic）。
    fn input(&mut self, ev: &InputEvent) -> Result<()>;
    /// 取一帧解码画面（被控制端 / scrcpy 端；编码端返回 `None`）。
    fn next_decoded(&mut self) -> Option<VideoFrame> {
        None
    }
}

/// 会话管理器：按设备 id 管理多会话。
#[derive(Default)]
pub struct SessionManager {
    sessions: DashMap<String, Box<dyn RemoteSession>>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// 依配置创建并登记一个会话（不自动启动）。
    pub fn create(&self, id: &str, cfg: &SessionConfig) -> Result<()> {
        if self.sessions.contains_key(id) {
            return Err(anyhow!("会话 {id} 已存在"));
        }
        let session: Box<dyn RemoteSession> = match cfg.direction {
            SessionDirection::Scrcpy => Box::new(ScrcpySession::new(cfg)),
            SessionDirection::DesktopSelf => Box::new(DesktopSelfSession::new(cfg)),
            SessionDirection::DesktopFrom => Box::new(DesktopFromSession::new(cfg)),
        };
        self.sessions.insert(id.to_string(), session);
        Ok(())
    }

    /// 启动指定会话。
    pub fn start(&self, id: &str) -> Result<()> {
        let mut guard = self.sessions.get_mut(id).ok_or_else(|| anyhow!("无会话 {id}"))?;
        guard.start()
    }

    /// 停止指定会话。
    pub fn stop(&self, id: &str) -> Result<()> {
        let mut guard = self.sessions.get_mut(id).ok_or_else(|| anyhow!("无会话 {id}"))?;
        guard.stop();
        Ok(())
    }

    /// 查询会话状态（无该会话返回 `None`）。
    #[must_use]
    pub fn state(&self, id: &str) -> Option<SessionState> {
        self.sessions.get(id).map(|s| s.state())
    }

    /// 取某会话的一帧解码画面（被控制端 / scrcpy 端；无则 `None`）。
    #[must_use]
    pub fn next_decoded(&self, id: &str) -> Option<VideoFrame> {
        self.sessions.get_mut(id).and_then(|mut g| g.next_decoded())
    }

    /// 向会话下发输入事件。
    pub fn input(&self, id: &str, ev: &InputEvent) -> Result<()> {
        let mut guard = self.sessions.get_mut(id).ok_or_else(|| anyhow!("无会话 {id}"))?;
        guard.input(ev)
    }

    /// 移除并返回某会话。
    pub fn remove(&self, id: &str) -> Option<Box<dyn RemoteSession>> {
        self.sessions.remove(id).map(|(_, v)| v)
    }

    /// 当前会话数。
    #[must_use]
    pub fn count(&self) -> usize {
        self.sessions.len()
    }

    /// 清空所有会话。
    pub fn clear(&self) {
        self.sessions.clear();
    }
}

/// 会话产出的 H.264 帧（编码端 / 解码端通用）。
#[derive(Debug, Clone)]
pub struct VideoFrame {
    pub width: u32,
    pub height: u32,
    pub frame_type: H264FrameType,
    /// AnnexB 压缩流（编码端）或 RGBA8（解码端），由 `is_decoded` 区分。
    pub data: Vec<u8>,
    /// `true` 表示是解码后的 RGBA8，`false` 表示 AnnexB 压缩流。
    pub is_decoded: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manager_lifecycle_three_directions() {
        let mgr = SessionManager::new();
        for (id, dir) in [
            ("dev-a", SessionDirection::Scrcpy),
            ("dev-b", SessionDirection::DesktopSelf),
            ("dev-c", SessionDirection::DesktopFrom),
        ] {
            let mut cfg = SessionConfig::default();
            cfg.direction = dir;
            cfg.width = 160;
            cfg.height = 120;
            mgr.create(id, &cfg).expect("create");
            mgr.start(id).expect("start");
            assert_eq!(mgr.state(id), Some(SessionState::Running), "{id} 应 Running");
        }
        assert_eq!(mgr.count(), 3);
        // 向 from 会话下发输入（探测降级，不 panic）。
        let _ = mgr.input(
            "dev-c",
            &InputEvent::Key {
                keycode: 30,
                down: true,
            },
        );
        for id in ["dev-a", "dev-b", "dev-c"] {
            mgr.stop(id).expect("stop");
            assert_eq!(mgr.state(id), Some(SessionState::Stopped), "{id} 应 Stopped");
        }
        mgr.clear();
        assert_eq!(mgr.count(), 0);
    }

    #[test]
    fn manager_rejects_duplicate_id() {
        let mgr = SessionManager::new();
        mgr.create("x", &SessionConfig::default()).expect("create");
        assert!(mgr.create("x", &SessionConfig::default()).is_err(), "重复 id 应报错");
        assert_eq!(mgr.count(), 1);
    }

    /// 编译期断言：`SessionManager` 必须 `Send + Sync`（FRB 不透明句柄需在
    /// Rust/Dart 线程边界传递；若回归到非 `Send + Sync` 字段，此测试在编译期即失败）。
    #[test]
    fn session_manager_is_send_and_sync() {
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<SessionManager>();
    }
}
