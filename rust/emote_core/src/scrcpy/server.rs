//! `scrcpy::server` —— scrcpy-server 启动参数（第 3.1 段）。
//!
//! 对应文档第 3.1 段「ServerOptions 结构体，含 max_size、bit_rate、max_fps、tunnel_forward」。

/// scrcpy-server 启动参数。
#[derive(Debug, Clone)]
pub struct ServerOptions {
    /// 视频最大边（像素）；`0` 表示不限制。
    pub max_size: u32,
    /// 目标码率（bps）。
    pub bit_rate: u32,
    /// 最大帧率；`0` 表示不限制。
    pub max_fps: u32,
    /// 是否以 tunnel-forward 模式运行（经 ADB 转发，而非直接 TCP）。
    pub tunnel_forward: bool,
}

impl Default for ServerOptions {
    fn default() -> Self {
        Self {
            max_size: 1080,
            bit_rate: 2_000_000,
            max_fps: 0,
            tunnel_forward: true,
        }
    }
}

impl ServerOptions {
    /// 生成传给 scrcpy-server 的参数串（不含 `CLASSPATH`/`app_process` 前缀）。
    pub fn to_server_args(&self) -> Vec<String> {
        let mut v = vec![
            format!("--max-size={}", self.max_size),
            "--video-codec=h264".to_string(),
            format!("--bit-rate={}", self.bit_rate),
        ];
        if self.max_fps > 0 {
            v.push(format!("--max-fps={}", self.max_fps));
        }
        // 关闭 raw-stream：保留 12 字节 video packet 帧格式（`VideoPacket::read_from` 依赖它）。
        v.push("--raw-stream=false".to_string());
        if self.tunnel_forward {
            v.push("--tunnel-forward=true".to_string());
        }
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_args_shape() {
        let args = ServerOptions::default().to_server_args();
        assert!(args.contains(&"--max-size=1080".to_string()));
        assert!(args.contains(&"--bit-rate=2000000".to_string()));
        assert!(args.contains(&"--raw-stream=false".to_string()));
        assert!(args.contains(&"--tunnel-forward=true".to_string()));
        // 默认不限制帧率 → 不应出现 --max-fps
        assert!(!args.iter().any(|a| a.starts_with("--max-fps")));
    }

    #[test]
    fn fps_and_tunnel_flags() {
        let opts = ServerOptions {
            max_size: 720,
            bit_rate: 1_000_000,
            max_fps: 30,
            tunnel_forward: false,
        };
        let args = opts.to_server_args();
        assert!(args.contains(&"--max-size=720".to_string()));
        assert!(args.contains(&"--max-fps=30".to_string()));
        assert!(!args.iter().any(|a| a.contains("tunnel-forward")));
    }
}
