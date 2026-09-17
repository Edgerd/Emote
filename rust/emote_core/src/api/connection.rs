//! `api::connection` —— 暴露给 Flutter(Dart) 的**连接管理** FFI 接口（第 2.4 段）。
//!
//! 把 `connection::manager::ConnectionManager` 封装为不透明句柄，供 Dart 侧
//! `ConnectionService` 建立/断开与设备的 QUIC(优先)/TCP(回退) 连接、查询状态并下发心跳。

use anyhow::Result;

use crate::connection::manager::ConnectionManager;
use crate::protocol::{ConnectionState, DeviceInfo, MessageType};
use crate::transport::ActiveTransport;

/// 连接管理对外统一的**不透明句柄**：内部持有 tokio 运行时与多连接表。
pub struct ConnectionHandle {
    manager: ConnectionManager,
}

impl ConnectionHandle {
    /// 创建一个连接管理器（惰性启动 tokio 运行时）。
    pub fn new() -> Result<Self> {
        Ok(ConnectionHandle {
            manager: ConnectionManager::new()?,
        })
    }

    /// 建立到设备的连接：优先 QUIC，失败回退 TCP。
    pub fn connect(&self, dev: &DeviceInfo) -> Result<ConnectionState> {
        self.manager.connect_to_device(dev)
    }

    /// 断开指定设备连接。
    pub fn disconnect(&self, id: String) -> Result<()> {
        self.manager.disconnect(&id)
    }

    /// 查询指定设备连接状态。
    pub fn state(&self, id: String) -> ConnectionState {
        self.manager.get_connection_state(&id)
    }

    /// 当前生效的传输层（未连接时为 None）。
    pub fn active_transport(&self, id: String) -> Option<ActiveTransport> {
        self.manager.get_active_transport(&id)
    }

    /// 向指定连接发送一帧控制消息（静默丢弃接收到的业务帧，由上层按需消费）。
    pub fn send(&self, id: String, msg_type: MessageType, payload: Vec<u8>) -> Result<()> {
        self.manager.send_message(&id, msg_type, &payload)
    }
}