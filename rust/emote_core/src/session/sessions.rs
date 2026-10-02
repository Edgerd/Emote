//! 三方向会话实现（第 3.7–3.9 段）。
//!
//! 每个会话都提供「可测管线」：桌面方向走 `合成源 → openh264 编码`（自控制）或
//! `openh264 解码 → 帧`（被控制）；scrcpy 方向喂入 scrcpy 视频包并解码。
//! 缺能力时降级为 `Ended`/no-op，不 panic。

use std::collections::VecDeque;

use anyhow::{anyhow, Result};

use crate::capture::{ScreenSource, SyntheticSource};
use crate::codec::H264FrameType;
use crate::decoder::{DecodedFrame, decoder_available};
use crate::encoder::{I420Frame, EncoderOptions, encoder_available};
use crate::input::{InputDispatcher, InputEvent};
use crate::scrcpy::VideoPacket;

#[cfg(desktop)]
use crate::decoder::OpenH264Decoder;
#[cfg(desktop)]
use crate::encoder::OpenH264Encoder;

use super::{RemoteSession, SessionConfig, SessionDirection, SessionState, VideoFrame};

/// 由会话配置构造 `EncoderOptions`。
fn encoder_options(cfg: &SessionConfig) -> EncoderOptions {
    EncoderOptions {
        width: cfg.width.next_multiple_of(2).max(2),
        height: cfg.height.next_multiple_of(2).max(2),
        bitrate_bps: cfg.video.bit_rate.max(1),
        max_fps: cfg.video.max_fps as f32,
    }
}

/// 3.9 Linux→Windows：被控制端（解码 + 输入注入）。
pub struct DesktopFromSession {
    state: SessionState,
    input_disp: InputDispatcher,
    frames: VecDeque<DecodedFrame>,
    #[cfg(desktop)]
    decoder: Option<OpenH264Decoder>,
}

impl DesktopFromSession {
    pub fn new(cfg: &SessionConfig) -> Self {
        let _ = cfg;
        Self {
            state: SessionState::Stopped,
            input_disp: InputDispatcher::new(),
            frames: VecDeque::new(),
            #[cfg(desktop)]
            decoder: None,
        }
    }

    /// 喂入一段 H.264 AnnexB 数据，解出一帧并缓存。
    pub fn feed(&mut self, annexb: &[u8]) -> Result<()> {
        #[cfg(desktop)]
        {
            let d = self.decoder.as_mut().ok_or_else(|| anyhow!("无解码器后端"))?;
            if let Some(frame) = d.decode(annexb)? {
                self.frames.push_back(frame);
            }
        }
        #[cfg(not(desktop))]
        {
            let _ = (self, annexb);
        }
        Ok(())
    }

    /// 取已解码的下一帧（无则 `None`）。
    pub fn next_frame(&mut self) -> Option<DecodedFrame> {
        self.frames.pop_front()
    }

    /// 当前使用的输入后端名（探测降级）。
    pub fn input_backend(&self) -> &'static str {
        self.input_disp.sink_name()
    }
}

impl RemoteSession for DesktopFromSession {
    fn direction(&self) -> SessionDirection {
        SessionDirection::DesktopFrom
    }
    fn start(&mut self) -> Result<()> {
        #[cfg(desktop)]
        {
            if !decoder_available() {
                self.state = SessionState::Ended;
                return Err(anyhow!("codec_not_available"));
            }
            self.decoder = Some(OpenH264Decoder::new()?);
        }
        self.state = SessionState::Running;
        Ok(())
    }
    fn stop(&mut self) {
        self.state = SessionState::Stopped;
    }
    fn state(&self) -> SessionState {
        self.state
    }
    fn input(&mut self, ev: &InputEvent) -> Result<()> {
        // 本地注入（探测降级到 NullSink，不 panic）。
        self.input_disp.dispatch(ev)
    }
    fn next_decoded(&mut self) -> Option<VideoFrame> {
        let f = self.frames.pop_front()?;
        Some(VideoFrame {
            width: f.width,
            height: f.height,
            frame_type: H264FrameType::Unknown,
            data: f.rgba,
            is_decoded: true,
        })
    }
}

