//! `transport::quic` —— 默认传输层实现（第 2.3 段）。
//!
//! 基于 `quinn` (0.11) 的 QUIC 连接：
//! - 每端在启动时生成自以为签证书，作为 LAN 上可对等的 QUIC 服务端与客户端；
//! - 客户端在 MVP 阶段跳过证书校验（LAN 信任模型，生产可后续加固）；
//! - 通过单条双向流承载统一帧，读路径复用 `transport::pump_frames` 打入帧通道。

use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::{Context, Result};
use quinn::rustls;
use quinn::{ClientConfig, Endpoint, RecvStream, ServerConfig};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified};
use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer, ServerName, UnixTime};

use crate::protocol::QUIC_ALPN;
use crate::transport::{Link, SendHalf, pump_frames};
use tokio::sync::mpsc;

/// 构造一个 QUIC 客户端端点（跳过证书校验，MVP 局域网信任模型）。
pub fn make_client_endpoint(bind_addr: SocketAddr) -> Result<Endpoint> {
    let mut cfg = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(SkipServerVerification::new())
        .with_no_client_auth();
    cfg.alpn_protocols = vec![QUIC_ALPN.to_vec()];

    let qcfg = quinn::crypto::rustls::QuicClientConfig::try_from(cfg)
        .context("构造 QUIC 客户端证书配置失败")?;
    let mut endpoint = Endpoint::client(bind_addr)?;
    endpoint.set_default_client_config(ClientConfig::new(Arc::new(qcfg)));
    Ok(endpoint)
}

/// 构造一个 QUIC 服务端端点（生成自以为签证书），返回端点与证书 DER。
pub fn make_server_endpoint(bind_addr: SocketAddr) -> Result<(Endpoint, CertificateDer<'static>)> {
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()])
        .context("生成自以为签证书失败")?;
    let cert_der = CertificateDer::from(cert.cert);
    let key_der = PrivatePkcs8KeyDer::from(cert.signing_key.serialize_der());

    let mut rcfg = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(vec![cert_der.clone()], key_der.into())
        .context("配置 QUIC 服务端证书失败")?;
    rcfg.alpn_protocols = vec![QUIC_ALPN.to_vec()];

    let qcfg = quinn::crypto::rustls::QuicServerConfig::try_from(rcfg)
        .context("构造 QUIC 服务端证书配置失败")?;
    let mut server_config = ServerConfig::with_crypto(Arc::new(qcfg));
    let mut tc = quinn::TransportConfig::default();
    tc.max_idle_timeout(Some(
        quinn::IdleTimeout::try_from(std::time::Duration::from_secs(30))
            .context("配置空闲超时失败")?,
    ));
    server_config.transport_config(Arc::new(tc));

    let endpoint = Endpoint::server(server_config, bind_addr)?;
    Ok((endpoint, cert_der))
}

/// 作为客户端建立 QUIC 连接，返回可用的 [`Link`]。
pub async fn connect(endpoint: &Endpoint, server: SocketAddr) -> Result<Link> {
    let conn = endpoint
        .connect(server, "localhost")
        .context("发起 QUIC 连接失败")?
        .await
        .context("QUIC 握手失败")?;
    let (send, recv) = conn
        .open_bi()
        .await
        .context("QUIC 打开双向流失败")?;
    Ok(link_from_streams(send, recv))
}

/// 作为服务端接受一条进入的 QUIC 连接，返回可用的 [`Link`]；端点关闭时返回 `Ok(None)`。
pub async fn accept(endpoint: &Endpoint) -> Result<Option<Link>> {
    match endpoint.accept().await {
        Some(incoming) => {
            let conn = incoming.await.context("接受 QUIC 连接失败")?;
            let (send, recv) = conn.open_bi().await.context("QUIC 打开双向流失败")?;
            Ok(Some(link_from_streams(send, recv)))
        }
        None => Ok(None),
    }
}

fn link_from_streams(send: quinn::SendStream, recv: RecvStream) -> Link {
    let (tx, rx) = mpsc::channel(256);
    tokio::spawn(pump_frames(recv, tx));
    Link {
        transport: crate::transport::ActiveTransport::Quic,
        send: SendHalf::Quic { tx: send },
        rx,
    }
}

/// 危险的证书校验器：信任任何服务器证书（仅用于局域网 MVP / 测试）。
#[derive(Debug)]
struct SkipServerVerification(Arc<rustls::crypto::CryptoProvider>);

impl SkipServerVerification {
    fn new() -> Arc<Self> {
        Arc::new(Self(Arc::new(rustls::crypto::ring::default_provider())))
    }
}

impl rustls::client::danger::ServerCertVerifier for SkipServerVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}