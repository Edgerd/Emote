//! `input` —— 远端输入注入（第 3.5 段）。
//!
//! 统一 `InputEvent` 模型 + 紧凑二进制序列化（跨连接通道传输）；各平台注入后端：
//! - `windows`（桌面 + Windows）：`SendInput`；
//! - `linux`（桌面 + Linux）：X11 XTest；
//! - `uinput`（桌面 + Linux）：`/dev/uinput` 内核接口（`libc`）。
//!
//! 后端探测 `detect()` + 派发 `InputDispatcher`：无可用后端时优雅降级到 `NullSink`（不 panic）。
//! Android target 无输入后端 → 一律 `NullSink`（本段范围外）。

#[cfg(all(desktop, target_os = "linux"))]
pub mod linux;
#[cfg(all(desktop, target_os = "linux"))]
pub mod uinput;
#[cfg(all(desktop, target_os = "windows"))]
pub mod windows;

use anyhow::Result;

/// 触摸动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TouchAction {
    Down,
    Move,
    Up,
}

/// 跨平台统一输入事件。
#[derive(Debug, Clone, PartialEq)]
pub enum InputEvent {
    /// 触摸（坐标为屏幕像素）。
    Touch { x: u32, y: u32, action: TouchAction },
    /// 按键（keycode 用 Android/Linux EV 码）。
    Key { keycode: u32, down: bool },
    /// 文本注入。
    Text(String),
    /// 滚动。
    Scroll { x: u32, y: u32, hscroll: f32, vscroll: f32 },
}

impl InputEvent {
    /// 序列化为紧凑二进制（大端），用于经连接通道发送。
    pub fn encode(&self) -> Vec<u8> {
        let mut v: Vec<u8> = Vec::new();
        match self {
            Self::Touch { x, y, action } => {
                v.push(0);
                v.push(match action {
                    TouchAction::Down => 0,
                    TouchAction::Move => 1,
                    TouchAction::Up => 2,
                });
                v.extend_from_slice(&x.to_be_bytes());
                v.extend_from_slice(&y.to_be_bytes());
            }
            Self::Key { keycode, down } => {
                v.push(1);
                v.push(u8::from(*down));
                v.extend_from_slice(&keycode.to_be_bytes());
            }
            Self::Text(s) => {
                let b = s.as_bytes();
                v.push(2);
                v.extend_from_slice(&(b.len() as u32).to_be_bytes());
                v.extend_from_slice(b);
            }
            Self::Scroll { x, y, hscroll, vscroll } => {
                v.push(3);
                v.extend_from_slice(&x.to_be_bytes());
                v.extend_from_slice(&y.to_be_bytes());
                v.extend_from_slice(&hscroll.to_be_bytes());
                v.extend_from_slice(&vscroll.to_be_bytes());
            }
        }
        v
    }

    /// 从 `encode` 的字节解码。
    pub fn decode(buf: &[u8]) -> Result<Self> {
        let read_be = |b: &[u8], off: usize, n: usize| -> Result<[u8; 4]> {
            if off + n > b.len() {
                return Err(anyhow::anyhow!("输入事件字节不足"));
            }
            let mut a = [0u8; 4];
            a[..n].copy_from_slice(&b[off..off + n]);
            Ok(a)
        };
        match buf.first().copied() {
            Some(0) => {
                let action = match buf.get(1).copied() {
                    Some(0) => TouchAction::Down,
                    Some(1) => TouchAction::Move,
                    Some(2) => TouchAction::Up,
                    _ => return Err(anyhow::anyhow!("非法 touch action")),
                };
                let x = u32::from_be_bytes(read_be(buf, 2, 4)?);
                let y = u32::from_be_bytes(read_be(buf, 6, 4)?);
                Ok(Self::Touch { x, y, action })
            }
            Some(1) => {
                let down = matches!(buf.get(1).copied(), Some(1));
                let keycode = u32::from_be_bytes(read_be(buf, 2, 4)?);
                Ok(Self::Key { keycode, down })
            }
            Some(2) => {
                let len = u32::from_be_bytes(read_be(buf, 1, 4)?) as usize;
                let text = std::str::from_utf8(&buf[5..5 + len])
                    .map_err(|_| anyhow::anyhow!("文本非 UTF-8"))?
                    .to_string();
                Ok(Self::Text(text))
            }
            Some(3) => {
                let x = u32::from_be_bytes(read_be(buf, 1, 4)?);
                let y = u32::from_be_bytes(read_be(buf, 5, 4)?);
                let hscroll = f32::from_be_bytes(read_be(buf, 9, 4)?);
                let vscroll = f32::from_be_bytes(read_be(buf, 13, 4)?);
                Ok(Self::Scroll {
                    x,
                    y,
                    hscroll,
                    vscroll,
                })
            }
            Some(t) => Err(anyhow::anyhow!("未知输入事件 tag {t}")),
            None => Err(anyhow::anyhow!("空输入事件")),
        }
    }
}

