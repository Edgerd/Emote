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

## 分支约定 / Branching

按大段任务推进，每完成一个阶段即上传一次。当前阶段：`dev-1.0`。