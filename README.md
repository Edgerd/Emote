# Emote

Emote 是一个面向**纯局域网**的跨平台远程控制软件，支持 Windows、Linux 和 Android 三端互相发现、连接与控制。
Emote is a LAN-only, cross-platform remote control application for Windows, Linux, and Android.

## 技术栈 / Tech Stack

- **UI**: Flutter（三端共用），Material Design 3
- **核心逻辑 / Core**: Rust（通过 `flutter_rust_bridge` 2.x 与 Flutter 通信）
- **包名 / Organization**: `com.emote.app`
- **Rust crate**: `emote_core`
- **Android minSdk**: 23

## 支持范围 / Scope

- Windows ↔ Linux 双向控制
- Windows/Linux ↔ Android 双向控制（含 Android 作为主控端控制桌面端）
- Android 控制桌面端：复用开源方案优化，不自研视频编码器和网络协议
- 桌面端控制 Android：复用 scrcpy（二进制或库，可稍作修改）

## 目录结构 / Structure

```
├── app/              # Flutter 三端共用 UI
├── rust/
│   └── emote_core/   # Rust 核心 crate
├── docs/             # 架构与文档
└── scripts/          # 构建 / 工具脚本
```

## 环境与版本锁定 / Environment & Version Lock

本段（1.1）已在开发机完成基础环境搭建并锁定版本（Flutter stable / Rust stable / flutter_rust_bridge 2.x 最新）。

| 组件 | 版本 |
| --- | --- |
| Flutter (stable) | 3.47.4（框架修订 9584c6713b / Engine 0e228ec8c8） |
| Dart | 3.13.3 |
| Rust (stable) | 1.92.0 |
| flutter_rust_bridge_codegen | 2.13.0 |
| cargo-ndk | 4.1.2 |
| Android SDK cmdline-tools | 12.0 |
| Android platform-tools | 37.0.1 |
| Android platform | android-36 |
| Android build-tools | 36.0.0 |
| Android NDK | 28.2.13676358 |
| JDK | 17.0.2 |
| cmake / ninja / clang | 3.28.3 / 1.11.1 / 17.0.0 |

- Rust 工具链锁定：见 [rust-toolchain.toml](./rust-toolchain.toml)
- Flutter 版本记录：见 [.fvmrc](./.fvmrc)

### 镜像环境变量

```sh
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export RUSTUP_DIST_SERVER=https://rsproxy.cn
export RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup
export ANDROID_HOME=/opt/android-sdk
```

## 分支约定 / Branching

按大段任务推进，每完成一个阶段即上传一次。当前阶段：`dev-1.0`。