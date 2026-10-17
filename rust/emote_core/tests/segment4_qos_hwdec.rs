//! 第 4 段验收：**QoS 与硬件解码探测**（4.4 硬件解码降级选择器 + 4.5 自适应码率会话集成）。
//!
//! 4.6 断线重连在 `connection::reconnect`（指数退避 + 抖动 + 上限）已覆盖并有单测；
//! 本文件聚焦 4.4/4.5 的会话级端到端行为。依赖桌面 target 的 openh264。

#[cfg(desktop)]
use emote_core::capture::{ScreenSource, SyntheticSource};
#[cfg(desktop)]
use emote_core::encoder::{EncoderOptions, I420Frame, OpenH264Encoder};
#[cfg(desktop)]
use emote_core::session::{
    DesktopSelfSession, RemoteSession, SessionConfig, SessionDirection,
};

/// 4.4：硬件解码探测 + 选择器回退软解的全链路（沙箱无 /dev/dri → 回退 openh264）。
#[cfg(desktop)]
#[test]
fn hw_probe_and_selector_fallback_pipeline() {
    use emote_core::decoder::{DecoderSelector, detect_hw_decoders};

    // 沙箱探测不 panic；结果为空或为已知后端名。
    let hw = detect_hw_decoders();
    for k in &hw {
        assert!(!k.name().is_empty());
    }

    // 选择器回退软解后仍能完成 编码→解码 round-trip。
    let (w, h) = (160u32, 120u32);
    let mut src = SyntheticSource::new(w, h, 2);
    let mut enc = OpenH264Encoder::new(&EncoderOptions {
        width: w,
        height: h,
        bitrate_bps: 200_000,
        max_fps: 15.0,
    })
    .expect("编码器");
    let mut sel = DecoderSelector::open().expect("选择器（桌面恒可用）");
    assert_eq!(sel.backend_name(), "openh264", "沙箱应回退软解");

    let mut decoded = 0usize;
    for _ in 0..2 {
        let f = src.next_frame().expect("合成帧");
        let annexb = enc
            .encode_i420(&I420Frame {
                width: f.width,
                height: f.height,
                i420: f.i420,
            })
            .expect("编码");
        if let Some(frame) = sel.decode(&annexb).expect("解码") {
            assert_eq!(frame.width, w);
            decoded += 1;
        }
    }
    assert!(decoded >= 1, "回退软解后应至少解出一帧");
}

/// 4.5：QoS 控制器 → 会话编码器码率变化重建 → 仍能持续产出压缩流。
#[cfg(desktop)]
#[test]
fn adaptive_bitrate_rebuilds_encoder_mid_stream() {
    let mut cfg = SessionConfig::default();
    cfg.direction = SessionDirection::DesktopSelf;
    cfg.width = 160;
    cfg.height = 120;
    cfg.video.bit_rate = 2_000_000;

    let mut session = DesktopSelfSession::new(&cfg);
    session.start().expect("启动");
    assert_eq!(session.qos_bitrate(), 2_000_000);

    // 起步阶段正常编码。
    assert!(session.next_encoded().is_some(), "初始码率下应能编码");

    // 模拟劣化反馈：延迟 150ms → QoS 降码率 20%；目标变化触发编码器重建。
    session.on_latency_ms(150);
    let after_bad = session.qos_bitrate();
    assert_eq!(after_bad, 1_600_000, "高延迟(100–199ms)一次应 ×0.8");
    let frame = session.next_encoded();
    assert!(frame.is_some(), "降码率重建编码器后仍应能编码");
    // 重建后 applied_bps 已对齐 → 再次编码无需重建，仍成功。
    assert!(session.next_encoded().is_some(), "连续编码稳定");

    // 外部设定极低码率 → 夹到 QoS min。
    session.set_bitrate(100);
    assert_eq!(session.qos_bitrate(), 500_000, "不低于 min_bitrate_bps");
    assert!(session.next_encoded().is_some(), "min 码率下仍能编码");

    session.stop();
}

/// 4.5：独立 QoS 控制器边界行为（无冷却配置下全范围可达）。
#[cfg(desktop)]
#[test]
fn qos_controller_bounds() {
    use std::time::Duration;

    use emote_core::encoder::qos::{QosConfig, QosController};

    let mut q = QosController::new(QosConfig {
        adjust_interval: Duration::ZERO, // 测试中禁用冷却
        ..QosConfig::default()
    });
    for _ in 0..10 {
        q.update(20); // 低延迟 → 提满
    }
    assert_eq!(q.current().bitrate_bps, 20_000_000, "封顶 max");
    assert_eq!(q.current().fps, 60);
    for _ in 0..30 {
        q.update(300); // 极高延迟 → 持续减半
    }
    assert_eq!(q.current().bitrate_bps, 500_000, "触底 min");
    assert!(q.current().fps >= 5, "帧率不低于 min_fps");
    // 手动限速夹紧。
    q.set_target(100, 999);
    assert_eq!(q.current().bitrate_bps, 500_000, "手动值夹到 min");
    assert_eq!(q.current().fps, 60, "手动帧率夹到 max");
}
