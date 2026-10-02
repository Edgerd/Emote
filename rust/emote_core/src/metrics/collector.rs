//! metrics::collector —— 运行期指标采集（第 4.9 段）。
//!
//! 轻量指标收集：帧率、编解码耗时、网络 RTT、FFI 传输耗时。
//! 线程安全（`DashMap` + `AtomicU64`），不引入额外锁。

use std::time::{Duration, Instant};

use dashmap::DashMap;

/// 会话级指标快照。
#[derive(Debug, Clone, Copy, Default)]
pub struct SessionMetrics {
    /// 累计处理帧数。
    pub frames: u64,
    /// 最后一次编码耗时（ns）。
    pub last_encode_ns: u64,
    /// 最后一次解码耗时（ns）。
    pub last_decode_ns: u64,
    /// 最后一次网络 RTT（ns）。
    pub last_rtt_ns: u64,
    /// 最后一次 FFI 传输耗时（ns）。
    pub last_ffi_ns: u64,
}

impl SessionMetrics {
    /// 计算简单平均帧率（基于累计帧数与观测时长）。
    #[must_use]
    pub fn avg_fps(&self, observed_secs: f64) -> f64 {
        if observed_secs <= 0.0 {
            return 0.0;
        }
        self.frames as f64 / observed_secs
    }
}

/// 全局指标采集器（每个 session_id 一份）。
pub struct MetricsCollector {
    sessions: DashMap<String, SessionMetrics>,
    start_time: Instant,
    /// 采样率：0.0 = 全量，1.0 = 每帧采样（默认 0.0）。
    #[allow(dead_code)]
    sample_rate: f64,
}

impl MetricsCollector {
    pub fn new() -> Self {
        Self {
            sessions: DashMap::new(),
            start_time: Instant::now(),
            sample_rate: 0.0,
        }
    }

    /// 记录编码耗时。
    pub fn record_encode(&self, session_id: &str, dur: Duration) {
        let mut m = self.sessions.entry(session_id.to_string()).or_default();
        m.last_encode_ns = dur.as_nanos() as u64;
    }

    /// 记录解码耗时。
    pub fn record_decode(&self, session_id: &str, dur: Duration) {
        let mut m = self.sessions.entry(session_id.to_string()).or_default();
        m.last_decode_ns = dur.as_nanos() as u64;
    }

    /// 记录一次帧处理完成。
    pub fn record_frame(&self, session_id: &str) {
        let mut m = self.sessions.entry(session_id.to_string()).or_default();
        m.frames += 1;
    }

    /// 记录网络 RTT。
    pub fn record_rtt(&self, session_id: &str, dur: Duration) {
        let mut m = self.sessions.entry(session_id.to_string()).or_default();
        m.last_rtt_ns = dur.as_nanos() as u64;
    }

    /// 记录 FFI 传输耗时。
    pub fn record_ffi(&self, session_id: &str, dur: Duration) {
        let mut m = self.sessions.entry(session_id.to_string()).or_default();
        m.last_ffi_ns = dur.as_nanos() as u64;
    }

    /// 取某会话当前指标快照。
    #[must_use]
    pub fn snapshot(&self, session_id: &str) -> Option<SessionMetrics> {
        self.sessions.get(session_id).map(|m| *m)
    }

    /// 观测时长（秒）。
    #[must_use]
    pub fn elapsed_secs(&self) -> f64 {
        self.start_time.elapsed().as_secs_f64()
    }

    /// 移除会话指标（会话关闭时调用）。
    pub fn remove(&self, session_id: &str) {
        self.sessions.remove(session_id);
    }
}

impl Default for MetricsCollector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn record_and_snapshot() {
        let mc = MetricsCollector::new();
        mc.record_frame("s1");
        mc.record_frame("s1");
        mc.record_encode("s1", Duration::from_millis(5));
        mc.record_decode("s1", Duration::from_millis(3));

        let snap = mc.snapshot("s1").expect("应有快照");
        assert_eq!(snap.frames, 2);
        assert!(snap.last_encode_ns > 0);
        assert!(snap.last_decode_ns > 0);
    }

    #[test]
    fn avg_fps_computation() {
        let m = SessionMetrics {
            frames: 60,
            ..Default::default()
        };
        let fps = m.avg_fps(1.0);
        assert!((fps - 60.0).abs() < 0.01);
    }

    #[test]
    fn remove_session() {
        let mc = MetricsCollector::new();
        mc.record_frame("gone");
        assert!(mc.snapshot("gone").is_some());
        mc.remove("gone");
        assert!(mc.snapshot("gone").is_none());
    }
}
