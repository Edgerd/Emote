//! transport —— 传输层入口，负责在 QUIC（默认）与 TCP（回退）之间路由选择。
//!
//! 默认传输层 QUIC，回退传输层 TCP；`mod.rs` 提供统一的事件与数据面接口。

pub mod quic;
pub mod tcp;