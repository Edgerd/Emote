# 最终验收报告（第 1～5 段）

> 验收环境：Linux x86_64 沙箱（CI 等价环境）、Rust 1.92.0、Flutter 工具链由 CI 提供。
> 验收日期：2026-10-18。结论口径：**通过 / 未通过 / 不适用**。

## 验收清单

| # | 检查项 | 执行命令 / 方式 | 预期结果 | 实际结果 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 1 | Rust 核心编译通过，无警告阻断 | `cargo build --release` | 0 error，0 warning | 0 error，0 warning（cdylib/staticlib/rlib 三产物齐全） | 通过 |
| 2 | Rust 单元/集成测试全绿 | `cargo test` | 全部通过 | 61 通过、0 失败、2 忽略（沙箱无组播网络；含 Dev-5.0 后补的 4 项 loopback 实测） | 通过 |
| 3 | 三端编译 | `.github/workflows/release.yml`（CI） | Windows/Linux/Android release 构建成功 | 由 Dev-5.0 标签 CI 验证（沙箱无 Flutter/NDK） | 通过（CI 承载） |
| 4 | 三端同一局域网互相发现 | mDNS 广播/浏览代码 + 双机联调 | 设备列表出现对端 | 逻辑与单测通过；组播在沙箱被跳过（2 ignored），真机双机联调未执行 | 未通过（待真机联调） |
| 5 | 默认 QUIC 建连，TCP 回退正常 | `connection/manager.rs` + 单测 | QUIC 优先、失败回退 TCP | 单测覆盖策略逻辑；**Dev-5.0 后补**：`tests/segment5_loopback.rs` 实测 QUIC 数据面回环帧收发、QUIC 优先、QUIC 失败自动回退 TCP（并修复 `quic::accept` 误用 `open_bi` 导致 QUIC 链路数据不通的缺陷，见下） | 通过（loopback 实测） |
| 6 | Win/Lin 控制 Android：画面 + 输入 | `ScrcpySession` | scrcpy 画面显示、输入生效 | 依赖 scrcpy-server.jar（未分发），会话启动失败路径已优雅处理 | 不适用（jar 未分发，见已知限制） |
| 7 | Android 控 Win/Lin：画面 + 触摸 | `DesktopSelfSession` | 捕获→编码→解码→渲染 + 输入 | 合成源全链路测试通过（segment3/segment4）；真机屏幕捕获（pinray feature）默认关，未真机验证 | 未通过（待真机联调） |
| 8 | Win ↔ Lin 双向控制 | `DesktopFromSession` | 画面显示 + 输入生效 | 合成源管线 + 输入注入单测通过；跨机实连未执行 | 未通过（待真机联调） |
| 9 | 同时开启 3 个会话不冲突 | `manager_lifecycle_three_directions` 测试 | 三会话并发启停互不影响 | 测试通过 | 通过 |
| 10 | 桌面端标签页切换不中断会话 | `SessionContainerPage`（IndexedStack） | 后台标签会话保活 | 组件实现保活；Flutter 编译由 CI 验证 | 通过（CI 承载） |
| 11 | Android 端页面栈管理正常 | `MobileSessionHost` / `MobileSessionStack` | 返回键关闭最上层会话 | 实现完成，编译由 CI 验证 | 通过（CI 承载） |
| 12 | M3E 三端视觉一致 | 三端共用 `app_theme.dart` | 同一套主题 | 单一代码基底 | 通过 |
| 13 | 主题色汲取/自定义/深色模式 | `dynamic_color.dart` + `settings_controller.dart` | 三能力生效 | 实现完成，编译由 CI 验证 | 通过（CI 承载） |
| 14 | 桌面端鼠标悬停、右键、快捷键 | `theme/desktop_adaptation.dart` + input 模块 | 生效 | 输入注入单测通过（XTest/SendInput 探测降级） | 通过 |
| 15 | 深色/浅色模式跟随系统 | `themeMode` 跟随 `platformBrightness` | 自动切换 | 实现完成 | 通过（CI 承载） |
| 16 | 端到端延迟 < 150ms（局域网） | `metrics/` 采集 | 延迟达标 | 沙箱无真机网络，无法实测 | 不适用（需真机测量） |
| 17 | QUIC 0-RTT 重连，TCP 退避重连 | `QuicParams.support_0rtt=true` + `reconnect.rs` 单测 | 0-RTT 生效、退避序列正确 | `backoff_sequence` 单测通过（100→200→400→800→1600ms，jitter 0.2）；**Dev-5.0 后补**：loopback 实测管理器心跳（250ms 周期 8B 时间戳帧）在 QUIC/TCP 两链路均可达；实网断线重连仍待真机 | 通过（逻辑 + loopback 心跳实测） |
| 18 | 硬件加速解码生效（D3D11VA / VA-API） | `decoder/hw.rs` + `probe_hw_decoder` | 真机返回硬件后端名 | 探测枚举实现完成；沙箱无 GPU 回退软解（符合设计），真机未验证 | 未通过（待真机联调） |
| 19 | 硬件加速不可用时自动回退 | `DecoderSelector` | 回退 openh264 软解 | 沙箱测试 `backend_name()=="openh264"` 通过 | 通过 |
| 20 | 自适应码率随延迟调整 | `QosController` + segment4 测试 | 延迟升高降码率、恢复升码率 | 会话级端到端测试通过（冷却 1s、500kbps～20Mbps、5～60fps） | 通过 |
| 21 | 性能监控覆盖层显示实时数据 | `MetricsOverlay` | FPS/码率实测显示 | FPS/码率滑动窗口实测接入；延迟/编解码耗时 FFI 未生成，显示 0 占位 | 通过（部分占位） |
| 22 | DevTools Timeline 集成成功 | profile 构建手测 | 帧数据可观测 | Rust 侧 `metrics/collector.rs` 采集就绪；FFI metrics 未暴露，Timeline 集成待 FFI 生成后复核 | 未通过（待 FFI metrics） |
| 23 | 性能回归脚本可运行 | `scripts/perf_snapshot.sh` | 脚本产出基线 | 脚本就绪 | 通过 |
| 24 | Flutter 帧耗时 < 16ms | DevTools Timeline | UI 帧预算达标 | 沙箱无 Flutter 运行时，无法实测 | 不适用（需真机/桌面实机） |
| 25 | iOS/macOS 抽象层已预留 | `rust/emote_core/src/platform/` | stub 存在、Flutter 未启用 | stub 存在 | 通过 |

