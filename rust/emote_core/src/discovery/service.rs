//! `discovery::service` —— mDNS 服务广播（第 2.2 段）。
//!
//! 注册本机 QUIC / TCP 服务，并通过 TXT 记录公布：
//! - `id` / `system` / `name` / `protocol_version`：设备描述
//! - `quic_port` / `tcp_port`：动态分配的监听端口
//! - `supported_transports`：支持的传输层
//! - `preferred_transport`：首选传输层
//!
//! 基于 `mdns-sd` 的 `ServiceDaemon`，广播由 mdns-sd 内部线程承载。

use std::collections::HashMap;

use mdns_sd::{ServiceDaemon, ServiceInfo};
use tracing::{info, warn};

use crate::protocol::{DeviceSystem, Transport, QUIC_SERVICE_TYPE, TCP_SERVICE_TYPE};

/// 本机设备描述（用于广播）。
#[derive(Debug, Clone)]
pub struct LocalDeviceConfig {
    pub id: String,
    pub name: String,
    pub system: DeviceSystem,
    pub quic_port: u16,
    pub tcp_port: u16,
    pub preferred_transport: Transport,
    pub protocol_version: String,
}

/// mDNS 广播服务：注册 QUIC 与 TCP 两条服务，并可停止。
pub struct DiscoveryService {
    daemon: ServiceDaemon,
    registered_fullnames: Vec<String>,
}

impl DiscoveryService {
    /// 启动广播。`host_ip` 为本机局域网 IPv4。
    pub fn start(config: &LocalDeviceConfig, host_ip: &str) -> anyhow::Result<Self> {
        info!(name=%config.name, ip=%host_ip, "mDNS 服务广播启动");
        let daemon = ServiceDaemon::new().map_err(|e| anyhow::anyhow!("mDNS 启动失败: {e}"))?;

        // mdns-sd 的 check_hostname 要求主机名以 ".local."（带末尾点）结尾，
        // 否则 register 会报 "Hostname must end with '.local.'"。
        let host_name = format!("{}.local.", config.name.replace(' ', "-"));
        let mut registered_fullnames = Vec::new();

        // ---- QUIC 服务（_emote._udp.local.）----
        register_service(
            &daemon,
            QUIC_SERVICE_TYPE,
            &config.name,
            &host_name,
            host_ip,
            config,
            config.quic_port,
            &mut registered_fullnames,
        )?;

        // ---- TCP 服务（_emote._tcp.local.）----
        register_service(
            &daemon,
            TCP_SERVICE_TYPE,
            &config.name,
            &host_name,
            host_ip,
            config,
            config.tcp_port,
            &mut registered_fullnames,
        )?;

        Ok(DiscoveryService {
            daemon,
            registered_fullnames,
        })
    }

    /// 停止广播并注销已注册的服务。
    pub fn stop(&self) {
        for fullname in &self.registered_fullnames {
            let _ = self.daemon.unregister(fullname);
        }
        let _ = self.daemon.shutdown();
        info!("mDNS 广播已停止");
    }
}

#[allow(clippy::too_many_arguments)]
fn register_service(
    daemon: &ServiceDaemon,
    service_type: &str,
    instance_name: &str,
    host_name: &str,
    host_ip: &str,
    config: &LocalDeviceConfig,
    port: u16,
    registered_fullnames: &mut Vec<String>,
) -> anyhow::Result<()> {
    let props = build_props(config);
    let info = ServiceInfo::new(
        service_type,
        instance_name,
        host_name,
        host_ip,
        port,
        props,
    )
    .map_err(|e| anyhow::anyhow!("构造 {service_type} 服务失败: {e}"))?;
    let fullname = info.get_fullname().to_string();

    match daemon.register(info) {
        Ok(_) => {
            info!(service = service_type, port, "mDNS 服务已注册");
            registered_fullnames.push(fullname);
            Ok(())
        }
        Err(e) => {
            warn!(service = service_type, error = %e, "mDNS 服务注册失败");
            Err(anyhow::anyhow!("注册 {service_type} 服务失败: {e}"))
        }
    }
}

fn build_props(config: &LocalDeviceConfig) -> HashMap<String, String> {
    let mut props = HashMap::new();
    props.insert("id".to_string(), config.id.clone());
    props.insert("system".to_string(), config.system.as_str().to_string());
    props.insert("name".to_string(), config.name.clone());
    props.insert("quic_port".to_string(), config.quic_port.to_string());
    props.insert("tcp_port".to_string(), config.tcp_port.to_string());
    props.insert("supported_transports".to_string(), "quic,tcp".to_string());
    props.insert(
        "preferred_transport".to_string(),
        config.preferred_transport.as_str().to_string(),
    );
    props.insert("protocol_version".to_string(), config.protocol_version.clone());
    props
}