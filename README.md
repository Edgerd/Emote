<div align="center">

# 🚀 Emote

**面向纯局域网的跨平台远程控制软件**

Windows · Linux · Android 三端互相发现、连接与控制
LAN-only · Cross-platform · Remote Control

[![Flutter](https://img.shields.io/badge/Flutter-3.47.4-blueviolet?logo=flutter&logoColor=white)](https://flutter.dev)
[![Rust](https://img.shields.io/badge/Rust-1.92.0-black?logo=rust&logoColor=white)](https://www.rust-lang.org)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20Android-lightgrey)]()
[![License](https://img.shields.io/badge/License-GPL--3.0-blue)]()
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

## ✨ 已实现功能（Dev-2.0）

- [x] 三端共用的 Material Design 3 界面框架
- [x] mDNS 设备发现（Rust 核心 + Flutter 服务层）
- [x] 设备列表页：展示发现的设备与传输层能力
- [x] 连接状态页：连接状态 / 心跳 / 传输层详情
- [x] QUIC 优先建连、失败回退 TCP
- [x] TCP 连接默认启用 `TCP_NODELAY`
- [x] Android MulticastLock 的获取与释放
- [x] Windows / Linux / Android 三端 CI 自动构建

---

## 🗺️ 未来规划

> 以下功能仍在开发中，欢迎一起贡献 💡

### 核心控制链路
- [ ] Windows ↔ Linux 双向控制
- [ ] Android 控制桌面端（自研捕获 + 编码 + 输入注入）
- [ ] 桌面端控制 Android（复用 scrcpy，二进制或库）
- [ ] H.264 软编/软解与视频渲染

### 体验与性能
- [ ] **M3E 界面（Material 3 Expressive）统一**
- [ ] 多会话标签页管理
- [ ] 断线自动重连（QUIC 0-RTT）
- [ ] 自适应码率 / 帧率控制
- [ ] FFI 零拷贝优化与硬件加速解码
- [ ] 性能监控浮层（延迟 / 帧率 / 码率实时显示）

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

- **Dev-2.0**（开发版）：当前最新开发版本，包含 mDNS 发现、连接与双传输层。
- **v1.0.0**（稳定版）：首个稳定发行版。

每个 Release 均附带 Windows（zip）、Linux（tar.gz / AppImage）与 Android（apk）三端产物。发布说明与已知问题见各 [Release](https://github.com/Edgerd/Emote/releases) 详情。

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

本项目基于 GPL-3.0 开源协议发布，请在遵守协议的前提下使用与二次开发。