//! `scrcpy` —— Win/Lin 控制 Android 方向复用 scrcpy（第 3.1 段）。
//!
//! 基于 `scrcpy-protocol` crate（server 3.3.3）实现「scrcpy 协议层 + ADB 通道」：
//! - `adb`：经 `adb` 命令行建立设备通道、推送 server、端口转发、启动 server；
//! - `server`：scrcpy-server 启动参数；
//! - `video`：视频流 H.264 包解析（不解码）；
//! - `control`：控制消息发送（触摸/按键/文本/滚动，复用 `ControlSender`）。
//!
//! 本段不涉及视频渲染（第 3.6 段）与桌面端输入注入（第 3.5 段）。
//! 约束：使用 `scrcpy-protocol` crate，不重新实现协议；scrcpy-server 固定 3.3.3。

pub mod adb;
pub mod control;
pub mod server;
pub mod video;

// 复用 `scrcpy-protocol` 的协议常量与类型，作为 Emote 的统一对外入口。
pub use scrcpy_protocol::h264;
pub use scrcpy_protocol::protocol::video::VideoPacket;
pub use scrcpy_protocol::{
    ControlSender, MAX_PACKET_SIZE, SCRCPY_SERVER_CLASS_NAME, SCRCPY_SERVER_PATH,
    SCRCPY_SERVER_VERSION, ScrcpyError,
};
