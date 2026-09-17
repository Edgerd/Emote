//! `discovery` —— 局域网设备发现（第 2.2 段）。
//!
//! 基于 `mdns-sd` 实现 mDNS 服务广播与设备发现：
//! - `service`：注册本机 QUIC / TCP 服务并广播，通过 TXT 记录公布端口与传输层能力。
//! - `browser`：浏览 `_emote._udp.local.` 与 `_emote._tcp.local.`，解析 TXT 并维护设备列表。
//!
//! 本段不涉及 QUIC/TCP 连接与心跳。

pub mod browser;
pub mod service;

use std::collections::HashMap;
use std::sync::RwLock;
use std::time::Duration;

use tokio::sync::mpsc;

use crate::protocol::{DeviceInfo, DiscoveryState, Transport};

pub use browser::{Browser, DiscoveryEvent};
pub use service::DiscoveryService;

/// 设备列表变更事件（预留接口，本段通过 `Receiver` 消费）。
#[derive(Debug, Clone)]
pub enum DiscoveryEventPublic {
    DeviceAdded(DeviceInfo),
    DeviceUpdated(DeviceInfo),
    DeviceRemoved(String),
}

/// 发现模块对外状态句柄。
pub struct DiscoveryStateHandle {
    devices: RwLock<HashMap<String, DeviceInfo>>,
    state: RwLock<DiscoveryState>,
}

impl Default for DiscoveryStateHandle {
    fn default() -> Self {
        Self::new()
    }
}

impl DiscoveryStateHandle {
    pub fn new() -> Self {
        DiscoveryStateHandle {
            devices: RwLock::new(HashMap::new()),
            state: RwLock::new(DiscoveryState::Stopped),
        }
    }

    /// 让 `mdns-sd` 回调用起来轻量：进程级缓存，避免回调线程里持有锁过久。
    pub(crate) fn set_state(&self, s: DiscoveryState) {
        *self.state.write().unwrap() = s;
    }

    pub fn state(&self) -> DiscoveryState {
        *self.state.read().unwrap()
    }

    pub fn upsert(&self, dev: DeviceInfo) {
        let mut map = self.devices.write().unwrap();
        map.insert(dev.id.clone(), dev);
    }

    pub fn remove(&self, id: &str) {
        self.devices.write().unwrap().remove(id);
    }

    pub fn list(&self) -> Vec<DeviceInfo> {
        let mut v: Vec<DeviceInfo> = self.devices.read().unwrap().values().cloned().collect();
        v.sort_by(|a, b| a.name.cmp(&b.name));
        v
    }
}

/// 启动发现任务的默认心跳给浏览器的轮询周期（2 秒）。
pub const BROWSE_REFRESH_INTERVAL: Duration = Duration::from_secs(2);

/// 供上层（FFI）创建的事件通道：返回 sender，持续上报设备与状态事件。
pub type DiscoverySender = mpsc::Sender<DiscoveryEvent>;

/// 创建足够容量的发现事件通道。
pub fn channel(buffer: usize) -> (mpsc::Sender<DiscoveryEvent>, mpsc::Receiver<DiscoveryEvent>) {
    mpsc::channel(buffer)
}

// 测试辅助：确保两个实例在同一运行时下可用。
#[allow(dead_code)]
fn _transport_label(t: Transport) -> &'static str {
    t.as_str()
}