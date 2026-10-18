# 最终交付报告

> 项目：Emote —— 面向纯局域网的跨平台远程控制软件（Windows / Linux / Android）
> 报告日期：2026-10-18 · 版本：5.0.0+7（Dev-5.0 预览版）

## 一、项目概述

- **目标**：三端（Windows / Linux / Android）在同一局域网内互相发现、连接与远程控制，不依赖公网服务器与第三方中转。
- **范围**：设备发现（mDNS）、双传输层（QUIC 优先 / TCP 回退）、三方向远控会话（scrcpy、Android 控桌面、桌面互控管线）、多会话并发管理、自适应码率、断线重连、硬件解码探测与降级、性能监控、M3E 主题系统、三端 CI 打包发布。
- **技术路线**：Flutter（UI）+ Rust（核心，`emote_core` crate）+ flutter_rust_bridge 2.13.0 FFI。
- **交付形态**：可编译运行的三端客户端 + Rust 核心库（cdylib/staticlib/rlib）+ 全套开发者文档与验收报告 + CI 自动发布流水线。

## 二、交付物清单

### 代码

| 路径 | 说明 |
| --- | --- |
| `rust/emote_core/` | Rust 核心 crate：api / protocol / discovery / transport / connection（含 reconnect）/ session（三方向）/ capture / encoder（含 qos）/ decoder（含 hw）/ input / scrcpy / metrics / platform |
| `app/` | Flutter 三端应用（pages / services / widgets / theme / FRB 绑定） |
| `flutter_rust_bridge.yaml` | FRB 代码生成配置 |
| `scripts/` | `build_windows.ps1` / `build_linux.sh` / `build_android.sh` + `perf_snapshot.sh` / `perf_snapshot.ps1` |
| `.github/workflows/release.yml` | 三端构建 + Release 创建流水线（标签触发：`v*`、`Dev-*`） |
| `rust-toolchain.toml` | Rust 工具链锁定（1.92.0） |

### 文档（docs/）

| 文档 | 说明 |
| --- | --- |
| [README.md](../README.md) | 项目简介、架构图、编译运行指南（第 5.1 段） |
| [ffi_reference.md](ffi_reference.md) | FFI 接口清单（与代码一一对应，第 5.2 段） |
| [module_dependencies.md](module_dependencies.md) | Rust 模块依赖图（Mermaid）+ Flutter 对照（第 5.2 段） |
| [extension_guide.md](extension_guide.md) | 扩展指南：新平台 / 新方向 / 换编解码器 / QoS / 新传输层（第 5.2 段） |
| [performance_tuning.md](performance_tuning.md) | 性能调优指南（tokio / 内存 / 帧预算 / Timeline）（第 5.2 段） |
| [network_protocol.md](network_protocol.md) | 网络协议文档（mDNS / QUIC / TCP / 消息头 / 心跳 / 重连）（第 5.2 段） |
| [theme_system.md](theme_system.md) | 主题系统文档（M3E / 动态色 / 自定义 / 深色模式）（第 5.2 段） |
| [acceptance_report.md](acceptance_report.md) | 最终验收清单（25 项逐项结论，第 5.3 段） |
| [known_limitations.md](known_limitations.md) | 已知限制、已知问题、性能瓶颈（第 5.4 段） |
| [licenses.md](licenses.md) | 开源许可证汇总（全部与 Apache-2.0 兼容，第 5.4 段） |
| [performance_engineering.md](performance_engineering.md) | 性能工程全景（第 4.8 段产出） |
| [dependencies.md](dependencies.md) | 工具链版本锁定清单 |
| [acceptance_report_2.md](acceptance_report_2.md) / [acceptance_report_3.md](acceptance_report_3.md) | 第二/三段阶段验收报告（历史留存） |

### 发布说明

`.github/release-notes/`：Dev-2.0 / Dev-2.1 / Dev-3.0 / Dev-4.0 / Dev-5.0（本次）。

## 三、验收结论汇总

（明细见 [acceptance_report.md](acceptance_report.md)）