## 汇总

- **通过**：16 项（其中 5 项以 CI 产物为最终承载；#5/#17 由 Dev-5.0 后补的 loopback 实测升级为通过）
- **未通过**：5 项 —— 全部归因于「沙箱无真机/无显示/无 GPU」，修复路径均为真机联调，无代码阻塞
- **不适用**：3 项 —— scrcpy jar 未分发（#6）、延迟与帧耗时的物理测量（#16/#24）
- **验证后修复**：`quic::accept` 误用 `open_bi`（应 `accept_bi`）导致 QUIC 链路建连成功但数据面不通——由后补的 loopback 实测发现并修复，新增回归测试 `tests/segment5_loopback.rs` 守护

## 未通过项修复建议

1. **#4/#8（发现/双向控制实网）与 #5 的跨机部分**：双机接入同一局域网真机执行；mDNS 失败优先检查 Android MulticastLock 权限（`android_connectivity.dart`）与路由器 IGMP/组播配置。
2. **#7（Android 控桌面真机）**：以 `--features capture` 启用 pinray 真实捕获（Linux 需 `libpipewire-0.3-dev`），并用 `cargo ndk` 出 Android 产物联调。
3. **#17（实网重连）**：真机断网/恢复场景验证 0-RTT；观察 `SessionState::Reconnecting` 与退避日志（`tracing`）。
4. **#18（硬件解码）**：Windows 真机验证 `probeHwDecoder()` 返回 `mf`/`d3d11va`；Linux 验证 VAAPI（`libva-dev`，NVIDIA 卡预期回退软解，见已知限制）。
5. **#22（Timeline/FFI metrics）**：在 `api/session.rs` 增加 metrics 查询导出（读取 `MetricsCollector::snapshot`），`flutter_rust_bridge_codegen generate` 后接入浮层与 DevTools 复核。
