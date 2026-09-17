//! `api::discovery` —— 暴露给 Flutter(Dart) 的**设备发现** FFI 接口（第 2.4 段）。
//!
//! 把 `discovery` 模块的广播 + 浏览能力封装为单个不透明句柄
//! [`DiscoveryHandle`]，供 Dart 侧 `DiscoveryService` 轮询设备列表与状态。

use std::sync::Arc;

use anyhow::{Context, Result};

use crate::discovery::Browser;
use crate::discovery::DiscoveryStateHandle;
use crate::discovery::service::{DiscoveryService, LocalDeviceConfig};
use crate::protocol::{DeviceInfo, DiscoveryState, DeviceSystem, Transport};

/// 设备广播参数（由 Dart 侧 `DiscoveryService` 传入）。
#[derive(Debug, Clone)]
pub struct BroadcastConfig {
    /// 设备唯一 ID（UUID v4）。
    pub id: String,
    /// 显示名（如 “Edgerd-Desktop”）。
    pub name: String,
    /// 系统类型。
    pub system: DeviceSystem,
    /// QUIC 监听端口。
    pub quic_port: u16,
    /// TCP 监听端口。
    pub tcp_port: u16,
    /// 首选传输层。
    pub preferred_transport: Transport,
    /// 协议版本，如 "1.0.0"。
    pub protocol_version: String,
}

impl BroadcastConfig {
    fn into_local(self) -> LocalDeviceConfig {
        LocalDeviceConfig {
            id: self.id,
            name: self.name,
            system: self.system,
            quic_port: self.quic_port,
            tcp_port: self.tcp_port,
            preferred_transport: self.preferred_transport,
            protocol_version: self.protocol_version,
        }
    }
}

/// 发现模块对外统一的**不透明句柄**：持有广播服务、浏览器与共享设备/状态缓存。
pub struct DiscoveryHandle {
    service: Option<DiscoveryService>,
    browser: Option<Browser>,
    handle: Arc<DiscoveryStateHandle>,
}

impl Default for DiscoveryHandle {
    fn default() -> Self {
        Self::new()
    }
}

impl DiscoveryHandle {
    /// 创建一个空句柄（未开始广播/浏览）。
    pub fn new() -> Self {
        DiscoveryHandle {
            service: None,
            browser: None,
            handle: Arc::new(DiscoveryStateHandle::new()),
        }
    }

    /// 启动 mDNS 广播（让本机可被其他设备发现）。
    pub fn start_broadcast(&mut self, cfg: BroadcastConfig, host_ip: String) -> Result<()> {
        if self.service.is_some() {
            return Ok(()); // 已在广播，幂等
        }
        let svc = DiscoveryService::start(&cfg.into_local(), &host_ip)
            .context("启动 mDNS 广播失败")?;
        self.service = Some(svc);
        Ok(())
    }

    /// 停止 mDNS 广播。
    pub fn stop_broadcast(&mut self) {
        if let Some(svc) = self.service.take() {
            svc.stop();
        }
    }

    /// 启动 mDNS 浏览（发现局域网内其他设备，填充共享缓存）。
    pub fn start_browse(&mut self) -> Result<()> {
        if self.browser.is_some() {
            return Ok(()); // 已在浏览，幂等
        }
        let daemon = Arc::new(
            mdns_sd::ServiceDaemon::new().context("创建 mDNS 浏览守护进程失败")?,
        );
        // 事件通道仅用于向浏览器提供合法 sender；列表/状态经共享缓存读取。
        let (sink, _rx) = crate::discovery::channel(16);
        self.handle.set_state(DiscoveryState::Starting);
        let browser = Browser::start(daemon, self.handle.clone(), sink);
        self.browser = Some(browser);
        Ok(())
    }

    /// 停止 mDNS 浏览。
    pub fn stop_browse(&mut self) {
        if let Some(b) = self.browser.take() {
            b.stop();
        }
    }

    /// 当前已发现的设备列表（按名称排序）。
    pub fn list_devices(&self) -> Vec<DeviceInfo> {
        self.handle.list()
    }

    /// 当前发现状态。
    pub fn state(&self) -> DiscoveryState {
        self.handle.state()
    }
}