# Emote 5.0.0

> **发布通道**：Pre-release（预览版） · **标签**：`Dev-5.0`
> **建议安装**：尝鲜预览版本，本版为第 5 段（最终整理与验收）文档交付版；生产环境请选用正式版。

---

## 平台支持

> 使用前请先阅读下方「使用说明」。

| 平台 | 包 | 说明 |
| --- | --- | --- |
| Windows x86_64 | `emote-windows-x86_64.zip` | 解压后运行 `emote.exe` |
| Linux x86_64 | `emote-linux-x86_64.tar.gz` | 解压后运行 `./emote`；另有 `emote-linux-x86_64.AppImage`（尽力而为） |
| Android (APK) | `app-release.apk` | 安装后需授予「本地网络」权限 |

---

## 更新明细

### 📚 文档交付（第 5 段核心内容）
- **README 重写（5.1）**：项目简介、功能特性、Mermaid 架构图、技术栈、逐行可复制编译步骤、运行步骤、目录结构、已知限制、许可证。
- **开发者文档六件套（5.2）**：
  - `docs/ffi_reference.md`：FFI 接口清单（simple / discovery / connection / session 四模块，与代码一一对应）。
  - `docs/module_dependencies.md`：Rust 模块依赖图（Mermaid）+ Flutter 侧对照表。
  - `docs/extension_guide.md`：扩展指南（新平台 / 新远控方向 / 替换编解码后端 / 调整 QoS / 新传输层）。
  - `docs/performance_tuning.md`：性能调优指南（tokio / 内存 / Flutter 帧预算 / DevTools Timeline）。
  - `docs/network_protocol.md`：网络协议文档（mDNS / QUIC 0-RTT / TCP 回退 / 消息头 / 心跳 / 重连退避）。
  - `docs/theme_system.md`：主题系统文档（M3E / 动态颜色 / 自定义主题色 / 深色模式）。
- **最终验收报告（5.3）**：`docs/acceptance_report.md`，25 项逐项结论（通过 14 / 未通过 7（均为待真机联调）/ 不适用 3）。
- **已知限制与许可证（5.4）**：`docs/known_limitations.md`（不支持场景、已知问题、性能瓶颈）+ `docs/licenses.md`（全部依赖许可证汇总，均与 Apache-2.0 兼容）。
- **最终交付报告（5.6）**：`docs/final_delivery_report.md`（交付物清单、验收汇总、按优先级排序的待办、交接说明）。

### 🔧 修复
- README「未来规划」与实际状态对齐（Dev-4.0 已交付项移入已实现清单）。

### 📋 其它
- 应用版本号提升至 `5.0.0+7`（预览版）。
- Rust 测试基线：57 通过 / 0 失败 / 2 忽略；`cargo build --release` 0 警告。

---

## 已知问题
- scrcpy-server.jar 未自动分发，「桌面控 Android」方向开箱不可用（规避方式见 [docs/known_limitations.md](https://github.com/Edgerd/Emote/blob/main/docs/known_limitations.md)）。
- QUIC 为局域网信任模型（跳过对端证书校验），TCP 为明文；严格校验代码已就绪待启用。
- 性能浮层延迟/编解码耗时为 0 占位（FFI metrics 未生成）；FPS/码率已实测。
- 硬件解码、实网发现/建连/双向控制需真机联调（详见验收报告未通过项）。

---

## 下一步计划

- [ ] scrcpy-server.jar 自动分发
- [ ] QUIC `cert=` 指纹经 mDNS TXT 发布并启用严格校验
- [ ] FFI metrics 接口生成接入浮层
- [ ] 真机联调批次（实网五项 + 硬解两项）

---

## 使用说明

1. 三端设备连接**同一局域网**。
2. 启动 Emote，授予必要权限（Android 需「本地网络 / 组播」权限）。
3. 首页设备列表自动发现对端并建立连接；「更多」页进入远程会话 / 多会话管理。
4. 开发者文档入口：仓库 `docs/` 目录（FFI、协议、扩展、调优、限制、许可证、交付报告）。

> 仅面向**纯局域网**使用，请勿跨公网部署。

## 下载

见本 Release 页面下方 **Assets**。
