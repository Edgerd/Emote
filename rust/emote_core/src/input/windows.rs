//! `input::windows` —— Win32 `SendInput` 注入（桌面 Windows）。
//!
//! 仅 `cfg(target_os = "windows")` 编译。本环境（GNU 桌面）不参与编译；
//! 在 Windows 开发机上跑 `cargo build` 校验。

use anyhow::Result;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, VIRTUAL_KEY, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP,
    KEYBD_EVENT_FLAGS,
};

use crate::input::{InputEvent, InputSink};

/// Win32 SendInput 注入后端。
pub struct SendInputSink;

impl InputSink for SendInputSink {
    fn name(&self) -> &'static str {
        "sendinput"
    }

    fn send(&self, ev: &InputEvent) -> Result<()> {
        match ev {
            InputEvent::Key { keycode, down } => {
                // windows-rs 0.61 API：`INPUT { r#type, Anonymous }` + union `INPUT_0 { ki }`，
                // `wVk: VIRTUAL_KEY`、`dwFlags: KEYBD_EVENT_FLAGS`、`SendInput(&[INPUT], cbsize)`。
                let mut anon = INPUT_0::default();
                anon.ki = KEYBDINPUT {
                    wVk: VIRTUAL_KEY(*keycode as u16),
                    wScan: 0,
                    dwFlags: if *down {
                        KEYBD_EVENT_FLAGS(0)
                    } else {
                        KEYEVENTF_KEYUP
                    },
                    time: 0,
                    dwExtraInfo: 0,
                };
                let inputs = [INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: anon,
                }];
                let _ =
                    unsafe { SendInput(&inputs, std::mem::size_of::<INPUT>() as i32) };
            }
            // 触摸/滚动/文本：SendInput 支持但本段保守跳过（键码注入为主）。
            _ => {}
        }
        Ok(())
    }
}
