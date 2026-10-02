//! `encoder::qos` —— 自适应码率与帧率控制（第 4.5 段）。
//!
//! 根据网络 RTT / 心跳延迟动态调整 H.264 编码参数（码率、帧率），
//! 保持局域网 < 150ms 端到端延迟目标。

use std::time::{Duration, Instant};

/// QoS 调整动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QosAction {
    /// 提升码率 / 帧率。
    IncreaseQuality,
    /// 降低码率 / 帧率。
    DecreaseQuality,
    /// 维持不变。
    NoChange,
}

/// 当前建议编码参数。
#[derive(Debug, Clone, Copy)]
pub struct QosParameters {
    /// 目标码率（bps）。
    pub bitrate_bps: u32,
    /// 目标帧率。
    pub fps: u32,
}

impl Default for QosParameters {
    fn default() -> Self {
        Self {
            bitrate_bps: 2_000_000,
            fps: 30,
        }
    }
}

/// QoS 控制器配置。
#[derive(Debug, Clone)]
pub struct QosConfig {
    /// 码率下限（bps）。
    pub min_bitrate_bps: u32,
    /// 码率上限（bps）。
    pub max_bitrate_bps: u32,
    /// 帧率下限。
    pub min_fps: u32,
    /// 帧率上限。
    pub max_fps: u32,
    /// 调整冷却（两次调整间最小间隔）。
    pub adjust_interval: Duration,
}

impl Default for QosConfig {
    fn default() -> Self {
        Self {
            min_bitrate_bps: 500_000,
            max_bitrate_bps: 20_000_000,
            min_fps: 5,
            max_fps: 60,
            adjust_interval: Duration::from_secs(1),
        }
    }
}

/// 自适应 QoS 控制器。
///
/// 调用方定期（≥ adjust_interval）传入当前网络延迟，控制器输出应执行的调整动作。
pub struct QosController {
    config: QosConfig,
    params: QosParameters,
    last_adjust: Option<Instant>,
}

impl QosController {
    pub fn new(config: QosConfig) -> Self {
        let params = QosParameters::default();
        Self {
            config,
            params,
            last_adjust: None,
        }
    }

    /// 当前建议参数。
    #[must_use]
    pub fn current(&self) -> &QosParameters {
        &self.params
    }

    /// 基于当前网络延迟（毫秒）决定下一步调整。
    ///
    /// 策略（§4.5）：
    /// - RTT < 50 ms：提升至上限
    /// - 50 ≤ RTT < 100 ms：维持
    /// - 100 ≤ RTT < 200 ms：码率降 20%、帧率降至 15
    /// - RTT ≥ 200 ms：码率降 50%、帧率降至 10
    ///
    /// 受冷却间隔约束：冷却期内返回 `NoChange`。
    pub fn update(&mut self, network_delay_ms: u32) -> QosAction {
        if let Some(last) = self.last_adjust {
            if last.elapsed() < self.config.adjust_interval {
                return QosAction::NoChange;
            }
        }

        let action = match network_delay_ms {
            0..=49 => {
                self.params.bitrate_bps = self.config.max_bitrate_bps;
                self.params.fps = self.config.max_fps;
                QosAction::IncreaseQuality
            }
            50..=99 => QosAction::NoChange,
            100..=199 => {
                self.params.bitrate_bps =
                    (self.params.bitrate_bps as u64 * 80 / 100).max(self.config.min_bitrate_bps as u64) as u32;
                self.params.fps = self.params.fps.min(15).max(self.config.min_fps);
                QosAction::DecreaseQuality
            }
            _ => {
                self.params.bitrate_bps =
                    (self.params.bitrate_bps as u64 * 50 / 100).max(self.config.min_bitrate_bps as u64) as u32;
                self.params.fps = self.params.fps.min(10).max(self.config.min_fps);
                QosAction::DecreaseQuality
            }
        };

        if action != QosAction::NoChange {
            self.last_adjust = Some(Instant::now());
        }
        action
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn low_latency_increases_quality() {
        let mut q = QosController::new(QosConfig::default());
        let action = q.update(20);
        assert_eq!(action, QosAction::IncreaseQuality);
        assert_eq!(q.current().bitrate_bps, 20_000_000);
        assert_eq!(q.current().fps, 60);
    }

    #[test]
    fn medium_latency_no_change() {
        let mut q = QosController::new(QosConfig::default());
        // 先提升一次
        q.update(20);
        q.last_adjust = Some(Instant::now() - Duration::from_secs(2));
        let action = q.update(75);
        assert_eq!(action, QosAction::NoChange);
    }

    #[test]
    fn high_latency_decreases_quality() {
        let mut q = QosController::new(QosConfig::default());
        // 先拉满
        q.update(20);
        q.last_adjust = Some(Instant::now() - Duration::from_secs(2));
        let action = q.update(150);
        assert_eq!(action, QosAction::DecreaseQuality);
        assert!(q.current().bitrate_bps < 20_000_000);
        assert!(q.current().fps <= 15);
    }

    #[test]
    fn very_high_latency_sharp_drop() {
        let mut q = QosController::new(QosConfig::default());
        q.update(20);
        q.last_adjust = Some(Instant::now() - Duration::from_secs(2));
        let action = q.update(300);
        assert_eq!(action, QosAction::DecreaseQuality);
        assert!(q.current().fps <= 10);
        // 不应低于下限
        assert!(q.current().bitrate_bps >= q.config.min_bitrate_bps);
    }

    #[test]
    fn respects_cooling_period() {
        let mut q = QosController::new(QosConfig::default());
        q.update(20); // 刚调整过
        // 冷却期内
        let action = q.update(300);
        assert_eq!(action, QosAction::NoChange, "冷却期内应 NoChange");
    }
}