| 结论 | 数量 | 说明 |
| --- | --- | --- |
| 通过 | 16 | 其中 5 项由 CI 产物承载（三端编译、UI 编译类）；#5/#17 由 Dev-5.0 后补 loopback 实测升级为通过 |
| 未通过 | 5 | 全部为「需真机联调」项：实网发现/双向控制/实网重连/真机硬解/Timeline 复核；无代码阻塞 |
| 不适用 | 3 | scrcpy jar 未分发、局域网延迟与帧耗时的物理测量（无真机无法测） |

Rust 侧测试：**61 通过 / 0 失败 / 2 忽略**（组播 2 项因沙箱无组播网络忽略；含 `tests/segment5_loopback.rs` 4 项 QUIC/TCP 真实回环实测）；`cargo build --release` 0 error / 0 warning。验证中修复 `quic::accept` 误用 `open_bi` 导致 QUIC 数据面不通的缺陷。

## 四、待解决问题清单（按优先级）

**阻塞**
1. （无）——当前版本可编译、可离线演示、可发布；无阻塞级缺陷。

**高**
2. scrcpy-server.jar 自动分发（复现/规避见 [known_limitations.md](known_limitations.md) 问题 1）——完成前「桌面控 Android」开箱不可用。
3. QUIC 证书指纹经 mDNS TXT（`cert=`）发布并启用 `make_client_endpoint_strict` 严格校验——消除局域网伪造风险。
4. 真机联调批次：实网发现/建连/双向控制/重连/真机硬解（对应验收 #4/#5/#7/#8/#17/#18）。

**中**
5. FFI metrics 接口经 FRB 生成，接入浮层延迟/编解码耗时实测（消除 0 占位）。
6. 帧传递零拷贝/纹理共享（FRB `ZeroCopyBuffer` 或平台纹理），解除高分辨率 FFI 拷贝瓶颈。
7. 帧轮询改事件驱动（Rust 回调/stream），解除 10 fps 轮询上限。

**低**
8. macOS / iOS 平台接入（`platform/` stub 已预留）。
9. Linux libei（portal）输入注入路线启用（Wayland 原生支持）。
10. AppImage 打包稳定性提升（当前尽力而为产物）。

## 五、版本信息

- **版本号**：`5.0.0+7`（Flutter pubspec；预览通道，标签 `Dev-5.0`）
- **构建日期**：2026-10-18
- **构建环境**：CI（GitHub Actions，ubuntu runner）+ 沙箱验证（Linux x86_64、Rust 1.92.0）
- **工具链锁定**：Flutter 3.47.4 / Dart 3.13.3 / Rust 1.92.0 / FRB codegen 2.13.0 / cargo-ndk 4.1.2（见 [dependencies.md](dependencies.md)）

## 六、交接说明

1. **环境搭建**：按 [README.md](../README.md)「编译步骤」逐行执行——`rustup update stable` → `cargo install flutter_rust_bridge_codegen@2.13.0` → `flutter_rust_bridge_codegen generate` → `cargo build --release` → `flutter pub get` → 目标平台 `flutter build`。版本锁定清单见 [dependencies.md](dependencies.md)。
2. **代码结构**：先读 [module_dependencies.md](module_dependencies.md) 的模块依赖图与 Flutter 对照表；FFI 边界查 [ffi_reference.md](ffi_reference.md)；改传输/协议前读 [network_protocol.md](network_protocol.md)。
3. **关键约定**：
   - FFI 绑定文件（`rust/emote_core/src/frb_generated.rs`、`app/lib/src/rust/`）由代码生成，**勿手改**；改 `api/` 后必须重新 `flutter_rust_bridge_codegen generate`。
   - 能力缺失必须优雅降级（`Ok` no-op / `None` / `Ended`），禁止 panic——这是全库统一约定，输入注入与编解码均有探测降级。
   - `SessionManager` 等跨线程句柄必须保持 `Send + Sync`（有编译期测试守护）。
4. **测试基线**：`cargo test` 应保持全绿（当前 57 通过）；新增能力请参照 `tests/segment3_pipeline.rs` / `segment4_qos_hwdec.rs` 补合成源全链路测试。
5. **发布流程**：更新 `.github/release-notes/Dev-x.y.md` + `app/pubspec.yaml` 版本 → 打标签 `Dev-x.y` 推送 → CI 自动三端打包并创建 Release（`.github/workflows/release.yml`）。
6. **日常联系人**：见仓库 GitHub（Edgerd/Emote）Issue / PR 渠道。
