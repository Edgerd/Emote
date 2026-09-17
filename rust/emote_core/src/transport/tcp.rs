//! `transport::tcp` —— 回退传输层实现（第 2.3 段）。
//!
//! 基于 `tokio::net::TcpStream`：
//! - 默认启用 `TCP_NODELAY`（禁用 Nagle），降低交互延迟；
//! - 作为客户端 `connect` 建连，或作为服务端 `accept` 接收（供回退/测试使用）。

use std::net::SocketAddr;

use anyhow::{Context, Result};
use tokio::io::AsyncWriteExt;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;

use crate::transport::{ActiveTransport, Link, SendHalf, pump_frames};

/// 作为客户端建立 TCP 连接，返回可用的 [`Link`]。默认启用 TCP_NODELAY。
pub async fn connect(server: SocketAddr, nodelay: bool) -> Result<Link> {
    let stream = TcpStream::connect(server)
        .await
        .context("TCP 连接失败")?;
    if nodelay {
        stream
            .set_nodelay(true)
            .context("设置 TCP_NODELAY 失败")?;
    }
    let (read, write) = stream.into_split();

    let (tx, rx) = mpsc::channel(256);
    tokio::spawn(pump_frames(read, tx));
    Ok(Link {
        transport: ActiveTransport::Tcp,
        send: SendHalf::Tcp { write },
        rx,
    })
}

/// 创建 TCP 监听（回退/测试用）。
pub async fn bind(addr: SocketAddr) -> Result<TcpListener> {
    TcpListener::bind(addr).await.context("TCP 绑定失败")
}

/// 接受一条进入的 TCP 连接，返回可用的 [`Link`]；监听关闭时返回 `Ok(None)`。
pub async fn accept(listener: &TcpListener, nodelay: bool) -> Result<Option<Link>> {
    match listener.accept().await {
        Ok((stream, _)) => {
            if nodelay {
                let _ = stream.set_nodelay(true);
            }
            let (read, write) = stream.into_split();
            let (tx, rx) = mpsc::channel(256);
            tokio::spawn(pump_frames(read, tx));
            Ok(Some(Link {
                transport: ActiveTransport::Tcp,
                send: SendHalf::Tcp { write },
                rx,
            }))
        }
        Err(_) => Ok(None),
    }
}

/// 优雅关闭写半（flush 后关闭连接）。
#[allow(dead_code)]
pub(crate) async fn shutdown(write: &mut tokio::net::tcp::OwnedWriteHalf) -> std::io::Result<()> {
    write.shutdown().await
}