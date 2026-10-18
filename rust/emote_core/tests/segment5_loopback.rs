//! 临时验证：沙箱内 loopback 真实建连可用性（验证后删除，不入库）。
//!
//! 覆盖验收项 #4（逻辑侧：链路帧收发）、#5（QUIC 优先 / TCP 回退）、
//! #17（心跳）、协议文档（10B 消息头、ALPN、严格指纹校验）。

use std::net::SocketAddr;
use std::time::Duration;

use emote_core::protocol::{DeviceInfo, DeviceSystem, MessageType, Transport};
use emote_core::transport::{quic, tcp, ActiveTransport};
use emote_core::connection::manager::{ConnectionConfig, ConnectionManager};

fn loopback(port: u16) -> SocketAddr {
    format!("127.0.0.1:{port}").parse().unwrap()
}

fn dev(id: &str, quic_port: u16, tcp_port: u16) -> DeviceInfo {
    DeviceInfo {
        id: id.into(),
        name: "verify".into(),
        system: DeviceSystem::Linux,
        ip: "127.0.0.1".into(),
        quic_port,
        tcp_port,
        supported_transports: vec![Transport::Quic, Transport::Tcp],
        online: true,
        preferred_transport: Transport::Quic,
        protocol_version: "1.0.0".into(),
    }
}

#[tokio::test]
async fn quic_loopback_frames_roundtrip() {
    // 服务端：绑定动态端口，接受一条连接并回显两帧。
    let (endpoint, cert) = quic::make_server_endpoint_with_identity(loopback(0), "verify-peer").unwrap();
    let server_addr = endpoint.local_addr().unwrap();
    let cert_for_fp = cert.clone();
    let server = tokio::spawn(async move {
        // 循环接受 2 条连接：第 1 条做帧回显；第 2 条供严格指纹握手。
        for i in 0..2 {
            let Some(mut link) = quic::accept(&endpoint).await.unwrap() else {
                break;
            };
            if i == 0 {
                assert_eq!(link.transport, ActiveTransport::Quic);
                // 收 Heartbeat，回 Control。
                let f1 = link.rx.recv().await.unwrap();
                assert_eq!(f1.msg_type, MessageType::Heartbeat);
                assert_eq!(f1.payload.as_ref(), b"ping-1");
                link.send.send(MessageType::Control, b"pong-1").await.unwrap();
                // 再收 Control。
                let f2 = link.rx.recv().await.unwrap();
                assert_eq!(f2.msg_type, MessageType::Control);
                assert_eq!(f2.payload.as_ref(), b"hello-emote");
            }
        }
    });

    // 客户端：非严格端点建连、发帧、收回显。
    let client = quic::make_client_endpoint(loopback(0)).unwrap();
    let mut link = quic::connect(&client, server_addr).await.unwrap();
    assert_eq!(link.transport, ActiveTransport::Quic);
    link.send.send(MessageType::Heartbeat, b"ping-1").await.unwrap();
    link.send.send(MessageType::Control, b"hello-emote").await.unwrap();
    let echoed = link.rx.recv().await.unwrap();
    assert_eq!(echoed.msg_type, MessageType::Control);
    assert_eq!(echoed.payload.as_ref(), b"pong-1");

    // 严格指纹校验：正确指纹握手成功（服务端仍在监听）。
    let fp = quic::certificate_fingerprint(&cert_for_fp);
    let strict = quic::make_client_endpoint_strict(loopback(0), fp).unwrap();
    assert!(quic::connect(&strict, server_addr).await.is_ok(), "正确指纹应握手成功");

    // 错误指纹握手必须失败。
    let bad = quic::make_client_endpoint_strict(loopback(0), [0u8; 32]).unwrap();
    assert!(quic::connect(&bad, server_addr).await.is_err(), "错误指纹应握手失败");

    server.await.unwrap();
}

#[tokio::test]
async fn tcp_loopback_frames_roundtrip() {
    let listener = tcp::bind(loopback(0)).await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let mut link = tcp::accept(&listener, true).await.unwrap().unwrap();
        assert_eq!(link.transport, ActiveTransport::Tcp);
        let f = link.rx.recv().await.unwrap();
        assert_eq!(f.msg_type, MessageType::Control);
        assert_eq!(f.payload.as_ref(), b"tcp-ping");
        link.send.send(MessageType::Control, b"tcp-pong").await.unwrap();
    });

    let mut link = tcp::connect(addr, true).await.unwrap();
    assert_eq!(link.transport, ActiveTransport::Tcp);
    link.send.send(MessageType::Control, b"tcp-ping").await.unwrap();
    let echoed = link.rx.recv().await.unwrap();
    assert_eq!(echoed.payload.as_ref(), b"tcp-pong");
    server.await.unwrap();
}

