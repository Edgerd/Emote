# Emote Dev-2.0

> **发布通道**：开发版（Dev） · **标签**：`Dev-2.0`
> **建议安装**：v1.0.0（稳定版）之后的功能迭代版本。

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
- 完善 Rust 核心 `libemote_core.so` 在 Linux 发布包内的加载与打包（RPATH `$ORIGIN/lib`），Linux 端开箱即用。
- macOS/iOS 平台加入编译桩（`platform/macos_stub.rs`、`ios_stub.rs`），为后续三端布局预留。

### 🔧 修复
- 修复 Flutter 侧 `ConnectionState` 命名冲突（`hide ConnectionState`）。
- 修复 `Icons.inbound` 未定义导致的编译错误（改用 `Icons.inbox`）。
- 移除未使用变量、不可达 `switch default` 分支，消除 analyzer 告警（`flutter analyze` 0 问题）。
- 修复 `flutter_rust_bridge_codegen generate` 在 CI 中的工作目录问题。

### 📋 其它
- 发布流水线支持 `Dev-*` 标签触发构建。
- 应用版本号提升至 `2.0.0+2`。

---

## 已知问题
- Linux/Windows 三端在同一局域网互相发现、心跳长连接保活仍需真机长时间联调验证（沙箱无真实组播链路）。
- AppImage 为“尽力而为”产物，若无法打包则以 tar.gz 为准。

---

## 下一步计划

- [ ] 实现 Windows ↔ Linux 双向控制
- [ ] 实现 Android 控制桌面端（自研捕获+编码+注入）
- [ ] 复用 scrcpy 实现桌面端控制 Android
- [ ] M3E（Material 3 Expressive）界面统一
- [ ] 多会话标签页与自适应码率控制
- [ ] 硬件加速解码与 FFI 零拷贝优化

---

## 使用说明

1. 三端设备连接**同一局域网**。
2. 启动 Emote，授予必要权限（Android 需「本地网络/组播」权限）。
3. 在设备列表页使用 mDNS 发现对端并建立连接。
4. 若发现失败：Android 请确认已获取 MulticastLock；桌面端请确认防火墙放行 UDP 组播与 QUIC/TCP 端口。

> 仅面向**纯局域网**使用，请勿跨公网部署。

## 下载

见本 Release 页面下方 **Assets**。