# Emote 3.0.0

> **发布通道**：Pre-release（预览版） · **标签**：`Dev-3.0`
> **建议安装**：尝鲜预览版本，主要用于三方向远程控制功能验证；生产环境请选用正式版。

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
- **三方向远程控制会话（3.7 / 3.8 / 3.9）**：
  - `ScrcpySession`：桌面端控制 Android（复用 scrcpy 协议，adb 推送并启动 server，解码实时画面）。
  - `DesktopSelfSession`：Android 控制桌面端（自研屏幕捕获 + H264 编码上行）。
  - `DesktopFromSession`：桌面端接收对端画面并下发输入（触摸 / 按键 / 滚轮）。
- **scrcpy 协议层（3.1）**：`scrcpy/adb.rs`（AdbConnection：connect/push_server/forward_port/start_server）、`server.rs`（ServerOptions→命令行）、`video.rs`（8B pts|flags + 4B len + payload 包解析）、`control.rs`（控制指令序列化）。
- **软编解码（桌面）**：openh264 编码（SPS/AnnexB）+ 解码，`codec_backend_linked` / `encoder_available` / `decoder_available` 能力位。
- **输入事件体系**：`InputEvent`（Touch/Key/Text/Scroll）大端 tag 序列化 + 各平台后端（Windows SendInput、Linux X11 XTest / uinput），沙箱不可用时优雅降级为 `NullSink`，不 panic。
- **合成帧源**：确定性 I420 合成源用于 headless 全链路（采集→编码→解码）测试。
- **FFI 与 Flutter**：`api/session.rs`（`SessionHandle` 不透明句柄）+ `RemoteView`（RawImage 渲染）+ `RemoteSessionService` + `RemoteSessionPage`，接入「更多」页。

### 🔧 修复
- `build.rs` 改用 `CARGO_CFG_TARGET_OS` 判定桌面目标，修复此前按 arch 判定导致 `desktop` cfg 未生效、openh264 编解码代码/测试被静默排除的问题。
- dashmap `RefMut` 路径错误，改为内联 `get_mut` 可变守卫。
- 清理未使用导入与未用变量，`cargo build --release` GNU 桌面目标 0 警告。

### 📋 其它
- `cargo test` 全绿：24 库内 + 5 双实例 + 3 三方向 pipeline，合计 32 通过 0 失败（mDNS/QUIC 组播相关 2 项在容器内优雅跳过）。
- 应用版本号提升至 `3.0.0+3`（预览版）。

---

## 已知问题
- **桌面控 Android 方向开箱不可用**：scrcpy-server.jar 分发未完成（见「下一步计划」），`push_server` 需要本机已手动放置 jar，否则该方向会话无法启动；`ScrcpySession` 代码可用但缺 jar 时失败。
- QUIC 客户端当前跳过对端证书校验（局域网信任模型），同网段可被伪造；严格校验（`make_client_endpoint_strict`，证书 CN 已绑定设备 ID）已就绪，待 `cert=` 指纹经 mDNS TXT 发布后启用。
- FRB 重生成、`flutter analyze`、三端整包（Windows/Linux/Android）在 CI 上验证；沙箱无 Flutter/NDK 工具链。
- 真机 scrcpy 全链路、桌面双向控制、跨端局域网互发现与 30s+ 心跳保活需真机联调。
- AppImage 为「尽力而为」产物，若无法打包则以 tar.gz 为准。

---

## 下一步计划

- [ ] scrcpy-server.jar 分发（5，当前仅保留 `SCRCPY_SERVER_PATH` 常量 + `push_server` 接口；完成前桌面控 Android 方向开箱不可用）
- [ ] QUIC 证书指纹发布（mDNS TXT `cert=`）并启用严格对端校验
- [ ] 硬件加速解码（4.4）
- [ ] 自适应码率与断线重连（4.5 / 4.6）
- [ ] 文档交付（5）
- [ ] 多会话标签页

---

## 使用说明

1. 三端设备连接**同一局域网**。
2. 启动 Emote，授予必要权限（Android 需「本地网络 / 组播」权限）。
3. 在设备列表页使用 mDNS 发现对端并建立连接。
4. 进入「更多」→「远程会话」，选择方向并启动；桌面控制 Android 需先完成 adb 连接。

> 仅面向**纯局域网**使用，请勿跨公网部署。

## 下载

见本 Release 页面下方 **Assets**。