/// 输入注入后端。
///
/// `Send + Sync` 使 `InputDispatcher`（持有 `Box<dyn InputSink>`）可跨线程共享（供远控会话管理器
/// 在 FFI 线程边界使用）；各后端均为无共享可变状态的单元/整数结构，天然满足 `Sync`。
pub trait InputSink: Send + Sync {
    /// 后端名（如 `x11-xtest` / `uinput` / `sendinput` / `null`）。
    fn name(&self) -> &'static str;
    /// 注入一个事件；不可用时返回错误（上层降级，不 panic）。
    fn send(&self, ev: &InputEvent) -> Result<()>;
}

/// 降级空后端：不实际注入，仅记录。无可用真实后端时使用。
pub struct NullSink;
impl InputSink for NullSink {
    fn name(&self) -> &'static str {
        "null"
    }
    fn send(&self, _ev: &InputEvent) -> Result<()> {
        Ok(())
    }
}

/// 各后端是否可用（能力探测报告）。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct BackendReport {
    pub windows_sendinput: bool,
    pub linux_xtest: bool,
    pub linux_uinput: bool,
}

/// 探测当前环境下可用的输入后端（无可用项为 `false`，绝不 panic）。
pub fn detect() -> BackendReport {
    #[cfg(all(desktop, target_os = "linux"))]
    {
        return BackendReport {
            linux_xtest: linux::available(),
            linux_uinput: uinput::available(),
            ..Default::default()
        };
    }
    #[cfg(all(desktop, target_os = "windows"))]
    {
        return BackendReport {
            windows_sendinput: true,
            ..Default::default()
        };
    }
    #[allow(unreachable_code)]
    BackendReport::default()
}

/// 输入派发器：选择优先级最高的可用后端；全无则降级到 `NullSink`。
pub struct InputDispatcher {
    sink: Box<dyn InputSink>,
}

impl InputDispatcher {
    /// 依当前环境探测选择后端。
    #[must_use]
    pub fn new() -> Self {
        #[cfg(all(desktop, target_os = "linux"))]
        {
            if linux::available() {
                return Self {
                    sink: Box::new(linux::XTestSink),
                };
            }
            if let Ok(sink) = uinput::UinputSink::try_new() {
                return Self {
                    sink: Box::new(sink),
                };
            }
        }
        #[cfg(all(desktop, target_os = "windows"))]
        {
            return Self {
                sink: Box::new(windows::SendInputSink),
            };
        }
        Self {
            sink: Box::new(NullSink),
        }
    }

    /// 注入一个事件（走当前选定后端）。
    pub fn dispatch(&self, ev: &InputEvent) -> Result<()> {
        self.sink.send(ev)
    }

    /// 当前使用的后端名。
    #[must_use]
    pub fn sink_name(&self) -> &'static str {
        self.sink.name()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(ev: &InputEvent) {
        let bytes = ev.encode();
        let back = InputEvent::decode(&bytes).expect("decode");
        assert_eq!(ev, &back);
    }

    #[test]
    fn all_variants_roundtrip() {
        roundtrip(&InputEvent::Touch {
            x: 120,
            y: 340,
            action: TouchAction::Move,
        });
        roundtrip(&InputEvent::Key {
            keycode: 42,
            down: true,
        });
        roundtrip(&InputEvent::Text("你好, Emote".to_string()));
        roundtrip(&InputEvent::Scroll {
            x: 1,
            y: 2,
            hscroll: 0.0,
            vscroll: -1.5,
        });
    }

    #[test]
    fn decode_rejects_bad_tag() {
        assert!(InputEvent::decode(&[9u8, 1, 2]).is_err());
        assert!(InputEvent::decode(&[]).is_err());
    }

    #[test]
    fn dispatcher_degrades_gracefully_in_sandbox() {
        // 沙箱内通常无 X / 无 /dev/uinput → 探测全 false，dispatcher 落到 NullSink。
        let report = detect();
        let d = InputDispatcher::new();
        // 无论落到哪个后端，dispatch 都不应 panic。
        let _ = d.dispatch(&InputEvent::Key {
            keycode: 30,
            down: true,
        });
        if report.linux_xtest || report.linux_uinput || report.windows_sendinput {
            assert_ne!(d.sink_name(), "null", "有可用后端时不应降级");
        }
        println!("输入后端探测: {report:?}，当前 dispatcher={}", d.sink_name());
    }
}
