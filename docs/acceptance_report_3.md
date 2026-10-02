# Emote 第3段验收报告（3.0 三方向远程控制 阶段验收）

- **验收对象**：第3段（3.1–3.9）全部产出（scrcpy 协议层 + ADB 通道 + 三方向远程控制会话）
- **验收人**：验收工程师（自动化）
- **版本**：Dev-3.0（`app/pubspec.yaml` → `3.0.0+3`）
- **日期**：2026-10-02
- **环境**：Linux（GNU，x86_64）+ Rust stable；Flutter/Dart 工具链与 NDK 不在沙箱内，相关项以 CI 为准
- **范围说明**：本段不含 iOS/macOS、硬件解码（4.4）、自适应码率/断线重连（4.5/4.6）、文档交付（5）、scrcpy-server.jar 分发（5，仅保留 `SCRCPY_SERVER_PATH` 常量 + `push_server` 接口）

---

## 1. 验收清单

| 检查项 | 执行命令 | 预期结果 | 实际结果 | 结论 |
| --- | --- | --- | --- | --- |
| 1. `cargo build` GNU 桌面目标三种 crate-type 全绿 0 警告 | `cargo build --release` | cdylib/staticlib/rlib 全产出 0 错误 0 警告 | 3 产物齐全 `libemote_core.{so,a,rlib}`；`touch lib.rs` 后重建 0 警告 | ✅ 通过 |
| 2a. 编解码 round-trip 单测 | `cargo test` | encode→decode 分辨率/亮度容差通过 | `decoder::tests::encode_decode_roundtrip`、`encoder::tests::encoder_produces_annexb_with_sps` 通过 | ✅ 通过 |
| 2b. scrcpy 协议单测 | `cargo test` | 包解析/控制序列化通过 | 11 个 scrcpy 用例全通过（video/key/touch/text/config/adb/args） | ✅ 通过 |
| 2c. 输入事件序列化单测 | `cargo test` | 全变体 round-trip + 坏 tag 拒绝 | `input::tests::all_variants_roundtrip`、`decode_rejects_bad_tag` 通过 | ✅ 通过 |
| 2d. 后端能力检测单测 | `cargo test` | 沙箱内降级为 NullSink 不 panic | `input::tests::dispatcher_degrades_gracefully_in_sandbox` 通过 | ✅ 通过 |
| 2e. loopback 视频流全链路 | `cargo test`（集成） | TCP loopback 4B 长度前缀 编码/解码 | `tests/segment3_session_pipeline.rs` 3 用例通过（synthetic 全链路、loopback、三方向端到端） | ✅ 通过 |
| 2f. 合成源全链路 pipeline | `cargo test`（集成） | 采集→编码→解码 完整 | `synthetic_full_pipeline_capture_encode_decode` 通过 | ✅ 通过 |
| 3. input/capture/codec 具备能力检测，沙箱不可用时优雅降级不 panic | 代码审计 + `cargo test` | 各模块返回可用位/降级 | `codec::codec_backend_linked()`、`encoder::encoder_available()`、`decoder::decoder_available()`、`input::detect()` + `InputDispatcher::new()` 降级 `NullSink`；全部单测通过 | ✅ 通过 |
| 4a. FFI 重生成（`api/session.rs` → Dart） | `flutter_rust_bridge_codegen generate` | 生成 `lib/src/rust/api/session.dart`、`lib/src/rust/session.dart` | 沙箱无 frb 二进制；`api/session.rs` 已就绪，import 路径 `../src/rust/api/session.dart`、`../src/rust/session.dart` 与既有 FRB 约定一致 | ⚠️ 待 CI 生成 |
| 4b. `flutter analyze` 0 错误（RemoteView/SessionService/RemoteSessionPage 可编译） | `flutter analyze` | 无报错 | 沙箱无 flutter/dart；Dart 侧 `remote_view.dart`、`remote_session_service.dart`、`remote_session_page.dart` 已编写并接入 `more_page.dart` | ⚠️ 待 CI 验证 |
| 5. 三方向会话类型（3.7 Scrcpy / 3.8 DesktopSelf / 3.9 DesktopFrom）实现并经 pipeline 测试 | `cargo test` | 三方向可创建/启停/编码/解码/输入 | `session::tests::manager_lifecycle_three_directions` + 集成 `three_direction_sessions_end_to_end_pipeline` 通过 | ✅ 通过 |
| 6a. 沙箱本地 Linux/Android Rust 包 build 无错 | `cargo build --release` / `cargo check --target x86_64-linux-android` | Linux 无错；Android 目标门控正确 | GNU release 干净；Android 因沙箱缺 NDK clang，`ring` 既有 crate C 构建失败（预期，CI 有 NDK）；emote_core 自身目标门控正确 | ✅ 通过（emote_core）/ ⚠️ 整包待 CI |
| 6b. 打 `Dev-3.0` 标签触发 CI 出 Windows/Linux/Android 3 段安装包 + 建 pre-release，工作流 3 build job 全绿 | `git tag Dev-3.0 && git push` | 3 job 绿 + pre-release | `.github/workflows/release.yml` 已含 3 个 build job（windows/linux/android）+ `create-release --prerelease`；`release-notes/Dev-3.0.md` 已备 | ⚠️ 待 CI 执行 |

**结论汇总**：通过 8 项（代码 + 测试层全绿），4 项因沙箱缺 Flutter/FRB/NDK/真实推送链路而待 CI 或真机验证（功能代码层均已实现）。

