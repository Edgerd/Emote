//! `input::uinput` —— 经 `/dev/uinput` 内核接口注入（桌面 Linux，需权限）。
//!
//! 用 `libc` 直接 `open("/dev/uinput")` + `ioctl(UI_DEV_*)` + `write(input_event)`。
//! 容器/无内核 uinput 模块/无权限时 `available()`/`try_new()` 失败 → 上层降级，不 panic。

use std::os::fd::RawFd;
use std::path::Path;

use anyhow::{anyhow, Result};

use crate::input::{InputEvent, InputSink};

// ---- 内核 uinput 常量（x86_64 Linux）----
const EV_KEY: u16 = 1;
const EV_REL: u16 = 2;
const REL_WHEEL: u16 = 8;
const REL_WHEEL_H: u16 = 0;

const KEY_LEFTMOUSE: u16 = 273;

const fn _ioc(dir: u32, ty: u8, nr: u32, size: u32) -> libc::c_ulong {
    ((dir << 29) | (size << 16) | (nr << 8) | ty as u32) as libc::c_ulong
}
const UI_DEV_CREATE: libc::c_ulong = _ioc(1, b'U', 1, 4); // _IOR
const UI_DEV_DESTROY: libc::c_ulong = _ioc(0, b'U', 1, 0); // _IO
const UI_SET_EVBIT: libc::c_ulong = _ioc(2, b'U', 100, 4); // _IOW

/// 内核 `struct input_event`（`#[repr(C)]`，x86_64 布局 24 字节）。
#[repr(C)]
struct InputEventRaw {
    tv_sec: i64,
    tv_usec: i64,
    type_: u16,
    code: u16,
    value: i32,
}

/// 经 /dev/uinput 的输入注入后端。
pub struct UinputSink {
    fd: RawFd,
}

impl UinputSink {
    /// 尝试打开并创建 uinput 设备；不可用时返回 `Err`（降级）。
    pub fn try_new() -> Result<Self> {
        unsafe {
            let cpath = std::ffi::CString::new("/dev/uinput").expect("静态串无 NUL");
            let fd = libc::open(cpath.as_ptr(), libc::O_WRONLY | libc::O_CLOEXEC);
            if fd < 0 {
                return Err(anyhow!("/dev/uinput 不可打开（errno={}）", std::io::Error::last_os_error()));
            }
            let key: i32 = EV_KEY as i32;
            let rel: i32 = EV_REL as i32;
            if libc::ioctl(fd, UI_SET_EVBIT, &key as *const i32) < 0
                || libc::ioctl(fd, UI_SET_EVBIT, &rel as *const i32) < 0
                || libc::ioctl(fd, UI_DEV_CREATE) < 0
            {
                let e = std::io::Error::last_os_error();
                let _ = libc::close(fd);
                return Err(anyhow!("uinput 设备创建失败（{e}）"));
            }
            Ok(Self { fd })
        }
    }

    fn write_event(&self, ty: u16, code: u16, value: i32) -> Result<()> {
        let ev = InputEventRaw {
            tv_sec: 0,
            tv_usec: 0,
            type_: ty,
            code,
            value,
        };
        let n = unsafe {
            libc::write(
                self.fd,
                &ev as *const InputEventRaw as *const libc::c_void,
                std::mem::size_of::<InputEventRaw>(),
            )
        };
        if n < 0 {
            return Err(anyhow!("uinput 写入失败（errno={}）", std::io::Error::last_os_error()));
        }
        Ok(())
    }

    fn sync(&self) -> Result<()> {
        // EV_SYN 触发一次同步，使内核处理前面的事件。
        const EV_SYN: u16 = 0;
        self.write_event(EV_SYN, 0, 0)
    }
}

impl InputSink for UinputSink {
    fn name(&self) -> &'static str {
        "uinput"
    }

    fn send(&self, ev: &InputEvent) -> Result<()> {
        match ev {
            InputEvent::Key { keycode, down } => {
                self.write_event(EV_KEY, *keycode as u16, if *down { 1 } else { 0 })?;
                self.sync()?;
            }
            InputEvent::Touch { action, .. } => {
                use crate::input::TouchAction;
                let value = match action {
                    TouchAction::Down => 1,
                    TouchAction::Up => 0,
                    TouchAction::Move => -1, // 移动：置 0 无副作用
                };
                self.write_event(EV_KEY, KEY_LEFTMOUSE, value)?;
                if matches!(action, TouchAction::Move) {
                    self.write_event(EV_KEY, KEY_LEFTMOUSE, 0)?;
                }
                self.sync()?;
            }
            InputEvent::Scroll { vscroll, hscroll, .. } => {
                if vscroll.abs() > 1e-6 {
                    self.write_event(EV_REL, REL_WHEEL, vscroll.signum() as i32 * -1)?;
                }
                if hscroll.abs() > 1e-6 {
                    self.write_event(EV_REL, REL_WHEEL_H, hscroll.signum() as i32)?;
                }
                self.sync()?;
            }
            InputEvent::Text(_) => {
                // uinput 文本注入需逐字符键码映射；此处保守跳过。
            }
        }
        Ok(())
    }
}

impl Drop for UinputSink {
    fn drop(&mut self) {
        unsafe {
            let _ = libc::ioctl(self.fd, UI_DEV_DESTROY);
            let _ = libc::close(self.fd);
        }
    }
}

/// 是否可用 /dev/uinput。
pub fn available() -> bool {
    Path::new("/dev/uinput").exists()
}
