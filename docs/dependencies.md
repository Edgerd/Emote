# Emote 依赖版本锁定清单

> 所属阶段：第 1.1 段「环境与版本锁定」。本文档用于可复现地锁定 Emote 各依赖版本。
> 本段**不创建任何项目代码**，以下 Cargo.toml / pubspec 声明片段为后续 Rust / UI 段落地时的参考。

## 一、工具链版本表（已验证）

| 工具 | 版本 | 安装方式 | 验证命令 |
| --- | --- | --- | --- |
| Flutter (stable) | 3.47.4 | 源码克隆至 `/opt/flutter`，`stable` 通道 | `flutter --version` |
| Dart | 3.13.3 | 随 Flutter 自带 | `dart --version` |
| DevTools | 2.60.0 | 随 Flutter 自带 | `flutter doctor -v` |
| Rust (stable) | 1.92.0 | rustup，锁定于 `rust-toolchain.toml` | `rustc --version`；`cargo --version` |
| flutter_rust_bridge_codegen | 2.13.0 | `cargo install flutter_rust_bridge_codegen@2.13.0 --locked` | `flutter_rust_bridge_codegen --version` |
| cargo-ndk | 4.1.2 | `cargo install cargo-ndk@4.1.2 --locked` | `cargo ndk --version` |
| JDK | 17.0.2 | 系统包 | `java -version` |
| cmake | 3.28.3 | 系统包 | `cmake --version` |
| ninja | 1.11.1 | 系统包 | `ninja --version` |
| clang | 17.0.0 | 系统包 | `clang --version` |
| Android cmdline-tools | 12.0 | sdkmanager | `sdkmanager --version` |
| Android platform | android-36 | sdkmanager | `ls $ANDROID_HOME/platforms` |
| Android build-tools | 36.0.0 | sdkmanager | `ls $ANDROID_HOME/build-tools` |
| Android NDK | 28.2.13676358 | sdkmanager | `ls $ANDROID_HOME/ndk` |
| Android platform-tools (adb) | 1.0.41 | sdkmanager | `adb version` |

- Flutter 版本记录：`.fvmrc`（`3.47.4` / `stable`）。
- Rust 工具链锁定：`rust-toolchain.toml`（channel `1.92.0`，targets 含 `aarch64-linux-android`、`armv7-linux-androideabi`、`x86_64-linux-android`、`x86_64-unknown-linux-gnu`）。

## 二、三端系统依赖清单

### Windows 构建依赖
- Visual Studio 2022（含「使用 C++ 的桌面开发」工作负载：MSVC、Windows 10/11 SDK、CMake）。
- Git，Flutter SDK，Rust toolchain（MSVC host）。

### Linux 构建依赖
- `clang`、`cmake`、`ninja-build`、`pkg-config`、`libgtk-3-dev`、`liblzma-dev`、`mesa-utils`（`flutter doctor` Linux 桌面工具链要求）。
- Linux 输入注入备选：`libei`（若使用 reis 运行时；uinput 走内核接口，不额外引入 crate）。

### Android SDK / NDK 组件
- platform-tools、platforms;android-36、build-tools;36.0.0、ndk;28.2.13676358（与 Flutter 3.47.4 stable 推荐 NDK 一致）、cmdline-tools;latest、Java 17。

## 三、新增依赖版本锁定表

| 用途 | 依赖 | 版本 | 锁定方式 | 引入时机 |
| --- | --- | --- | --- | --- |
| 默认传输层 QUIC | `quinn` | 0.11.11 | Cargo.toml `quinn = "0.11.11"` | Rust 段（传输层） |
| TCP 回退 | `tokio::net::TcpStream` | — | 由 quinn 传递引入 Tokio；如需显式声明 `tokio`，在 Rust 段创建 Cargo.toml 时精确锁定具体版本 | Rust 段（回退路径） |
| 零拷贝 buffer（性能工程） | `bytes` | 1.12.1 | Cargo.toml `bytes = "1.12.1"` | Rust 段 |
| 动态取色（Flutter / M3） | `dynamic_color` | 2.1.0 | pubspec `dynamic_color: ^2.1.0` | 主题 / UI 段 |
| Linux 输入注入（libei 纯 Rust 实现） | `reis` | 0.7.0 | Cargo.toml `reis = { version = "=0.7.0", features = ["tokio"] }`（仅 Linux 目标） | 输入注入段（1.4+） |
| 可选软件解码后端 | `ffmpeg-next` | 8.1.0 | Cargo.toml `ffmpeg-next = { version = "=8.1.0", optional = true }` | 4.3 段按需启用 |

> 版本号均为具体数字（已完成 crates.io / pub.dev 核实）：quinn 0.11.11（MSRV 1.85，Rust 1.92.0 兼容）、bytes 1.12.1、dynamic_color 2.1.0、reis 0.7.0、ffmpeg-next =8.1.0（维护模式，官方建议精确锁定）。

## 四、参考声明片段（后续段落地，本段不创建）

### Cargo.toml（Rust 段）
```toml
[dependencies]
# 默认传输层：QUIC
quinn = "0.11.11"
# 零拷贝 buffer
bytes = "1.12.1"
# Linux 输入注入（libei 纯 Rust 绑定，仅 Linux target 启用）
reis = { version = "=0.7.0", features = ["tokio"] }
# 可选软件解码后端（4.3 段启用）
ffmpeg-next = { version = "=8.1.0", optional = true }
```

### pubspec.yaml（主题 / UI 段）
```yaml
dependencies:
  # M3 动态取色，Android 动态色 + 深色模式
  dynamic_color: ^2.1.0
```

## 五、阶段边界提醒
- `scrcpy-server`：桌面端控制 Android 所需，**3.1 段单独下载**，本段不安装。
- `ffmpeg-next`：可选软件解码后端，**4.3 段按需引入**，本段仅锁定版本。
- 本阶段不安装 scrcpy / ffmpeg / libei 等系统级远程控制运行时依赖。