//! `scrcpy::adb` —— ADB 通道（第 3.1 段）。
//!
//! 经 `adb` 可执行文件（`std::process::Command`）与设备交互，不自己实现 ADB 协议：
//! - `connect`：`adb -s <serial> get-state` 验证设备可达；
//! - `push_server`：推送本地 scrcpy-server.jar 到设备；
//! - `forward_port`：`adb forward tcp:<local> tcp:<remote>` 建立端口转发；
//! - `start_server`：在设备 shell 内以 `app_process` 启动 scrcpy-server。
//!
//! 纯参数构造函数（`build_*`）可单测；实际执行需环境中有 `adb` 且设备可达。

use std::process::{Command, Output};

use anyhow::{Context, Result};

use crate::scrcpy::server::ServerOptions;

/// 到一台 ADB 设备的连接句柄（持有 serial，供后续 shell/push/forward 复用）。
#[derive(Debug, Clone)]
pub struct AdbConnection {
    serial: String,
}

impl AdbConnection {
    /// 以设备 serial（USB 序列号或 `ip:port` 网络 ADB 地址）构造。
    pub fn new(serial: impl Into<String>) -> Self {
        Self { serial: serial.into() }
    }

    /// 验证设备可达：`adb -s <serial> get-state` 应输出 `device`。
    pub fn connect(&self) -> Result<()> {
        let out = self.run(&["get-state".to_string()])?;
        let state = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if state != "device" {
            return Err(anyhow::anyhow!(
                "设备 {} 状态异常（期望 device，实际 {state:?}）",
                self.serial
            ));
        }
        Ok(())
    }

    /// 推送本地 scrcpy-server.jar 到设备（`device_path` 通常为 `/data/local/tmp/scrcpy-server.jar`）。
    pub fn push_server(&self, local_jar: &str, device_path: &str) -> Result<()> {
        let args = build_push_args(local_jar, device_path);
        let out = self.run(&args)?;
        if !out.status.success() {
            return Err(anyhow::anyhow!(
                "adb push 失败: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            ));
        }
        Ok(())
    }

    /// 建立端口转发：`adb forward tcp:<local> tcp:<remote>`。
    pub fn forward_port(&self, local: u16, remote: u16) -> Result<()> {
        let args = build_forward_args(local, remote);
        let out = self.run(&args)?;
        if !out.status.success() {
            return Err(anyhow::anyhow!(
                "adb forward 失败: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            ));
        }
        Ok(())
    }

    /// 在设备 shell 内启动 scrcpy-server（常驻；其 stdout 为视频/控制流前导）。
    ///
    /// 安全约束：`ServerOptions` 参数会以空格拼接为单个 shell 串经 `adb shell` 执行，
    /// 因此先逐参数做 shell 安全校验（拒绝含 shell 元字符的值），防止命令注入。
    pub fn start_server(&self, options: &ServerOptions) -> Result<()> {
        for arg in options.to_server_args() {
            if !is_shell_safe_token(&arg) {
                return Err(anyhow::anyhow!(
                    "scrcpy-server 参数 {arg:?} 含 shell 元字符，拒绝经 adb shell 执行"
                ));
            }
        }
        let cmd = build_start_server_command(options);
        let args = vec!["shell".to_string(), cmd];
        let out = self.run(&args)?;
        if !out.status.success() {
            return Err(anyhow::anyhow!(
                "启动 scrcpy-server 失败: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            ));
        }
        Ok(())
    }

    /// 执行 `adb -s <serial> <args...>`，返回完整输出。
    fn run(&self, args: &[String]) -> Result<Output> {
        let out = Command::new("adb")
            .arg("-s")
            .arg(&self.serial)
            .args(args)
            .output()
            .context("执行 adb 失败（确认 adb 已安装且在 PATH，且设备可达）")?;
        Ok(out)
    }
}

/// 构造 `adb push` 子命令参数。
pub fn build_push_args(local_jar: &str, device_path: &str) -> Vec<String> {
    vec![
        "push".to_string(),
        local_jar.to_string(),
        device_path.to_string(),
    ]
}

/// 构造 `adb forward` 子命令参数。
pub fn build_forward_args(local: u16, remote: u16) -> Vec<String> {
    vec![
        "forward".to_string(),
        format!("tcp:{local}"),
        format!("tcp:{remote}"),
    ]
}

/// 构造在设备上启动 scrcpy-server 的完整 shell 命令串。
///
/// 调用方（`start_server`）已对参数做 [`is_shell_safe_token`] 校验；
/// 直接调用本函数拼接外部输入前必须先完成该校验。
pub fn build_start_server_command(options: &ServerOptions) -> String {
    let joined = options.to_server_args().join(" ");
    format!(
        "CLASSPATH={} app_process / {} {}",
        scrcpy_protocol::SCRCPY_SERVER_PATH,
        scrcpy_protocol::SCRCPY_SERVER_CLASS_NAME,
        joined,
    )
}

/// 判定单个 token 是否可安全拼入 `adb shell` 命令串。
///
/// 仅允许 scrcpy-server 参数形态：`--key=value`，其中 key/value 限定为
/// `[A-Za-z0-9._-]`。任何 shell 元字符（空格、`;`、`$`、`|`、反引号、括号等）
/// 一律拒绝，防止经 `adb shell` 向目标设备注入命令。
pub fn is_shell_safe_token(token: &str) -> bool {
    if !token.starts_with("--") {
        return false;
    }
    let value = token
        .strip_prefix("--")
        .and_then(|rest| rest.split_once('='))
        .map(|(_, v)| v);
    match value {
        Some(v) => v.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-')),
        None => token[2..].chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-')),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scrcpy::server::ServerOptions;

    #[test]
    fn default_options_are_shell_safe() {
        for arg in ServerOptions::default().to_server_args() {
            assert!(is_shell_safe_token(&arg), "参数 {arg:?} 应通过校验");
        }
    }

    #[test]
    fn rejects_shell_metacharacters() {
        for bad in [
            "--max-size=1080; rm -rf /",
            "--bit-rate=$(reboot)",
            "--raw-stream=true`id`",
            "--max-size=1080 extra",
            "not-a-flag",
        ] {
            assert!(!is_shell_safe_token(bad), "应拒绝 {bad:?}");
        }
    }


    #[test]
    fn forward_args_correct() {
        assert_eq!(
            build_forward_args(4000, 27183),
            vec!["forward".to_string(), "tcp:4000".to_string(), "tcp:27183".to_string()]
        );
    }

    #[test]
    fn push_args_correct() {
        assert_eq!(
            build_push_args("/tmp/scrcpy-server.jar", "/data/local/tmp/scrcpy-server.jar"),
            vec![
                "push".to_string(),
                "/tmp/scrcpy-server.jar".to_string(),
                "/data/local/tmp/scrcpy-server.jar".to_string()
            ]
        );
    }

    #[test]
    fn start_server_command_contains_server_fields() {
        let cmd = build_start_server_command(&ServerOptions::default());
        assert!(cmd.contains("CLASSPATH="));
        assert!(cmd.contains("com.genymobile.scrcpy.Server"));
        assert!(cmd.contains("--max-size=1080"));
        assert!(cmd.contains("--bit-rate=2000000"));
        assert!(cmd.contains("--raw-stream=false"));
        assert!(cmd.contains("--tunnel-forward=true"));
    }
}