/// 3.8 Windows→Windows 本机自控制（捕获 + 编码）。
pub struct DesktopSelfSession {
    cfg: SessionConfig,
    state: SessionState,
    source: Option<Box<dyn ScreenSource>>,
    #[cfg(desktop)]
    encoder: Option<OpenH264Encoder>,
}

impl DesktopSelfSession {
    pub fn new(cfg: &SessionConfig) -> Self {
        Self {
            cfg: cfg.clone(),
            state: SessionState::Stopped,
            source: None,
            #[cfg(desktop)]
            encoder: None,
        }
    }

    /// 抓一帧并编码，返回 AnnexB 压缩流（无源/无编码器后端时 `None`，不 panic）。
    pub fn next_encoded(&mut self) -> Option<Vec<u8>> {
        let frame = self.source.as_mut()?.next_frame()?;
        #[cfg(desktop)]
        {
            let i420 = I420Frame {
                width: frame.width,
                height: frame.height,
                i420: frame.i420,
            };
            self.encoder.as_mut()?.encode_i420(&i420).ok()
        }
        #[cfg(not(desktop))]
        {
            let _ = frame;
            None
        }
    }

    /// 源宽高（未启动时 `None`）。
    pub fn source_size(&self) -> Option<(u32, u32)> {
        self.source.as_ref().map(|s| s.size())
    }
}

impl RemoteSession for DesktopSelfSession {
    fn direction(&self) -> SessionDirection {
        SessionDirection::DesktopSelf
    }
    fn start(&mut self) -> Result<()> {
        self.source = Some(Box::new(SyntheticSource::new(
            self.cfg.width,
            self.cfg.height,
            u32::MAX,
        )));
        #[cfg(desktop)]
        {
            if !encoder_available() {
                self.state = SessionState::Ended;
                return Err(anyhow!("codec_not_available"));
            }
            self.encoder = Some(OpenH264Encoder::new(&encoder_options(&self.cfg))?);
        }
        self.state = SessionState::Running;
        Ok(())
    }
    fn stop(&mut self) {
        self.state = SessionState::Stopped;
    }
    fn state(&self) -> SessionState {
        self.state
    }
    fn input(&mut self, _ev: &InputEvent) -> Result<()> {
        // 自控制为「源」方向：本端是被控显示源，不注入输入 → 降级 no-op。
        Ok(())
    }
}

/// 3.7 Win/Lin→Android：复用 scrcpy + ADB（喂入 scrcpy 视频包并解码）。
pub struct ScrcpySession {
    state: SessionState,
    input_disp: InputDispatcher,
    #[cfg(desktop)]
    decoder: Option<OpenH264Decoder>,
}

impl ScrcpySession {
    pub fn new(cfg: &SessionConfig) -> Self {
        let _ = cfg;
        Self {
            state: SessionState::Stopped,
            input_disp: InputDispatcher::new(),
            #[cfg(desktop)]
            decoder: None,
        }
    }

    /// 喂入一个 scrcpy 视频包（`data` 为 AnnexB payload），解出下一帧。
    pub fn feed_scrcpy_packet(&mut self, vp: &VideoPacket) -> Option<DecodedFrame> {
        #[cfg(desktop)]
        {
            let d = self.decoder.as_mut()?;
            d.decode(&vp.data).ok().flatten()
        }
        #[cfg(not(desktop))]
        {
            let _ = (self, vp);
            None
        }
    }
}

impl RemoteSession for ScrcpySession {
    fn direction(&self) -> SessionDirection {
        SessionDirection::Scrcpy
    }
    fn start(&mut self) -> Result<()> {
        #[cfg(desktop)]
        {
            if !decoder_available() {
                self.state = SessionState::Ended;
                return Err(anyhow!("codec_not_available"));
            }
            self.decoder = Some(OpenH264Decoder::new()?);
        }
        // 无真机时降级：解码能力就绪，实际 scrcpy 流需真机 ADB 通道提供。
        self.state = SessionState::Running;
        Ok(())
    }
    fn stop(&mut self) {
        self.state = SessionState::Stopped;
    }
    fn state(&self) -> SessionState {
        self.state
    }
    fn input(&mut self, ev: &InputEvent) -> Result<()> {
        // 映射到 scrcpy 控制通道；无真机时经本地 `InputDispatcher` 探测降级（沙箱内为 NullSink no-op）。
        self.input_disp.dispatch(ev)
    }
}
