# 已知限制清单

> 与代码同步基线：Dev-5.0。逐项给出：场景、影响、复现、规避。

## 一、当前不支持的场景

| 场景 | 说明 | 影响 | 规避方式 |
| --- | --- | --- | --- |
| macOS / iOS 平台 | `rust/emote_core/src/platform/` 仅抽象 stub，Flutter 无对应 Runner | 无法在 macOS/iOS 运行 | 使用 Windows / Linux / Android 三端 |
| 桌面控 Android（scrcpy 方向）开箱不可用 | `scrcpy-server.jar` 未自动分发，`push_server` 依赖本机已放置 jar | 该方向会话启动失败（优雅报错，不崩溃） | 手动下载 scrcpy-server v2.x jar，放置后设置 `SCRCPY_SERVER_PATH` 指向该文件 |
| Linux Wayland 输入注入 | XTest 依赖 X11；Wayland 会话下 `x11-dl` 加载或 XTest 扩展不可用，自动降级 `NullSink` | Linux Wayland 下无法注入键鼠 | 使用 X11 会话；或配置 uinput udev 规则（见下）；libei 路线需桌面 portal 支持（`reis` 依赖为预留未启用） |
| Linux uinput 权限 | uinput 设备节点 `/dev/uinput` 默认 root 才可写 | 非 root 注入失败（降级 `NullSink`） | 添加 udev 规则：`/etc/udev/rules.d/80-uinput.rules` 授予 `uinput` 组写权限后重新插拔内核模块 |
| NVIDIA 显卡上的 VAAPI | NVIDIA 私有驱动不提供 VA-API 后端 | `detect_hw_decoders()` 不返回 VAAPI，解码回退 openh264 软解 | 无需操作（自动回退）；需硬解时使用 NVIDIA NVENC/NVDEC 集成（未实现） |
| QUIC 被企业网络阻断 | 部分防火墙阻断 UDP/QUIC | QUIC 建连失败 | 自动回退 TCP（明文）；或联系网络管理员放行 UDP 5201 |
| 跨公网部署 | 设计为纯局域网信任模型 | 公网暴露将面临未认证连接 | 仅在可信局域网使用 |
| 性能浮层延迟/编解码耗时 | FFI metrics 查询接口未生成（`metrics/collector.rs` 数据已就绪） | 浮层中 `latency/enc/dec` 显示 0 占位 | FPS/码率为实测值可正常显示；待 `api/session.rs` 暴露 snapshot 接口并重新 `frb generate` |

## 二、已知问题

### 1. scrcpy-server.jar 缺失时 ScrcpySession 启动失败

- **描述**：`SessionDirection::Scrcpy` 会话 `start()` 时 `push_server` 找不到 jar 报错。
- **复现**：「更多 → 远程会话」选 Scrcpy 方向启动，本机无 `SCRCPY_SERVER_PATH` 指向的 jar。
- **影响范围**：仅桌面控 Android 方向；其余方向不受影响。
- **规避**：手动放置 jar（版本需与 scrcpy-protocol 0.1.1 兼容的 server v2.x）。

### 2. mDNS 发现在无组播网络中静默无结果

- **描述**：`mdns-sd` 在禁用组播的网络（部分 AP 隔离 Wi-Fi、CI 容器）收不到对端。
- **复现**：两台设备接入开启 AP 隔离的路由器 → 设备列表为空。
- **影响范围**：设备发现；`cargo test` 中 2 项组播测试因此标记 ignore。
- **规避**：关闭路由器 AP 隔离/客户端隔离；确认 Android 已授予「本地网络」权限并持有 MulticastLock。

### 3. QUIC 通道无对端身份校验（局域网信任模型）

- **描述**：客户端默认跳过对端证书校验；同网段攻击者可伪造服务端。TCP 通道为明文。
- **复现**：同网段伪造 `_emote._udp.local.` 服务即可被连接。
- **影响范围**：数据机密性与完整性（画面/输入流）。
- **规避**：仅在可信局域网使用；严格校验入口 `make_client_endpoint_strict`（证书 CN 绑定设备 ID）已实现，待 mDNS TXT `cert=` 指纹发布后启用。

### 4. FFI 帧拷贝带来内存/延迟开销

- **描述**：解码帧 RGBA8 经 FFI 每帧拷贝一次（`Uint8List.fromList(frame.data)`）。
- **复现**：提升会话分辨率（>720p）后轮询路径 CPU 占用与帧延迟上升。
- **影响范围**：高分辨率会话性能；当前 320×240 演示分辨率无感。
- **规避**：保持演示分辨率；根治需 FRB 零拷贝或纹理共享（4.3 段规划项）。

## 三、性能瓶颈

| 瓶颈点 | 具体指标 | 触发条件 |
| --- | --- | --- |
| 帧轮询上限 | 帧率上限 ≈ 10 fps | `RemoteSessionService` 100 ms 轮询间隔（当前设计使然）；事件驱动改造前无法突破 |
| FFI 拷贝 | 每帧双份内存 + 一次拷贝 | 所有分辨率；分辨率越高开销越大（见已知问题 4） |
| 软解码 CPU | openh264 解码单核占用随分辨率线性上升 | 无硬件解码可用（沙箱/NVIDIA/Android target）时 |
| 多会话保活 | 后台标签持续拉帧消耗 Flutter 帧预算 | 桌面/移动同时保活 ≥3 个会话 |
| Android target 无编解码 | openh264 代码不链接 Android target | Android 作为编码/解码端依赖对端或后续接入硬件编解码 |

## 四、约束与依赖相关限制

- **openh264 二进制分发**：crate 为 BSD-2-Clause，但其封装的 Cisco OpenH264 预编译二进制分发需向 Cisco 申请免费商用许可；从源码构建则无需。当前 CI 从源码构建，不受影响。
- **pinray 屏幕捕获默认关闭**：`capture` feature 默认关（保证 CI 无显示环境可构建）；Linux 构建启用需 `libpipewire-0.3-dev` 与 clang。
- **纯局域网字体下载**：唯一公网访问为首次启动下载 HarmonyOS Sans 字体（华为官方域、SHA-256 校验）；「纯局域网模式」可禁用，禁用后回退系统字体。
