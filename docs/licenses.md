# 开源许可证汇总

> 项目自身许可证：**Apache-2.0**（见根目录 [LICENSE](LICENSE)）。
> 版本取自 `rust/emote_core/Cargo.lock`（Rust）与 `app/pubspec.yaml`（Flutter），基线 Dev-5.0。

## 结论

**所有直接与间接依赖的许可证均与 Apache-2.0 兼容，无冲突，无需替换。**

## Rust 依赖（emote_core）

| 项目 | 版本 | 许可证 | 用途 |
| --- | --- | --- | --- |
| flutter_rust_bridge | 2.13.0 | MIT | Rust ↔ Dart FFI 桥接运行时 |
| quinn | 0.11.12 | MIT OR Apache-2.0 | QUIC 传输层（默认） |
| tokio | 1.53.3 | MIT | 异步运行时 |
| mdns-sd | 0.11.5 | Apache-2.0 OR MIT | mDNS 设备发现 |
| bytes | 1.12.1 | MIT | 零拷贝 buffer / 消息帧 |
| rcgen | 0.14.10 | MIT OR Apache-2.0 | QUIC 自签证书生成（LAN 对等端） |
| serde | 1.0.229 | MIT OR Apache-2.0 | 消息/设备结构序列化 |
| uuid | 1.28.0 | Apache-2.0 OR MIT | 设备唯一 ID（v4） |
| anyhow | 1.0.104 | MIT OR Apache-2.0 | 错误统一 |
| futures | 0.3.34 | MIT OR Apache-2.0 | QUIC async 并发 |
| dashmap | 5.5.3 | MIT | 连接/会话并发容器 |
| tracing | 0.1.44 | MIT | 诊断日志 |
| sha2 | 0.10.9 | MIT OR Apache-2.0 | QUIC 证书指纹（SHA-256） |
| fastrand | 2.5.0 | Apache-2.0 OR MIT | 重连抖动 |
| scrcpy-protocol | 0.1.1 | MIT OR Apache-2.0 | scrcpy 协议层（VideoPacket/ControlSender/h264） |
| libc | 0.2.191 | MIT OR Apache-2.0 | uinput ioctl（纯 C 绑定） |
| openh264 | 0.5.0 | BSD-2-Clause | H.264 软编解码（crate 绑定） |
| windows | 0.61.3 | MIT OR Apache-2.0 | Win32 SendInput 注入（Windows target） |
| x11-dl | 2.21.0 | MIT | X11/XTest 动态加载（Linux target） |
| pinray | 0.2.7 | MIT | 屏幕捕获（可选 `capture` feature，默认关） |

> **openh264 特别说明**：Rust crate `openh264` 为 BSD-2-Clause，与 Apache-2.0 兼容；但其封装的 **Cisco OpenH264 预编译二进制**分发需向 Cisco 申请免费商用许可。本项目 CI 从源码构建、不分发其二进制，不受此约束。分发含 OpenH264 二进制的安装包前需完成申请。

## Flutter 依赖（app/pubspec.yaml）

| 项目 | 版本 | 许可证 | 用途 |
| --- | --- | --- | --- |
| flutter / flutter_test / integration_test | SDK（3.47.4 / Dart 3.13.3） | BSD-3-Clause（Flutter 引擎与工具） | UI 框架与测试 |
| flutter_rust_bridge | 2.13.0 | MIT | Dart 侧 FFI 运行时 |
| dynamic_color | 1.9.0 | Apache-2.0 | Material You 动态颜色汲取 |
| shared_preferences | ^2.5.5 | BSD-3-Clause | 设置持久化 |
| path_provider | ^2.1.5 | BSD-3-Clause | 平台目录定位（字体缓存等） |
| archive | ^3.6.1 | MIT | 字体压缩包解压 |
| file_picker | ^8.3.5 | MIT | 自定义字体文件选择 |
| package_info_plus | ^8.0.0 | MIT | 应用版本信息（「检查更新」） |
| crypto | ^3.0.7 | BSD-3-Clause | 字体包 SHA-256 完整性校验 |
| cupertino_icons | ^1.0.8 | MIT | 图标资源 |
| flutter_lints | ^6.0.0（dev） | BSD-3-Clause | 静态检查规则集 |

## 第三方代码资产

| 项目 | 许可证 | 用途 |
| --- | --- | --- |
| scrcpy（协议参考 / server jar，运行时依赖） | Apache-2.0（Genymobile） | 桌面控 Android 方向的 server 端；jar 分发未完成，启用分发时需保留其 Apache-2.0 声明 |
| HarmonyOS Sans 字体 | 华为品牌字体许可（官方域下载、SHA-256 校验） | 应用默认字体；仅运行时下载不分发 |

## 兼容性核对

- MIT / BSD-2 / BSD-3 / Apache-2.0 / MIT-OR-Apache-2.0 双许可 → 全部与 Apache-2.0 单向兼容（本项目的 Apache-2.0 保留版权与 NOTICE 义务即可）。
- 无 GPL / LGPL / AGPL / 无署名禁止类依赖。
- 发布包要求：随包附带 `LICENSE`（Apache-2.0）与本文档（`THIRD_PARTY_LICENSES` 义务由 `docs/licenses.md` 承担）。
