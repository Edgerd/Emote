# Emote 4.0.0

> **发布通道**：Pre-release（预览版） · **标签**：`Dev-4.0`
> **建议安装**：尝鲜预览版本，主要用于性能与可靠性特性验证；生产环境请选用正式版。

---

## 平台支持

> 使用前请先阅读下方「使用说明」。

| 平台 | 包 | 说明 |
| --- | --- | --- |
| Windows x86_64 | `emote-windows-x86_64.zip` | 解压后运行 `emote.exe` |
| Linux x86_64 | `emote-linux-x86_64.tar.gz` | 解压后运行 `./emote`；另有 `emote-linux-x86_64.AppImage`（尽力而为） |
| Android (APK) | `app-release.apk` | 安装后需授予「本地网络」权限 |

---

## 更新明细

### 🚀 新特性
- **硬件解码探测与选择器（4.4）**：`decoder/hw.rs` 多后端探测（各平台硬件解码枚举）+ `DecoderSelector` 优先硬件、失败自动回退 openh264 软解；无 GPU 环境（沙箱/CI）优雅降级，不 panic。
- **自适应码率（4.5）**：`encoder/qos.rs` `QosController` 按端到端延迟动态调整编码码率/帧率，带冷却间隔防抖；已集成到 `DesktopSelfSession`，码率漂移时自动重建编码器。
- **断线重连（4.6）**：`connection/reconnect.rs` 指数退避 + 随机抖动 + 尝试上限，避免网络抖动导致的重连风暴。
- **多会话管理 UI（4.2）**：
  - 桌面端 `SessionContainerPage`：标签条 + `IndexedStack` 保活后台会话；
  - 移动端 `MobileSessionHost` / `MobileSessionStack`：页面栈管理，返回键关闭最上层会话；
  - 「更多」页新增「多会话管理」入口，按平台自动路由。
- **性能监控浮层（4.9）**：`MetricsOverlay` 叠加于视频区域，展示实时 FPS、码率、延迟与编/解码耗时；FPS / 码率为 Dart 侧滑动窗口实测值。

### 🔧 修复
- `RemoteSessionService` 停止时清空帧统计窗口，避免残留 FPS/码率读数。
- 浮层数据源统一由服务层提供，帧字节数与时间戳同步记录。

### 📋 其它
- `cargo test` 全绿：新增第 4 段集成测试（`segment4_qos_hwdec.rs`：硬件解码探测回退、QoS 会话级端到端、控制器边界）。
- 应用版本号提升至 `4.0.0+6`（预览版）。

---

## 已知问题
- 端到端延迟与编/解码耗时的 FFI metrics 接口尚未经 FRB 生成，浮层中暂显示 0 占位（FPS / 码率已实测）。
- FRB 重生成、`flutter analyze`、三端整包（Windows/Linux/Android）在 CI 上验证；沙箱无 Flutter/NDK 工具链。
- 硬件解码实际生效需真机（GPU/媒体框架）联调；无硬件环境一律走软解兜底。
- 桌面控 Android 方向仍依赖本机手动放置 scrcpy-server.jar（同 Dev-3.0）。

---

## 下一步计划

- [ ] FFI metrics 接口（延迟 / 编解码耗时）经 FRB 生成接入浮层
- [ ] QUIC 证书指纹发布（mDNS TXT `cert=`）并启用严格对端校验
- [ ] scrcpy-server.jar 分发
- [ ] 文档交付（5）

---

## 使用说明

1. 三端设备连接**同一局域网**。
2. 启动 Emote，授予必要权限（Android 需「本地网络 / 组播」权限）。
3. 进入「更多」→「远程会话」或「多会话管理」，启动会话；运行中视频区域左下角显示性能浮层。
4. 桌面端多标签切换、移动端页面栈返回均可保活后台会话。

> 仅面向**纯局域网**使用，请勿跨公网部署。

## 下载

见本 Release 页面下方 **Assets**。
