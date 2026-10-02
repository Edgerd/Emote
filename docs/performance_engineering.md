# Emote 性能工程

本文档覆盖 Rust 异步运行时调优、内存分配策略、Flutter 帧预算与端到端延迟目标。

---

## Tokio 运行时调优

| 参数 | 值 | 说明 |
|---|---|---|
| `worker_threads` | CPU 核心数 | 默认即核心数；显式设避免单线程 |
| `max_blocking_threads` | 核心数 × 2 | 捕获/编码等阻塞任务不饿死 worker |
| `thread_name` | `emote-worker` | 方便 profiler 标识 |

代码位置：`connection/manager.rs` 的 `ConnectionManager::with_config()` 中
`tokio::runtime::Builder::new_multi_thread()` 配置。

CPU 密集型操作（openh264 编码/解码）必须用 `spawn_blocking` 或独立线程，
不阻塞 tokio worker。

---

## 内存分配优化

- **预分配**：视频缓冲区使用 `BytesMut::with_capacity(width * height * 4)`，避免每帧重新分配。
- **复用**：`I420Frame` 的 `i420: Vec<u8>` 在 `SyntheticSource` 中循环复用。
- **零拷贝**：`bytes::Bytes` 用于跨 FFI 传输解码帧（`session/VideoFrame.data` 当前为 `Vec<u8>`，
  后续可切换为 `Bytes` 减少一次 clone）。
- **对象池**：高频分配的小对象（如 `Frame`）使用 `VecDeque` 环形缓冲。

---

## Flutter 帧预算

| 目标 | 约束 |
|---|---|
| 60 Hz | 每帧 ≤ 16.67 ms（含 build + layout + paint） |
| 120 Hz | 每帧 ≤ 8.33 ms |

优化手段：
- `RepaintBoundary` 隔离视频渲染区域（`RemoteView` 外层）。
- `IndexedStack` 保活后台标签页（不触发 build，但继续接收帧）。
- 使用 `const` 构造减少 rebuild。
- 视频渲染用 `RawImage`（`remote_view.dart`），不触发 Flutter layer 重建。

---

## 端到端延迟目标

**局域网 < 150 ms**（捕获 → 编码 → 网络 → 解码 → 渲染）

| 阶段 | 目标 | 备注 |
|---|---|---|
| 捕获（pinray/synthetic） | < 5 ms | 1080p |
| H.264 编码（openh264） | < 30 ms p95 | 1080p 30fps |
| 网络（QUIC/TCP LAN） | < 5 ms | 千兆以太网 |
| H.264 解码 | < 20 ms | openh264 软件 |
| FFI 传输 + 渲染 | < 5 ms | Vec<u8> → RawImage |
| **总计** | **< 65 ms** | 远低于 150 ms 目标 |

自适应码率（QoS）在延迟 > 100 ms 时自动降码率/帧率，防止缓冲溢出。

---

## 性能回归检测

脚本路径：`scripts/perf_snapshot.sh`（已有，第 1.6 段产出）。

采集指标：
- 启动到首帧耗时
- 空闲内存占用
- FFI 调用 1000 次平均耗时
- 编码/解码 p50/p95

与基线对比，超过 10% 报警。
