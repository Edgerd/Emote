//! `input::windows` —— Win32 `SendInput` 注入（桌面 Windows）。
//!
//! 仅 `cfg(target_os = "windows")` 编译。本环境（GNU 桌面）不参与编译；
//! 在 Windows 开发机上跑 `cargo build` 校验。

use anyhow::Result;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP,
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
                let inputs = [INPUT {
                    dwType: INPUT_KEYBOARD,
                    u: unsafe {
                        std::mem::zeroed::<_>().ki = KEYBDINPUT {
                            wVk: *keycode as u16,
                            wScanCode: 0,
                            dwFlags: if *down { 0 } else { KEYEVENTF_KEYUP },
                            time: 0,
                            dwExtraInfo: 0,
                        };
                        std::mem::zeroed()
                    },
                }];
                let _ = unsafe { SendInput(1, inputs.as_ptr(), std::mem::size_of::<INPUT>() as i32) };
            }
            // 触摸/滚动/文本：SendInput 支持但本段保守跳过（键码注入为主）。
            _ => {}
        }
        Ok(())
    }
}