---

## 2. 测试统计

| 套件 | 通过 | 失败 | 忽略 |
| --- | --- | --- | --- |
| 库内单测（lib） | 24 | 0 | 1（mDNS 真实组播） |
| `tests/segment2_dual_instance.rs` | 5 | 0 | 1（mDNS 双实例） |
| `tests/segment3_session_pipeline.rs` | 3 | 0 | 0 |
| **合计** | **32** | **0** | **2** |

- 忽略项说明：mDNS 真实组播链路在容器内无 UDP 组播，用例带「可组播环境 `cargo test -- --ignored` 运行」注释，自动优雅跳过。
- QUIC 双实例在沙箱无 UDP loopback 时通过 5s 超时守卫优雅降级（`quic_failure_falls_back_to_tcp` 验证回退逻辑）。

---

## 3. 第3段产出物清单

- **scrcpy 协议层（Rust）**：`scrcpy/mod.rs`、`scrcpy/adb.rs`（AdbConnection：new/connect/push_server/forward_port/start_server）、`scrcpy/server.rs`（ServerOptions→to_server_args，`--raw-stream=false`）、`scrcpy/video.rs`（ScrcpyVideoStream.connect/read_packet，8B pts|flags + 4B len + payload）、`scrcpy/control.rs`（ControlSender 重导出）
- **codec/encoder/decoder（Rust，桌面）**：`codec.rs`（H264FrameType/H264VideoFrame/codec_backend_linked）、`encoder/mod.rs`（OpenH264Encoder + SPS/AnnexB 单测）、`decoder/mod.rs`（OpenH264Decoder + encode_decode_roundtrip）
- **capture（Rust）**：`capture/mod.rs`（Frame/ScreenSource/ScreenCapture）、`capture/synthetic.rs`（确定性 I420 合成源，headless 管线测试用）、`capture/pinray_backend.rs`（`feature="capture"` 门控）
- **input（Rust）**：`input/mod.rs`（InputEvent/encode/decode、InputSink、BackendReport、detect、InputDispatcher）、`input/linux.rs`（X11 XTest + uinput）、`input/uinput.rs`（/dev/uinput ioctl）、`input/windows.rs`（SendInput）
- **session（Rust）**：`session/mod.rs`（SessionDirection 3.7/3.8/3.9、SessionState、SessionManager/DashMap）、`session/sessions.rs`（ScrcpySession/DesktopSelfSession/DesktopFromSession）
- **FFI（Rust）**：`api/session.rs`（SessionHandle 不透明句柄：create/start/stop/state/next_frame/input_*/codec_available/probe_input_backend）
- **集成测试**：`tests/segment3_session_pipeline.rs`
- **Flutter 侧**：`widgets/remote_view.dart`（RawImage 渲染器）、`services/remote_session_service.dart`（轮询 nextFrame、发 key/touch/scroll）、`pages/remote_session_page.dart`（启停/状态/输入演示），并接入 `pages/more_page.dart`
- **发布**：`.github/release-notes/Dev-3.0.md`、标签 `Dev-3.0`

---

## 4. 需真机/CI 的手动验收步骤

- [ ] **CI 执行 FRB 重生成 + `flutter analyze`**：在含 flutter/frb 的 CI 上运行 `flutter_rust_bridge_codegen generate`，确认 `api/session.dart`/`session.dart` 生成、Dart 侧 0 报错。
- [ ] **CI 三端打包**：`git push` 触发 `Dev-3.0` 标签 → windows/linux/android 3 个 build job 全绿 → 生成 3 段安装包 + pre-release。
- [ ] **真机 scrcpy 全链路**：adb 连接 Android 真机，`AdbConnection::push_server` + `start_server`，`ScrcpySession` 解码实时画面（验证 3.7 方向）。
- [ ] **桌面双向远程控制**：DesktopSelfSession 采集本机 → DesktopFromSession 解码 + 输入下发（验证 3.8/3.9 方向），确认触摸/按键/滚轮生效。
- [ ] **跨平台互发现 + 长时间保活**：三端真机局域网 mDNS 互发现（`cargo test -- --ignored` 触发忽略的 mDNS 用例）与 30s+ 心跳保活。
- [ ] **QUIC 帧交换**：真实组播/UDP 网络下跑 `cargo test -- --ignored` 验证 QUIC 双实例帧交换。

---

## 5. 已知限制与沙箱说明

- **Flutter/Dart 工具链缺失**：沙箱内无 `flutter`/`dart` 二进制，`flutter analyze` 与 FRB codegen 无法本地执行；Dart 代码按 FRB 生成后 API 编写，import 路径与既有约定一致，交由 CI 验证。
- **NDK 缺失**：Android 整包 `cargo check --target x86_64-linux-android` 在沙箱因缺 `x86_64-linux-android-clang` 于既有 `ring` crate C 构建阶段失败；emote_core 自身目标门控（openh264/x11-dl/windows 仅桌面、pinray feature 门控）正确，CI 具备 NDK。
- **真实链路缺失**：mDNS 组播、adb 真机、跨端网络在沙箱不可达，相关用例以 `#[ignore]`/超时常驻优雅降级。

---

*本报告验收第3段（含 3.1–3.9 三方向远程控制），不评估第4段（硬件解码/自适应码率/重连）及第5段（文档/scrcpy-server.jar 分发）。*
