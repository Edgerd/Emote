//! 第 3 段验收：**可测管线**（合成源全管线 + loopback 视频流 + 三方向会话端到端）。
//!
//! 依赖桌面 target 的 openh264 软编解码；Android target 不构建本集成测试用例（`#[cfg(desktop)]`）。

#[cfg(desktop)]
use emote_core::decoder::OpenH264Decoder;
#[cfg(desktop)]
use emote_core::encoder::{OpenH264Encoder, EncoderOptions};
use emote_core::capture::{ScreenSource, SyntheticSource};
use emote_core::encoder::I420Frame;
use emote_core::input::InputEvent;
use emote_core::session::{
    DesktopFromSession, DesktopSelfSession, RemoteSession, SessionConfig, SessionDirection,
};

/// 合成源全管线：捕获(合成 I420) → openh264 编码 → openh264 解码 → 帧。
#[cfg(desktop)]
#[test]
fn synthetic_full_pipeline_capture_encode_decode() {
    let (w, h, n) = (160u32, 120u32, 4u32);
    let mut src = SyntheticSource::new(w, h, n);
    let mut enc = OpenH264Encoder::new(&EncoderOptions {
        width: w,
        height: h,
        bitrate_bps: 200_000,
        max_fps: 15.0,
    })
    .expect("编码器");
    let mut dec = OpenH264Decoder::new().expect("解码器");

    let mut decoded = 0usize;
    for _ in 0..n {
        let f = src.next_frame().expect("合成帧");
        let annexb = enc
            .encode_i420(&I420Frame {
                width: f.width,
                height: f.height,
                i420: f.i420.clone(),
            })
            .expect("编码");
        assert!(!annexb.is_empty());
        if let Some(frame) = dec.decode(&annexb).expect("解码") {
            assert_eq!(frame.width, w, "解码宽度应匹配");
            assert_eq!(frame.height, h, "解码高度应匹配");
            assert_eq!(frame.rgba.len(), (w * h * 4) as usize);
            decoded += 1;
        }
    }
    assert!(decoded >= 1, "全管线应至少解出一帧");
    println!("合成源全管线：{decoded} 帧解码成功（{w}x{h}）");
}

/// loopback 视频流：编码端把 AnnexB 经 loopback TCP 发送（4B 长度前缀），接收端解码。
#[cfg(desktop)]
#[test]
fn loopback_video_stream_encode_and_decode() {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    let (w, h) = (160u32, 120u32);
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().unwrap();
    let mut rx_side = std::net::TcpStream::connect(addr).expect("connect");
    let (mut tx_side, _peer) = listener.accept().expect("accept");

    let mut src = SyntheticSource::new(w, h, 3);
    let mut enc = OpenH264Encoder::new(&EncoderOptions {
        width: w,
        height: h,
        bitrate_bps: 200_000,
        max_fps: 15.0,
    })
    .expect("编码器");

    for _ in 0..3 {
        let f = src.next_frame().expect("合成帧");
        let annexb = enc
            .encode_i420(&I420Frame {
                width: f.width,
                height: f.height,
                i420: f.i420,
            })
            .expect("编码");
        tx_side.write_all(&(annexb.len() as u32).to_be_bytes()).expect("写长度");
        tx_side.write_all(&annexb).expect("写数据");
    }
    drop(tx_side); // 关闭发送端 → 接收端读到 EOF

    let mut dec = OpenH264Decoder::new().expect("解码器");
    let mut decoded = 0usize;
    loop {
        let mut len = [0u8; 4];
        if rx_side.read_exact(&mut len).is_err() {
            break;
        }
        let n = u32::from_be_bytes(len) as usize;
        let mut buf = vec![0u8; n];
        if rx_side.read_exact(&mut buf).is_err() {
            break;
        }
        if let Some(frame) = dec.decode(&buf).expect("解码") {
            assert_eq!(frame.width, w);
            decoded += 1;
        }
    }
    assert!(decoded >= 1, "loopback 视频流应至少解出一帧");
    println!("loopback 视频流：{decoded} 帧解码成功");
}

/// 三方向会话端到端：`DesktopSelfSession`（编码源）→ `DesktopFromSession`（解码 + 输入降级）。
#[cfg(desktop)]
#[test]
fn three_direction_sessions_end_to_end_pipeline() {
    let mut src_cfg = SessionConfig::default();
    src_cfg.direction = SessionDirection::DesktopSelf;
    src_cfg.width = 160;
    src_cfg.height = 120;
    let mut sink_cfg = SessionConfig::default();
    sink_cfg.direction = SessionDirection::DesktopFrom;

    let mut self_session = DesktopSelfSession::new(&src_cfg);
    self_session.start().expect("自控制会话启动");
    let mut from_session = DesktopFromSession::new(&sink_cfg);
    from_session.start().expect("被控制会话启动");

    let mut decoded = 0usize;
    for _ in 0..4 {
        if let Some(annexb) = self_session.next_encoded() {
            from_session.feed(&annexb).expect("feed");
            if from_session.next_frame().is_some() {
                decoded += 1;
            }
        }
    }
    assert!(decoded >= 1, "会话间管线应至少解出一帧");

    // 输入注入：沙箱内探测降级（NullSink），不应 panic。
    from_session
        .input(&InputEvent::Key {
            keycode: 30,
            down: true,
        })
        .expect("输入降级 no-op");

    from_session.stop();
    self_session.stop();
    println!("三方向会话端到端管线：{decoded} 帧，输入降级后端={}", from_session.input_backend());
}