#[test]
fn manager_falls_back_to_tcp_when_quic_unavailable() {
    // ConnectionManager 自带 tokio runtime（同步 FFI 入口），测试也走同步入口，
    // server 侧放到独立线程自建 runtime，避免 runtime 嵌套。
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (tcp_port_tx, tcp_port_rx) = std::sync::mpsc::channel();
    let server = std::thread::spawn(move || {
        rt.block_on(async {
            let listener = tcp::bind(loopback(0)).await.unwrap();
            let tcp_port = listener.local_addr().unwrap().port();
            tcp_port_tx.send(tcp_port).unwrap();
            let mut link = tcp::accept(&listener, true).await.unwrap().unwrap();
            // 管理器 handler 每 250ms 自动发心跳（8 字节 LE 毫秒时间戳）；
            // 期间可能混入业务 Control 帧，循环等待直到出现心跳帧。
            let hb = tokio::time::timeout(Duration::from_secs(5), async {
                loop {
                    let f = link.rx.recv().await.expect("链路提前断开");
                    if f.msg_type == MessageType::Heartbeat {
                        break f;
                    }
                }
            })
            .await
            .expect("未在超时内收到管理器心跳");
            assert_eq!(hb.payload.len(), 8, "心跳 payload 应为 8 字节时间戳");
        });
    });
    let tcp_port = tcp_port_rx.recv().unwrap();

    let mgr = ConnectionManager::with_config(ConnectionConfig {
        heartbeat_interval: Duration::from_millis(250),
        ..ConnectionConfig::default()
    })
    .unwrap();
    // quic_port 指向一个大概率无监听的端口，强制 QUIC 失败。
    let d = dev("fb-device", 1, tcp_port);
    let state = mgr.connect_to_device(&d).unwrap();
    assert!(
        matches!(state, emote_core::protocol::ConnectionState::Connecting | emote_core::protocol::ConnectionState::Connected),
        "回退建连后状态异常: {state:?}"
    );
    // 生效传输层必须是 TCP。
    let active = mgr.get_active_transport("fb-device");
    assert_eq!(active, Some(ActiveTransport::Tcp), "QUIC 不可达时应回退 TCP");
    // 业务帧发送路径可用。
    mgr.send_message("fb-device", MessageType::Control, b"via-tcp").unwrap();
    server.join().unwrap();
    mgr.disconnect("fb-device").unwrap();
    assert_eq!(mgr.get_connection_state("fb-device"), emote_core::protocol::ConnectionState::Disconnected);
}

#[test]
fn manager_prefers_quic_when_available() {
    // QUIC + TCP 同时监听：管理器应优先走 QUIC。
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (ports_tx, ports_rx) = std::sync::mpsc::channel();
    let server = std::thread::spawn(move || {
        rt.block_on(async {
            let (endpoint, _cert) = quic::make_server_endpoint_with_identity(loopback(0), "verify-q").unwrap();
            let quic_port = endpoint.local_addr().unwrap().port();
            ports_tx.send(quic_port).unwrap();
            let mut link = quic::accept(&endpoint).await.unwrap().unwrap();
            let hb = tokio::time::timeout(Duration::from_secs(5), link.rx.recv())
                .await
                .expect("未收到 QUIC 链路心跳")
                .unwrap();
            assert_eq!(hb.msg_type, MessageType::Heartbeat);
        });
    });
    let quic_port = ports_rx.recv().unwrap();
    let listener_port = {
        // 占位 TCP 端口（管理器应优先 QUIC，不触达 TCP）。
        let l = tokio::runtime::Runtime::new().unwrap().block_on(tcp::bind(loopback(0))).unwrap();
        let p = l.local_addr().unwrap().port();
        drop(l);
        p
    };

    let mgr = ConnectionManager::with_config(ConnectionConfig {
        heartbeat_interval: Duration::from_millis(250),
        ..ConnectionConfig::default()
    })
    .unwrap();
    let d = dev("q-device", quic_port, listener_port);
    mgr.connect_to_device(&d).unwrap();
    let active = mgr.get_active_transport("q-device");
    assert_eq!(active, Some(ActiveTransport::Quic), "QUIC 可达时应优先 QUIC");
    mgr.send_message("q-device", MessageType::Heartbeat, b"").unwrap();
    server.join().unwrap();
    mgr.disconnect("q-device").unwrap();
}
