//! `input::linux` —— X11 XTest 注入（桌面 Linux）。
//!
//! 经 `x11-dl`（动态加载 libX11 / libXtst）+ XTest 扩展注入键盘/鼠标事件。
//! 注意：`x11-dl` 的 `xtest` 模块结构体按源码宏首参命名为 `Xf86vmode`（crate 命名 quirk），
//! 字段为函数指针，需以 `(lib.FnName)(args)` 语法调用。
//! 无 `DISPLAY` 或未装 X11 时 `available()` 返回 `false`，上层降级，不 panic。

use anyhow::{anyhow, Result};
use x11_dl::xlib::Xlib;
use x11_dl::xtest::Xf86vmode as XTestLib;

use crate::input::{InputEvent, InputSink, TouchAction};

/// X11 XTest 注入后端（零成本单例）。
pub struct XTestSink;

/// 当前环境是否具备可用的 X11 XTest 注入能力。
pub fn available() -> bool {
    if std::env::var_os("DISPLAY").is_none() {
        return false;
    }
    Xlib::open().is_ok() && XTestLib::open().is_ok()
}

impl InputSink for XTestSink {
    fn name(&self) -> &'static str {
        "x11-xtest"
    }

    fn send(&self, ev: &InputEvent) -> Result<()> {
        let xlib = Xlib::open().map_err(|_| anyhow!("libX11 不可用"))?;
        let xtst = XTestLib::open().map_err(|_| anyhow!("libXtst 不可用"))?;
        let display = unsafe { (xlib.XOpenDisplay)(std::ptr::null()) };
        if display.is_null() {
            return Err(anyhow!("无法打开默认 X display（无显示环境？）"));
        }

        macro_rules! fake_button {
            ($btn:expr, $press:expr) => {
                unsafe {
                    let _ = (xtst.XTestFakeButtonEvent)(display, $btn, $press, 0u64);
                }
            };
        }

        match ev {
            InputEvent::Touch { x, y, action } => {
                unsafe {
                    let _ = (xtst.XTestFakeMotionEvent)(display, 0i32, *x as i32, *y as i32, 0u64);
                }
                match action {
                    TouchAction::Down => fake_button!(1u32, 1i32),
                    TouchAction::Up => fake_button!(1u32, 0i32),
                    TouchAction::Move => {}
                }
            }
            InputEvent::Key { keycode, down } => unsafe {
                let _ = (xtst.XTestFakeKeyEvent)(display, *keycode, if *down { 1i32 } else { 0i32 }, 0u64);
            },
            InputEvent::Scroll { x, y, hscroll, vscroll } => {
                unsafe {
                    let _ = (xtst.XTestFakeMotionEvent)(display, 0i32, *x as i32, *y as i32, 0u64);
                }
                if *vscroll < 0.0 {
                    fake_button!(5u32, 1i32);
                    fake_button!(5u32, 0i32);
                } else if *vscroll > 0.0 {
                    fake_button!(4u32, 1i32);
                    fake_button!(4u32, 0i32);
                }
                if *hscroll < 0.0 {
                    fake_button!(7u32, 1i32);
                    fake_button!(7u32, 0i32);
                } else if *hscroll > 0.0 {
                    fake_button!(6u32, 1i32);
                    fake_button!(6u32, 0i32);
                }
            }
            // XTest 无直接文本注入；文本走键码序列（此处保守跳过）。
            InputEvent::Text(_) => {}
        }

        unsafe {
            let _ = (xlib.XFlush)(display);
        }
        Ok(())
    }
}
