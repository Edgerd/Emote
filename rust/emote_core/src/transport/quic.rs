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
///
/// 安全说明：同网段任一端可伪造对端（MITM）。可信对端校验请使用
/// [`make_client_endpoint_strict`]（配合 `make_server_endpoint_with_identity`
/// 生成的设备绑定证书与 [`certificate_fingerprint`]）。
pub fn make_client_endpoint(bind_addr: SocketAddr) -> Result<Endpoint> {
    make_client_endpoint_with_verifier(bind_addr, Some(SkipServerVerification::new()))
}

/// 构造一个「严格」QUIC 客户端端点：仅接受与 `expected_fingerprint`
/// （`certificate_fingerprint` 输出的 SHA-256）匹配的对端证书，否则握手失败。
/// 对端指纹应由可信侧带外分发（后续：经 mDNS TXT `cert=` 发布）。
pub fn make_client_endpoint_strict(bind_addr: SocketAddr, expected_fingerprint: [u8; 32]) -> Result<Endpoint> {
    let verifier = Arc::new(FingerprintServerVerification {
        expected: expected_fingerprint,
        provider: Arc::new(rustls::crypto::ring::default_provider()),
    });
    make_client_endpoint_with_verifier(bind_addr, Some(verifier))
}

fn make_client_endpoint_with_verifier(
    bind_addr: SocketAddr,
    verifier: Option<Arc<impl rustls::client::danger::ServerCertVerifier + 'static>>,
) -> Result<Endpoint> {
    let mut cfg = match verifier {
        Some(v) => rustls::ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(v)
            .with_no_client_auth(),
        None => unreachable!("当前实现必须提供校验器"),
    };
    cfg.alpn_protocols = vec![QUIC_ALPN.to_vec()];

    let qcfg = quinn::crypto::rustls::QuicClientConfig::try_from(cfg)
        .context("构造 QUIC 客户端证书配置失败")?;
    let mut endpoint = Endpoint::client(bind_addr)?;
    endpoint.set_default_client_config(ClientConfig::new(Arc::new(qcfg)));
    Ok(endpoint)
}

/// 生成设备绑定的自签证书：SAN 的 dns-name 为 `device_id`（替代此前的固定
/// `localhost`），供 `make_server_endpoint_with_identity` 使用。
pub fn generate_device_certificate(
    device_id: &str,
) -> Result<(CertificateDer<'static>, PrivatePkcs8KeyDer<'static>)> {
    let cert = rcgen::generate_simple_self_signed(vec![device_id.to_string()])
        .context("生成自以为签证书失败")?;
    Ok((
        CertificateDer::from(cert.cert),
        PrivatePkcs8KeyDer::from(cert.signing_key.serialize_der()),
    ))
}

/// 计算证书 DER 的 SHA-256 指纹（32 字节），用于带外信任与严格校验。
pub fn certificate_fingerprint(cert: &CertificateDer<'_>) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(cert.to_vec());
    hasher.finalize().into()
}

/// 指纹转小写 hex（mDNS TXT `cert=` 传输格式）。
pub fn fingerprint_to_hex(fingerprint: &[u8; 32]) -> String {
    fingerprint.iter().map(|b| format!("{b:02x}")).collect()
}

/// 解析 `cert=` hex 指纹；非法 hex 或长度不符返回 None。
pub fn hex_to_fingerprint(hex: &str) -> Option<[u8; 32]> {
    if hex.len() != 64 {
        return None;
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}

/// 构造一个 QUIC 服务端端点（CN 固定 `localhost`，仅供测试/兼容旧调用）。
pub fn make_server_endpoint(bind_addr: SocketAddr) -> Result<(Endpoint, CertificateDer<'static>)> {
    make_server_endpoint_with_identity(bind_addr, "localhost")
}

/// 构造一个 QUIC 服务端端点，证书绑定 `device_id`（CN/SAN dns-name），
/// 返回端点与证书 DER（调用方可据 DER 计算指纹经 mDNS 发布）。
pub fn make_server_endpoint_with_identity(
    bind_addr: SocketAddr,
    device_id: &str,
) -> Result<(Endpoint, CertificateDer<'static>)> {
    let (cert_der, key_der) = generate_device_certificate(device_id)?;

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

/// 证书指纹校验器：仅接受 SHA-256 指纹与 `expected` 一致的服务证书。
#[derive(Debug)]
struct FingerprintServerVerification {
    expected: [u8; 32],
    provider: Arc<rustls::crypto::CryptoProvider>,
}

impl rustls::client::danger::ServerCertVerifier for FingerprintServerVerification {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        if certificate_fingerprint(end_entity) != self.expected {
            return Err(rustls::Error::General(
                "QUIC 对端证书指纹不匹配（疑似被伪造/中间人）".into(),
            ));
        }
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
            &self.provider.signature_verification_algorithms,
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
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.provider.signature_verification_algorithms.supported_schemes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fingerprint_roundtrip() {
        let cert = generate_device_certificate("dev-001").expect("证书生成失败");
        let fp = certificate_fingerprint(&cert.0);
        assert_eq!(hex_to_fingerprint(&fingerprint_to_hex(&fp)), Some(fp));
        assert!(fingerprint_to_hex(&fp).len() == 64);
    }

    #[test]
    fn hex_to_fingerprint_rejects_bad_input() {
        assert!(hex_to_fingerprint("xyz").is_none());
        assert!(hex_to_fingerprint(&"g".repeat(64)).is_none());
        assert!(hex_to_fingerprint(&"f".repeat(63)).is_none());
    }

    #[test]
    fn identity_cert_differs_per_device() {
        let a = certificate_fingerprint(&generate_device_certificate("a").expect("a").0);
        let b = certificate_fingerprint(&generate_device_certificate("b").expect("b").0);
        assert_ne!(a, b);
    }
}