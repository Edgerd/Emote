//! emote_core —— Emote 跨平台远程控制的核心库。
//!
//! 架构分层：
//! - `api`：对外暴露给 Flutter(Dart) 的 FFI 接口（flutter_rust_bridge）。
//! - `transport`：默认 QUIC、回退 TCP 的双传输层。
//! - `discovery` / `connection` / `session`：局域网发现、连接与会话管理。
//! - `scrcpy` / `capture` / `encoder` / `decoder`：画面采集与编解码。
//! - `input`：远端输入注入（Linux 走 reis/libei 或 D-Bus portal，uinput 走内核接口）。
//! - `metrics`：性能监控采集与上报。
//! - `platform`：跨平台抽象层（iOS/macOS 暂不实现）。
//!
//! 本段仅实现 `api::simple::greet`，其余模块为占位骨架，后续分段逐段填充。

pub mod api;
mod frb_generated; // 由 flutter_rust_bridge_codegen 自动生成的 FFI 桥接入口

pub mod discovery;
pub mod connection;
pub mod transport;
pub mod scrcpy;
pub mod capture;
pub mod encoder;
pub mod decoder;
pub mod input;
pub mod session;
pub mod metrics;
pub mod platform;