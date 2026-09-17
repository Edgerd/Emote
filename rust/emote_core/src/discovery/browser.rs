//! `discovery::browser` —— mDNS 设备发现（第 2.2 段）。
//!
//! 浏览 `_emote._udp.local.` 与 `_emote._tcp.local.` 服务类型，解析 TXT 记录，
//! 合并为对外的 `DeviceInfo` 列表，并投递到事件通道。

use std::collections::HashMap;
use std::sync::{Arc, Mutex, atomic::AtomicBool, atomic::Ordering};
use std::thread;
use std::time::Duration;

use mdns_sd::{Receiver, ServiceDaemon, ServiceEvent};
use tokio::sync::mpsc;
use tracing::{debug, error, info};

use crate::discovery::DiscoveryStateHandle;
use crate::protocol::{
    DeviceInfo, DeviceSystem, DiscoveryState, Transport, QUIC_SERVICE_TYPE, TCP_SERVICE_TYPE,
};

/// 发现事件（对外）。
#[derive(Debug, Clone)]
pub enum DiscoveryEvent {
    Device(DeviceInfo),
    StateChange(DiscoveryState),
}

/// 浏览器：注册两个服务类型的 receiver，在独立线程中轮询维护设备列表。
pub struct Browser {
    stop: Arc<AtomicBool>,
}

impl Browser {
    /// 启动发现。`handle` 为进程级设备/状态缓存；`sink` 用于向上层推送事件。
    pub fn start(
        daemon: Arc<ServiceDaemon>,
        handle: Arc<DiscoveryStateHandle>,
        sink: mpsc::Sender<DiscoveryEvent>,
    ) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let stop_handle = stop.clone();
        thread::spawn(move || {
            run_browser_loop(&daemon, &handle, sink, &stop_handle);
        });
        Browser { stop }
    }

    /// 请求停止发现循环。
    pub fn stop(&self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

/// 后台发现循环（std 线程内轮询，不依赖 async 运行时）。
fn run_browser_loop(
    daemon: &ServiceDaemon,
    handle: &DiscoveryStateHandle,
    sink: mpsc::Sender<DiscoveryEvent>,
    stop: &AtomicBool,
) {
    handle.set_state(DiscoveryState::Starting);
    let _ = sink.try_send(DiscoveryEvent::StateChange(DiscoveryState::Starting));

    let mut receivers: Vec<(&str, Receiver<ServiceEvent>)> = Vec::new();
    for ty in [QUIC_SERVICE_TYPE, TCP_SERVICE_TYPE] {
        match daemon.browse(ty) {
            Ok(rx) => receivers.push((ty, rx)),
            Err(e) => error!(service = ty, error = %e, "mDNS browse 注册失败"),
        }
    }
    if receivers.is_empty() {
        handle.set_state(DiscoveryState::Error);
        let _ = sink.try_send(DiscoveryEvent::StateChange(DiscoveryState::Error));
        return;
    }

    handle.set_state(DiscoveryState::Running);
    let _ = sink.try_send(DiscoveryEvent::StateChange(DiscoveryState::Running));
    info!("mDNS 发现开始浏览 2 个服务类型");

    let devices: Arc<Mutex<HashMap<String, DeviceInfo>>> = Arc::new(Mutex::new(HashMap::new()));

    while !stop.load(Ordering::Relaxed) {
        let mut drained = Vec::new();
        for (ty, rx) in receivers.drain(..) {
            loop {
                match rx.try_recv() {
                    Ok(ev) => {
                        handle_service_event(ty, ev, &devices, handle, &sink);
                    }
                    // Empty 表示暂无新事件，Disconnected 表示浏览已停止；二者均退出本轮轮询。
                    Err(_) => break,
                }
            }
            drained.push((ty, rx));
        }
        receivers = drained;
        thread::sleep(Duration::from_millis(300));
    }

    handle.set_state(DiscoveryState::Stopped);
    let _ = sink.try_send(DiscoveryEvent::StateChange(DiscoveryState::Stopped));
    info!("mDNS 发现已停止");
}

fn handle_service_event(
    ty: &str,
    ev: ServiceEvent,
    devices: &Arc<Mutex<HashMap<String, DeviceInfo>>>,
    handle: &DiscoveryStateHandle,
    sink: &mpsc::Sender<DiscoveryEvent>,
) {
    match ev {
        ServiceEvent::ServiceResolved(info) => {
            if let Some(dev) = build_device(ty, &info) {
                let id = dev.id.clone();
                devices.lock().unwrap().insert(id.clone(), dev.clone());
                handle.upsert(dev.clone());
                let _ = sink.try_send(DiscoveryEvent::Device(dev));
            }
        }
        ServiceEvent::ServiceRemoved(_name, _ty) => {
            // 本段按保留记录处理，不做主动删除（在线状态由上层心跳判定）
        }
        ServiceEvent::SearchStopped(ty) => {
            debug!(service = ?ty, "mDNS 搜索停止");
        }
        other => {
            debug!("未处理 mDNS 事件: {other:?}");
        }
    }
}

/// 从解析到的服务实例构造 `DeviceInfo`。
fn build_device(_ty: &str, info: &mdns_sd::ServiceInfo) -> Option<DeviceInfo> {
    let props = info.get_properties();
    let id = props
        .get("id")
        .map(|v| v.to_string())
        .unwrap_or_else(|| info.get_fullname().to_string());
    let name = props
        .get("name")
        .map(|v| v.to_string())
        .unwrap_or_else(|| info.get_fullname().to_string());
    let system = props
        .get("system")
        .map(|v| DeviceSystem::from_str(&v.to_string()))
        .unwrap_or(DeviceSystem::Unknown);
    let ip = info
        .get_addresses()
        .iter()
        .find_map(|a| match a {
            std::net::IpAddr::V4(v4) => Some(v4.to_string()),
            _ => None,
        })
        .unwrap_or_else(|| info.get_hostname().to_string());

    let quic_port = props
        .get("quic_port")
        .and_then(|v| v.to_string().parse::<u16>().ok())
        .unwrap_or(0);
    let tcp_port = props
        .get("tcp_port")
        .and_then(|v| v.to_string().parse::<u16>().ok())
        .unwrap_or(0);
    let preferred_transport = props
        .get("preferred_transport")
        .map(|v| Transport::from_str(&v.to_string()))
        .unwrap_or(Transport::Quic);
    let supported = props
        .get("supported_transports")
        .map(|v| v.to_string())
        .unwrap_or_else(|| "quic,tcp".to_string());

    Some(DeviceInfo {
        id,
        name,
        system,
        ip,
        quic_port,
        tcp_port,
        supported_transports: supported.split(',').map(Transport::from_str).collect(),
        online: true,
        preferred_transport,
        protocol_version: props
            .get("protocol_version")
            .map(|v| v.to_string())
            .unwrap_or_default(),
    })
}