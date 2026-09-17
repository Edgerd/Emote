//! `connection::handler` —— 单连接读写、心跳与超时检测（第 2.3 段）。
//!
//! 每个连接运行一个独立 tokio 任务：
//! - 每 `heartbeat_interval` 发送一次心跳帧（8 字节 LE 毫秒时间戳）；
//! - 任意收到的帧都刷新 `last_rx`，超过 `heartbeat_timeout` 未活动即判定断线；
//! - 读通道关闭（对端断开）或收到 Close 命令时主动断开。

use std::sync::{Arc, Mutex};
use std::sync::atomic::AtomicU8;
use std::time::{Duration, Instant};

use tokio::sync::mpsc;
use tokio::time::MissedTickBehavior;

use crate::protocol::{ConnectionState, MessageType, now_millis};
use crate::transport::{ActiveTransport, Frame, SendHalf};

/// 下发到连接任务的外部命令。
#[derive(Debug)]
pub enum Outbound {
    Send { msg_type: MessageType, payload: Vec<u8> },
    Close,
}

/// 连接任务的可调参数（默认从协议常量派生，测试可注入短周期）。
#[derive(Debug, Clone, Copy)]
pub struct HandlerConfig {
    pub heartbeat_interval: Duration,
    pub heartbeat_timeout: Duration,
}

impl Default for HandlerConfig {
    fn default() -> Self {
        HandlerConfig {
            heartbeat_interval: Duration::from_secs(crate::protocol::HEARTBEAT_INTERVAL_SECS),
            heartbeat_timeout: Duration::from_secs(crate::protocol::HEARTBEAT_TIMEOUT_SECS),
        }
    }
}

/// 对外共享的连接状态快照（严格的小型值，供跨上下文读取）。
#[derive(Debug, Clone)]
pub struct ConnState {
    pub state: ConnectionState,
    pub transport: ActiveTransport,
}

/// 状态 + 传输层的共享句柄（`Arc<mutex>` 轻量，FFI 侧经行读取）。
#[derive(Debug)]
pub struct SharedState {
    inner: Mutex<ConnState>,
    /// 状态变化哨兵，避免频繁加锁轮询（无数据面含义）。
    _guard: StatGuard,
}

#[derive(Debug)]
struct StatGuard(AtomicU8);

impl SharedState {
    pub fn new(transport: ActiveTransport) -> Self {
        SharedState {
            inner: Mutex::new(ConnState {
                state: ConnectionState::Connecting,
                transport,
            }),
            _guard: StatGuard(AtomicU8::new(0)),
        }
    }

    pub fn get(&self) -> ConnState {
        match self.inner.lock() {
            Ok(g) => g.clone(),
            Err(p) => p.into_inner().clone(),
        }
    }

    pub fn set_state(&self, state: ConnectionState) {
        if let Ok(mut g) = self.inner.lock() {
            g.state = state;
        }
        self._guard.0.store(state as u8, std::sync::atomic::Ordering::Relaxed);
    }
}

/// 心跳载荷编码：8 字节 LE 毫秒时间戳。
pub fn encode_heartbeat(ts: u64) -> [u8; 8] {
    ts.to_le_bytes()
}

/// 心跳载荷解码。
#[allow(dead_code)]
pub fn decode_heartbeat(b: &[u8]) -> Option<u64> {
    Some(u64::from_le_bytes(b.get(..8)?.try_into().ok()?))
}

/// 启动单连接处理任务。
pub fn spawn(
    send: SendHalf,
    rx_frames: mpsc::Receiver<Frame>,
    rx_cmd: mpsc::UnboundedReceiver<Outbound>,
    shared: Arc<SharedState>,
    cfg: HandlerConfig,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(run(send, rx_frames, rx_cmd, shared, cfg))
}

async fn run(
    mut send: SendHalf,
    mut rx_frames: mpsc::Receiver<Frame>,
    mut rx_cmd: mpsc::UnboundedReceiver<Outbound>,
    shared: Arc<SharedState>,
    cfg: HandlerConfig,
) {
    let mut heartbeat = tokio::time::interval(cfg.heartbeat_interval);
    heartbeat.set_missed_tick_behavior(MissedTickBehavior::Delay);
    let mut last_rx = Instant::now();
    shared.set_state(ConnectionState::Connected);

    loop {
        let now = Instant::now();
        let timeout_at = last_rx.checked_add(cfg.heartbeat_timeout).unwrap_or(now);
        // 超时时间已过则立即触发检查，否则休眠到超时时刻。
        let sleep = if timeout_at > now {
            tokio::time::sleep_until(tokio::time::Instant::from_std(timeout_at))
        } else {
            tokio::time::sleep(Duration::ZERO)
        };

        tokio::select! {
            _ = heartbeat.tick() => {
                if send.send(MessageType::Heartbeat, &encode_heartbeat(now_millis())).await.is_err() {
                    shared.set_state(ConnectionState::Disconnected);
                    break;
                }
            }
            frame = rx_frames.recv() => {
                match frame {
                    Some(_f) => {
                        last_rx = Instant::now();
                    }
                    None => {
                        shared.set_state(ConnectionState::Disconnected);
                        break;
                    }
                }
            }
            cmd = rx_cmd.recv() => {
                match cmd {
                    Some(Outbound::Send { msg_type, payload }) => {
                        if send.send(msg_type, &payload).await.is_err() {
                            shared.set_state(ConnectionState::Disconnected);
                            break;
                        }
                    }
                    Some(Outbound::Close) | None => {
                        shared.set_state(ConnectionState::Disconnected);
                        break;
                    }
                }
            }
            _ = sleep => {
                if Instant::now().duration_since(last_rx) > cfg.heartbeat_timeout {
                    shared.set_state(ConnectionState::Disconnected);
                    break;
                }
            }
        }
    }
}