//! `connection::manager` —— 连接管理器（第 2.3 段）。
//!
//! 维护 `设备ID -> ConnectionHandle` 的多连接表：
//! - 默认优先 QUIC，连接失败或超时后回退 TCP；
//! - 每连接在独立异步任务中处理心跳与断线检测（`handler`）；
//! - 自身持有 tokio 运行时与 QUIC 客户端端点，供同步 FFI 调用方使用。

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use dashmap::DashMap;
use tokio::sync::mpsc;

use crate::protocol::{ConnectionState, DeviceInfo, MessageType};
use crate::transport::{ActiveTransport, Link};
use crate::transport::{quic, tcp};

use super::handler::{HandlerConfig, Outbound, SharedState, spawn};

/// 连接管理器的可调参数（默认由协议常量派生）。
#[derive(Debug, Clone, Copy)]
pub struct ConnectionConfig {
    pub heartbeat_interval: Duration,
    pub heartbeat_timeout: Duration,
    pub quic_connect_timeout: Duration,
    pub tcp_connect_timeout: Duration,
    pub prefer_quic: bool,
}

impl Default for ConnectionConfig {
    fn default() -> Self {
        ConnectionConfig {
            heartbeat_interval: Duration::from_secs(crate::protocol::HEARTBEAT_INTERVAL_SECS),
            heartbeat_timeout: Duration::from_secs(crate::protocol::HEARTBEAT_TIMEOUT_SECS),
            quic_connect_timeout: Duration::from_secs(4),
            tcp_connect_timeout: Duration::from_secs(4),
            prefer_quic: true,
        }
    }
}

/// 一条被管理连接对外的句柄。
struct ManagedConn {
    shared: Arc<SharedState>,
    tx: mpsc::UnboundedSender<Outbound>,
}

/// 连接管理器：线程安全，支持多连接并行。
pub struct ConnectionManager {
    connections: DashMap<String, ManagedConn>,
    quic_endpoint: quinn::Endpoint,
    runtime: tokio::runtime::Runtime,
    cfg: ConnectionConfig,
}

impl ConnectionManager {
    /// 创建管理器并启动 tokio 运行时与 QUIC 客户端端点。
    pub fn new() -> Result<Self> {
        Self::with_config(ConnectionConfig::default())
    }

    /// 以自定义参数创建管理器（测试注入短周期心跳/超时）。
    pub fn with_config(cfg: ConnectionConfig) -> Result<Self> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .context("创建 tokio 运行时失败")?;
        let quic_endpoint = runtime.block_on(make_quic_client())?;
        Ok(ConnectionManager {
            connections: DashMap::new(),
            quic_endpoint,
            runtime,
            cfg,
        })
    }

    /// 建立到设备的连接：优先 QUIC，失败回退 TCP。
    pub fn connect_to_device(&self, dev: &DeviceInfo) -> Result<ConnectionState> {
        if self.connections.contains_key(&dev.id) {
            return Ok(self.get_connection_state(&dev.id));
        }
        let target = self.runtime.block_on(self.connect_async(dev))?;
        debug_assert_eq!(
            target.shared.get().state,
            ConnectionState::Connected,
            "连接建立后应处于 Connected"
        );
        let conn_state = target.shared.get().state;
        self.connections.insert(dev.id.clone(), target);
        Ok(conn_state)
    }

    /// 断开指定设备连接。
    pub fn disconnect(&self, id: &str) -> Result<()> {
        let Some(conn) = self.connections.remove(id) else {
            return Ok(());
        };
        let _ = conn.1.tx.send(Outbound::Close);
        Ok(())
    }

    /// 查询指定设备连接状态。
    pub fn get_connection_state(&self, id: &str) -> ConnectionState {
        match self.connections.get(id) {
            Some(conn) => conn.shared.get().state,
            None => ConnectionState::Disconnected,
        }
    }

    /// 查询指定连接当前生效的传输层。
    pub fn get_active_transport(&self, id: &str) -> Option<ActiveTransport> {
        self.connections.get(id).map(|c| c.shared.get().transport)
    }

    /// 向指定连接发送一帧业务消息。
    pub fn send_message(&self, id: &str, msg_type: MessageType, payload: &[u8]) -> Result<()> {
        let conn = self
            .connections
            .get(id)
            .ok_or_else(|| anyhow::anyhow!("设备 {id} 未连接"))?;
        conn.tx
            .send(Outbound::Send {
                msg_type,
                payload: payload.to_vec(),
            })
            .map_err(|_| anyhow::anyhow!("设备 {id} 连接已关闭"))?;
        Ok(())
    }

    async fn connect_async(&self, dev: &DeviceInfo) -> Result<ManagedConn> {
        let quic_addr = to_socket_addr(&dev.ip, dev.quic_port)?;
        let tcp_addr = to_socket_addr(&dev.ip, dev.tcp_port)?;

        // 优先 QUIC
        if self.cfg.prefer_quic {
            if let Ok(Some(link)) = self
                .try_quic(dev, quic_addr)
                .await
            {
                return Ok(self.adopt(link));
            }
        }
        // 回退 TCP
        let link = self
            .try_tcp(tcp_addr)
            .await
            .context("QUIC 与 TCP 均连接失败")?;
        Ok(self.adopt(link))
    }

    async fn try_quic(&self, dev: &DeviceInfo, addr: SocketAddr) -> Result<Option<Link>> {
        match tokio::time::timeout(self.cfg.quic_connect_timeout, quic::connect(&self.quic_endpoint, addr)).await {
            Ok(Ok(link)) => {
                tracing::debug!(id = %dev.id, "QUIC 建连成功");
                Ok(Some(link))
            }
            Ok(Err(e)) => {
                tracing::warn!(id = %dev.id, error = %e, "QUIC 建连失败，尝试回退 TCP");
                Ok(None)
            }
            Err(_) => {
                tracing::warn!(id = %dev.id, "QUIC 建连超时，尝试回退 TCP");
                Ok(None)
            }
        }
    }

    async fn try_tcp(&self, addr: SocketAddr) -> Result<Link> {
        tokio::time::timeout(self.cfg.tcp_connect_timeout, tcp::connect(addr, true))
            .await
            .context("TCP 建连超时")?
            .context("TCP 建连失败")
    }

    /// 把已建连的链路接入 handler 任务并返回受管句柄。
    fn adopt(&self, link: Link) -> ManagedConn {
        let transport = link.transport;
        let shared = Arc::new(SharedState::new(transport));
        let (send, rx_frames) = link.split();
        let (tx, rx_cmd) = mpsc::unbounded_channel();
        spawn(
            send,
            rx_frames,
            rx_cmd,
            shared.clone(),
            HandlerConfig {
                heartbeat_interval: self.cfg.heartbeat_interval,
                heartbeat_timeout: self.cfg.heartbeat_timeout,
            },
        );
        ManagedConn {
            shared,
            tx,
        }
    }
}

async fn make_quic_client() -> Result<quinn::Endpoint> {
    quic::make_client_endpoint("0.0.0.0:0".parse().context("解析本地绑定地址失败")?)
}

fn to_socket_addr(ip: &str, port: u16) -> Result<SocketAddr> {
    format!("{ip}:{port}").parse().context("非法设备地址")
}