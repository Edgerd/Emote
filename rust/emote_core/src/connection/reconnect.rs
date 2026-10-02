//! `connection::reconnect` —— 断线自动重连策略（第 4.6 段）。
//!
//! 指数退避 + 随机抖动，避免多客户端同时重连造成 thundering herd。
//! QUIC 优先 0-RTT 恢复；TCP 使用标准指数退避。

use std::time::Duration;

/// 重连策略参数。
#[derive(Debug, Clone)]
pub struct ReconnectPolicy {
    /// 首次退避时长。
    pub initial_backoff: Duration,
    /// 指数因子（每次翻倍）。
    pub factor: f64,
    /// 最大重试次数。
    pub max_attempts: u32,
    /// 抖动比例（0.0-1.0，退避时长 × jitter 的随机偏移）。
    pub jitter: f64,
}

impl Default for ReconnectPolicy {
    fn default() -> Self {
        Self {
            initial_backoff: Duration::from_millis(100),
            factor: 2.0,
            max_attempts: 5,
            jitter: 0.2,
        }
    }
}

/// 重连管理器：跟踪尝试次数，计算下次退避。
#[derive(Debug)]
pub struct ReconnectManager {
    policy: ReconnectPolicy,
    attempt: u32,
}

impl ReconnectManager {
    pub fn new(policy: ReconnectPolicy) -> Self {
        Self {
            policy,
            attempt: 0,
        }
    }

    /// 重置（连接恢复后调用）。
    pub fn reset(&mut self) {
        self.attempt = 0;
    }

    /// 当前是第几次尝试（从 0 开始）。
    #[must_use]
    pub fn current_attempt(&self) -> u32 {
        self.attempt
    }

    /// 是否还能重试。
    #[must_use]
    pub fn can_retry(&self) -> bool {
        self.attempt < self.policy.max_attempts
    }

    /// 记录一次失败，返回下次应等待的退避时长（含抖动）。
    ///
    /// 抖动使用 `fastrand`（无全局锁、无 rand 依赖）。
    pub fn next_delay(&mut self) -> Duration {
        let base = self
            .policy
            .initial_backoff
            .as_secs_f64()
            * self.policy.factor.powi(self.attempt as i32);
        let jitter_val = fastrand::f64() * self.policy.jitter * base;
        let total = base + jitter_val;
        self.attempt += 1;
        Duration::from_secs_f64(total)
    }

    /// 获取本次重试的退避序列（纯计算，不修改状态），用于测试/UI 展示。
    #[must_use]
    pub fn backoff_sequence(&self) -> Vec<Duration> {
        (0..self.policy.max_attempts)
            .map(|i| {
                let base = self
                    .policy
                    .initial_backoff
                    .as_secs_f64()
                    * self.policy.factor.powi(i as i32);
                Duration::from_secs_f64(base)
            })
            .collect()
    }
}

impl Default for ReconnectManager {
    fn default() -> Self {
        Self::new(ReconnectPolicy::default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_sequence_grows_exponentially() {
        let policy = ReconnectPolicy {
            initial_backoff: Duration::from_millis(100),
            factor: 2.0,
            max_attempts: 5,
            jitter: 0.0,
        };
        let mgr = ReconnectManager::new(policy.clone());
        let seq = mgr.backoff_sequence();
        assert_eq!(seq.len(), 5);
        assert_eq!(seq[0], Duration::from_millis(100));
        assert_eq!(seq[1], Duration::from_millis(200));
        assert_eq!(seq[2], Duration::from_millis(400));
        assert_eq!(seq[3], Duration::from_millis(800));
        assert_eq!(seq[4], Duration::from_millis(1600));
    }

    #[test]
    fn can_retry_exhausts_after_max_attempts() {
        let mut mgr = ReconnectManager::new(ReconnectPolicy {
            max_attempts: 3,
            ..Default::default()
        });
        assert!(mgr.can_retry());
        mgr.next_delay();
        assert!(mgr.can_retry());
        mgr.next_delay();
        assert!(mgr.can_retry());
        mgr.next_delay();
        assert!(!mgr.can_retry(), "3 次后应不可重试");
    }

    #[test]
    fn reset_clears_attempt() {
        let mut mgr = ReconnectManager::default();
        mgr.next_delay();
        mgr.next_delay();
        assert_eq!(mgr.current_attempt(), 2);
        mgr.reset();
        assert_eq!(mgr.current_attempt(), 0);
        assert!(mgr.can_retry());
    }

    #[test]
    fn jitter_produces_non_deterministic_but_bounded_delays() {
        let policy = ReconnectPolicy {
            initial_backoff: Duration::from_millis(100),
            factor: 2.0,
            max_attempts: 5,
            jitter: 0.2,
        };
        let mut mgr = ReconnectManager::new(policy);
        for i in 0..5 {
            let base_ms = 100.0 * 2f64.powi(i as i32);
            let max_ms = base_ms * 1.2; // base * (1 + jitter)
            let d = mgr.next_delay();
            assert!(
                d.as_secs_f64() * 1000.0 >= base_ms - 1.0 && d.as_secs_f64() * 1000.0 <= max_ms + 1.0,
                "delay {d:?} 超出第 {i} 次抖动范围 [{base_ms}, {max_ms}]ms"
            );
        }
    }
}
