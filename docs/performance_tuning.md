# 性能调优指南

> 与代码同步基线：Dev-5.0。性能工程全景见 [performance_engineering.md](performance_engineering.md)。

## Tokio 运行时调优

`ConnectionHandle` 内部惰性启动 tokio 多线程运行时（`connection/manager.rs`）：

- worker 线程数默认 = CPU 核数。局域网双端场景（QUIC + TCP + 会话管线）负载轻，无需调整；如需限制，在 `ConnectionManager::new` 构建运行时处显式 `Builder::worker_threads(n)`。
- 避免 worker 线程内执行阻塞操作：FFI 层（`api/*.rs`）所有方法均为同步接口，内部已将异步操作包在运行时中；新增代码勿在 async 上下文里调用 `std::fs` / 长忙等。
- 心跳与超时常量（`protocol/message.rs`）：`HEARTBEAT_INTERVAL_SECS = 3`、`HEARTBEAT_TIMEOUT_SECS = 10`；QUIC `idle_timeout_secs = 15` 大于心跳间隔以保证保活。调整心跳间隔时必须同步保证 `idle_timeout > heartbeat_interval`。

## 内存分配优化

- 发布配置（`rust/emote_core/Cargo.toml` `[profile.release]`）：`lto = "thin"`、`codegen-units = 1`、`panic = "abort"`、`strip = true`，产物体积与运行性能已按可复现构建调优。
- 帧数据生命周期：`VideoFrame.data`（RGBA8）每帧在 Rust 侧分配并经 FFI 拷贝到 Dart（`Uint8List.fromList(frame.data)`）。当前 320×240 演示分辨率下单帧 ≤ 300 KB；提升分辨率时优先做零拷贝（FRB `ZeroCopyBuffer` 或纹理共享，见 4.3 段规划），避免每帧双份内存。
- 多会话内存：`SessionManager` 用 `DashMap` 按会话持有解码缓存；关闭会话（`stop`）即释放，长驻多会话场景监控会话数（`SessionHandle` 无上限，UI 层由标签/栈数量约束）。

## Flutter 帧预算管理

- 渲染管线：解码帧经 100 ms 轮询（`RemoteSessionService._pullFrame`）→ `ChangeNotifier` → `RemoteView`（`RawImage`）。轮询间隔是帧率上限的瓶颈：目标 30 fps 需将轮询改为事件驱动（Rust 回调或 stream），这是延迟优化的第一优先级。
- UI 刷新粒度：`_pullFrame` 有帧才 `notifyListeners()`，无帧不触发重建；避免在 `build` 中做 RGBA 转换等重活（转换已在 Rust 完成）。
- 多会话保活：桌面 `IndexedStack`、移动 `IndexedStack` 均保活全部会话，后台会话持续拉帧消耗预算；后台标签可按需暂停轮询（在 `_RemoteSessionPageState` 中按可见性控制 `_svc` 轮询）。

## DevTools Timeline 使用

1. 运行 debug/profile 构建：`cd app && flutter run --profile`。
2. 打开 DevTools → Timeline（Performance 视图），勾选 Raster / UI 两个线程泳道。
3. 关注指标：
   - **UI 线程帧耗时 < 16 ms**（60 fps 预算）：超标的常见原因是 `RemoteView` 全量重建或主题级 `setState` 扩散。
   - **Raster 线程**：`RawImage` 大图上传耗时；分辨率提升后此处先到瓶颈。
   - FPS 实测值可与浮层读数（`metrics_overlay.dart`）交叉验证。
4. Rust 侧编解码耗时经 `metrics/collector.rs`（`record_encode` / `record_decode` / `record_ffi`）采集；FFI metrics 暴露接口生成后（见已知限制）可在 Timeline 中与 Dart 帧时间对齐分析。
5. 采样标记勿过度添加：Timeline 内自定义 Timeline 事件在高频路径（每帧）上会放大开销，按需采样。

## 性能回归脚本

```sh
# Linux / macOS：采集构建产物体积与启动基线
sh scripts/perf_snapshot.sh

# Windows：
powershell -File scripts/perf_snapshot.ps1
```

产物写入仓库根目录 `perf_snapshot.json`（不入库），用于跨版本对比。
