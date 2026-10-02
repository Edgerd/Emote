//! connection —— 连接建立、心跳保活、超时检测与多连接管理（第 2.3 段）。
//!
//! - `manager`：多连接管理器（QUIC 优先、TCP 回退），供 FFI 侧同步调用。
//! - `handler`：单连接异步任务（心跳发送、超时判定、帧读写）。
//! - `reconnect`：断线自动重连策略（第 4.6 段，指数退避 + 抖动）。

pub mod handler;
pub mod manager;
pub mod reconnect;