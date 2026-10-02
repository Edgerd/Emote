<div align="center">

# 🚀 Emote

**面向纯局域网的跨平台远程控制软件**

Windows · Linux · Android 三端互相发现、连接与控制
LAN-only · Cross-platform · Remote Control

[![Flutter](https://img.shields.io/badge/Flutter-3.47.4-blueviolet?logo=flutter&logoColor=white)](https://flutter.dev)
[![Rust](https://img.shields.io/badge/Rust-1.92.0-black?logo=rust&logoColor=white)](https://www.rust-lang.org)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20Android-lightgrey)]()
[![License](https://img.shields.io/badge/License-Apache--2.0-blue)]()
[![Release](https://img.shields.io/github/v/release/Edgerd/Emote?label=Release)](https://github.com/Edgerd/Emote/releases)

</div>

---

## 📖 关于本项目

Emote 是一款面向**纯局域网**的跨平台远程控制软件，端到端在同一局域网内即可完成设备的发现、连接与控制，**不依赖公网服务器、不经过第三方中转**。

- 🖥️ **UI**：Flutter（三端共用一套界面），Material Design 3
- ⚙️ **核心逻辑**：Rust（经 `flutter_rust_bridge` 2.x 与 Flutter 通信）
- 🌐 **设备发现**：mDNS（局域网内自动发现设备）
- 🔌 **传输层**：QUIC（quinn，默认） + TCP 回退，TCP 默认启用 `TCP_NODELAY`

> ⚠️ 纯局域网使用，请勿跨公网部署。

---

## ✨ 已实现功能

### Dev-3.0（当前最新）
- [x] 三方向远程控制会话：`ScrcpySession`（桌面控 Android）、`DesktopSelfSession`（Android 控桌面）、`DesktopFromSession`（桌面接收对端画面并下发输入）
- [x] scrcpy 协议层（adb 连接 / server 推送启动 / 视频与控制流解析）
- [x] 桌面端 openh264 软编/软解（Android target 不链接，能力位探测、优雅降级）
- [x] 输入事件体系（Windows SendInput、Linux X11 XTest / uinput，沙箱不可用时降级 `NullSink`）
- [x] `RemoteView`（RawImage 渲染）+ `RemoteSessionService` + 「更多 → 远程会话」页

### Dev-2.0 ～ v2.3.1
- [x] 三端共用的 Material Design 3 界面框架
- [x] mDNS 设备发现（Rust 核心 + Flutter 服务层），TXT 属性解析修复、自发现过滤
- [x] 设备列表页 / 连接状态页：设备与传输层能力、心跳与连接详情
- [x] QUIC 优先建连、失败回退 TCP；TCP 默认启用 `TCP_NODELAY`
- [x] Android MulticastLock 的获取与释放
- [x] HarmonyOS Sans 字体启动下载（流式写盘 + 缓存复用）
- [x] MD3E「更多」页重构、M3E 波浪进度条、开发者选项与分级运行日志
- [x] Windows / Linux / Android 三端 CI 自动构建

---

## 🗺️ 未来规划

> 以下功能仍在开发中，欢迎一起贡献 💡

### 核心控制链路
- [ ] Windows ↔ Linux 双向控制
- [ ] scrcpy-server.jar 自动分发（当前桌面控 Android 方向缺少 jar 时不可用，需手动放置）
- [ ] 硬件加速解码（4.4）
- [ ] 自适应码率与断线重连（4.5 / 4.6）

### 体验与性能
- [ ] 多会话标签页管理
- [ ] 性能监控浮层（延迟 / 帧率 / 码率实时显示）
- [ ] FFI 零拷贝优化
- [ ] QUIC 对端证书指纹经 mDNS TXT（`cert=`）发布并启用严格校验（当前为局域网信任模型，见「网络访问与信任模型」）

### 其它
- [ ] macOS / iOS 平台支持
- [ ] 应用内主题色自定义与深浅色跟随系统

---

## 📁 目录结构

```text
.
├── app/                # Flutter 三端共用 UI
│   ├── lib/
│   │   ├── pages/      # 页面（设备列表 / 连接状态 / 设置）
│   │   └── services/   # 服务层（发现 / 连接 / 权限）
│   └── linux/ etc.     # 各平台 Runner 与打包配置
├── rust/
│   └── emote_core/     # Rust 核心 crate（发现/连接/传输/协议）
├── docs/               # 架构与文档、验收报告
├── scripts/            # 构建 / 工具脚本
└── .github/            # CI/CD 工作流与 Release 说明
```

---

## 🔧 构建与开发

### 环境

依赖版本已锁定，见 [dependencies.md](docs/dependencies.md) 与 [rust-toolchain.toml](rust-toolchain.toml)：

| 组件 | 版本 |
| --- | --- |
| Flutter (stable) | 3.47.4 |
| Dart | 3.13.3 |
| Rust (stable) | 1.92.0 |
| flutter_rust_bridge_codegen | 2.13.0 |
| cargo-ndk | 4.1.2 |
| JDK / cmake / ninja / clang | 17 / 3.28 / 1.11 / 17 |

### 生成 FFI 绑定与构建

```sh
# 1. 生成 Rust ↔ Flutter 的 FFI 绑定
flutter_rust_bridge_codegen generate

# 2. 编译 Rust 核心库
(cd rust/emote_core && cargo build --release)

# 3. 构建各平台应用
cd app
flutter pub get
flutter build linux --release     # Linux（需要 GTK3 等）
flutter build windows --release   # Windows
flutter build apk --release       # Android（需要 NDK）
```

### 一键脚本

Windows / Linux / Android 也提供了脚本，见 [scripts/](scripts/)：

```sh
sh scripts/build_linux.sh
bash scripts/build_android.sh
powershell -File scripts/build_windows.ps1
```

### 静态检查

```sh
cd app && flutter analyze
```

---

## 📦 发行版

- **Dev-3.0**（预览版，当前最新）：三方向远程控制会话、scrcpy 协议层、桌面 openh264 软编解码。
- **v2.3.1 / v2.3.1-hotfix**（预览版）：MD3E「更多」页、M3E 波浪进度条、开发者选项（hotfix 为 Android 构建修复）。
- **v2.2.1**（首个正式版）：mDNS TXT 解析修复、自发现过滤、字体下载流式写盘。
- **Dev-2.1 / Dev-2.0**（预览版）：Rust 核心与 FFI 桥接、mDNS 发现框架、双传输层。
- **v1.0.0**（预览版）：首个公开预览，工程骨架与基础连通性。

每个 Release 均附带 Windows（zip）、Linux（tar.gz / AppImage）与 Android（apk）三端产物。完整发布说明见各 [Release](https://github.com/Edgerd/Emote/releases) 详情（`.github/release-notes/`）。

---

## 🌐 网络访问与信任模型

- 设备发现 / 连接 / 控制均在局域网内完成，**唯一**的公网访问是首次启动时下载 HarmonyOS Sans 字体包（约 49.7 MB，华为官方域 `developer.huawei.com`，SHA-256 固定校验 + 重定向白名单，见 [harmony_font_loader.dart](app/lib/services/harmony_font_loader.dart)）。下载失败自动回退系统字体，不影响局域网功能；「设置 → 个性化 → 纯局域网模式」可完全禁止该公网下载。
- QUIC（TLS）当前为**局域网信任模型**：对端证书指纹尚未经 mDNS 发布，客户端默认跳过证书校验（LAN 信任模型）；TCP 回退通道为明文。同网段设备可窃听 / 伪造通道，请勿在不可信网络使用；严格校验能力（`make_client_endpoint_strict` + 证书 CN 绑定设备 ID）已就绪，随「`cert=` 指纹发布」一并启用。

---

## 🤝 贡献

欢迎任何形式的贡献：

1. Fork 本仓库并创建功能分支
2. 提交清晰的改动
3. 打开 Pull Request
4. 等待 Review 与合并

如有功能建议或 Bug，请提 [Issue](https://github.com/Edgerd/Emote/issues)。

---

## 📄 License

本项目基于 Apache-2.0 开源协议发布（见根目录 [LICENSE](LICENSE)），请在遵守协议的前提下使用与二次开发。

> 第三方依赖 `openh264` 同为 Apache-2.0，但官方规定分发其**预编译二进制**需另行申请免费商用许可（见 openh264 仓库 License 说明）；从源码自行构建则无需申请。