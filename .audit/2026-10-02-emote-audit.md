# Emote 每日审计报告 2026-10-02

## 一、审计范围

| 项 | 值 |
| --- | --- |
| 仓库 | /workspace（Emote，纯局域网跨平台远程控制） |
| 分支 | 审计时 HEAD 在 `trae/agent-YXxEpS`（较 main/origin/main 领先 `32fb4ab`；浅克隆 / grafted 基底 `b46a02b`；本地无任何 tag） |
| 工作树 | clean（报告文件已随 `32fb4ab` 入库成为受跟踪文件） |
| 时间窗 | 2026-10-01 02:00 ～ 2026-10-02 02:00（Asia/Shanghai，24h） |
| 24h 提交数 | 2：① `b46a02b` "feat: 系统工程修复与交付发布"（Edgerd，2026-10-01 11:41 UTC；整库批量导入，153 文件全新增，+22808 行）；② `32fb4ab` "feat: Emote 每日自动化审计代理"（Edgerd + Co-authored-by: traeagent，2026-10-01 16:10 UTC；仅新增本审计日报 `.audit/2026-10-02-emote-audit.md`，146 行） |
| 非安全审计提交数 | 2（`b46a02b`、`32fb4ab`；后者标题/正文不含 `[security-audit]` 后缀、无关联 tag，按规则 8 归类为非安全审计提交并纳入审计） |
| 安全审计提交数 | 0 |
| 安全审计后缀 | `[security-audit]`（默认）；提交消息与本地 tag 均不含该后缀（本地无 tag） |
| 安全审计是否跳过 | 否 —— 存在非安全审计提交，正常执行 |
| 变更文件 | `b46a02b`：全库（该提交即整仓导入）：rust/emote_core（discovery/connection/transport/protocol/api/metrics 等）、app/lib（services/pages/theme/src/rust FFI 绑定）、scripts/、.github/、docs/、README；`32fb4ab`：仅 `.audit/2026-10-02-emote-audit.md`（审计日报文档，无代码/逻辑变更） |
| 测试命令 | `cargo test -p emote_core`、`cargo build --release`、`flutter analyze`、`flutter test` |
| 自动修复 | AUTO_FIX=false（任务未显式置 true）→ 仅输出发现与建议，不改仓库 |
| 是否提交 | 本周期不新增提交（AUTO_FIX=false，未应用修复）；说明：初版报告后，自动化流程已将报告文件单独提交为 `32fb4ab`（"feat: Emote 每日自动化审计代理"，不含 `[security-audit]` 后缀），本报告随后并入审计范围复查 |
| Release 版本号 | 2.3.1（app/pubspec.yaml `version: 2.3.1+5`，去 build 号） |
| Release 提交与 tag | 本地浅克隆无 tag；`git describe --tags` 不可用；release notes 目录最末条目为 v2.3.1-hotfix |
| 更新日志路径 | .github/release-notes/（沿用现有约定） |
| 版本漂移备注 | **存在漂移**：README（Dev-2.0 章节）自称"当前最新开发版本"，但 pubspec 为 2.3.1+5 且 release-notes 已至 v2.3.1-hotfix；浅克隆无 tag 无法交叉核对远端 tag。docs/acceptance_report_2.md 仍标注 Dev-2.0（2.0.0+2），与 2.3.1 基线不一致。 |
| 验证执行限制 | 沙箱无 flutter 工具链 → `flutter analyze` / `flutter test` 未执行；cargo 1.92.0 可用但依赖无缓存且默认规则禁止访问公网/安装依赖 → `cargo test` / `cargo build --release` 未执行。本周期发现均基于完整执行路径的代码审计。 |

## 二、执行摘要

- 正确性关键缺陷数：**3**（C-1 高、C-2 高、C-3 中；另有 C-4 仓库卫生中）
- 安全已确认漏洞数：**2**（S-1 高、S-2 中；S-3 为加固项不计入已确认）
- 测试缺口数：**4**（P0×3、P1×1，含验收报告遗留项 2 个）
- 总体风险：**高**（核心"发现→连接"链路端到端不可用 + 无认证可被同网攻击者劫持）
- 安全审计状态：已执行（针对非安全审计提交 b46a02b 与 32fb4ab）
- 提交 `32fb4ab`（审计报告文档入库）复查结果：纯 Markdown 文档新增，无代码/逻辑/测试变更 → **无关键缺陷、无新增攻击面、无有意义测试缺口**；报告正文已核：不含密钥/令牌/PII/剪贴板或文件内容（仅路径与行为描述），不构成新的敏感数据泄露
- 建议优先处理：C-1（服务端监听缺失/端口虚标）与 C-2（断连后无法重连 + 连接异常未处理）；安全侧 S-1（无配对/认证）需在输入注入段（第 3 段）落地前完成
- Release 版本号：2.3.1；提交后缀：无（本周期未提交）

## 三、提交后正确性检查

已确认关键缺陷（提交 b46a02b）：

> 提交 `32fb4ab` 复查：仅新增审计日报文档，无代码/逻辑/资源/并发变更，**未引入新的正确性缺陷**。

### C-1（严重度：高｜核心功能退化）发现设备公布的端口无任何监听方，端到端连接必然失败
- **位置**：`app/lib/services/discovery_service.dart` L24-25（`kDefaultQuicPort=5201`/`kDefaultTcpPort=5202`，注释自述"本 MVP 暂无真正的服务端监听，仅作发现信息公布"）；`rust/emote_core/src/transport/quic.rs::make_server_endpoint`、`transport/tcp.rs::bind/accept` 定义后**全仓无任何调用方**；`rust/emote_core/src/session/mod.rs` 为占位（"后续分段实现"）。
- **触发条件**：任意两台设备同网运行 → A 发现 B（B 广播 5201/5202）→ A 点击"连接"。
- **代码路径**：`discovery_service.start()` 广播固定端口 → 对端 `browser::build_device` 解析出 `quic_port/tcp_port` → `ConnectionManager::connect_to_device` → `try_quic`（4s 超时，端口无人监听 → 超时）→ `try_tcp`（连接被拒）→ 抛 `anyhow!("QUIC 与 TCP 均连接失败")`。
- **影响**：产品核心（远程控制链路）100% 失败；每点击一次连接浪费约 4~8s 并得到无提示的异常（见 C-2a）。
- **置信度**：高（静态确认：全仓 grep 无任何 server 监听调用；session 为占位骨架，属已知未实现项，但 discovery 已实现且主动虚标能力，属集成缺陷）。
- **最小修复建议**：短期——discovery 仅在确有监听时公布端口（或公布 0 并由 UI 隐藏端口 chip），避免虚标；中期——实现 session 段服务端：`make_server_endpoint(quic_port)` + `tcp::bind(tcp_port)` 并与 `DiscoveryService.start` 使用同一端口源，监听成功后再 `start_broadcast`。
- **测试建议**：本地 127.0.0.1 起 `make_server_endpoint`/`tcp::bind` + `connect()` 的端到端集成用例（同时补 C-2 回归）。

### C-2（严重度：高｜未处理异常 + 断连后无法重连）
- **位置 a**：`app/lib/pages/device_list_page.dart` L337-348（"连接"按钮 `onPressed` 为 async 闭包，`await connectionService.connect(device)` 无 try/catch，失败时产生**未处理异步异常**、不跳转状态页、无任何 UI 反馈）；`app/lib/pages/connection_status_page.dart` L36-38（`_connections.connect(widget.device)` 未 await 无捕获）、L233（"连接 / 重连"按钮同样未捕获）。
- **位置 b**：`rust/emote_core/src/connection/manager.rs` L81-94 `connect_to_device`：`if self.connections.contains_key(&dev.id) { return Ok(self.get_connection_state(&dev.id)); }` —— 连接表条目**只在显式 `disconnect()` 时移除**；对端断开/心跳超时后 handler 置 `Disconnected` 但条目仍在，此后所有 connect 调用直接短路返回 `Disconnected`。`ConnectionState::Reconnecting` 全仓无使用方。
- **触发条件**：(a) 当前任何一次连接失败（叠加 C-1 即 100%）→ 控制台 unhandled exception；(b) 链路曾建立后对端重启/断网 → 心跳 10s 超时判定断线 → 用户点"连接 / 重连" → 永远停留在未连接，必须手动"断开"一次才能再连。
- **代码路径**：`handler::run` break（`Disconnected`）→ 条目滞留 DashMap → `connect_to_device` `contains_key` 短路 → `ConnectionService.connect` 返回 `disconnected` → UI 无任何反应。
- **影响**：断线后重连功能实际不存在；连接失败路径无用户可见错误（远程桌面类产品属严重功能退化）。
- **置信度**：高。
- **最小修复建议**：`connect_to_device` 中若条目存在且状态为 `Disconnected`/`Error`，先 `connections.remove` 再重连（或将 `Reconnecting` 状态真正接入）；Dart 侧三处 `connect` 调用统一包 try/catch，失败时进入/保留状态页并展示错误（可复用 `ConnectionState.error` 渲染），不再产生未处理异常。
- **测试建议**：`ConnectionManager::with_config`（短心跳/超时）+ 本地 TCP 服务端（`tcp::bind/accept`）：建连→杀服务端→断言状态转 `Disconnected`→再调 `connect_to_device` 断言可重连（C-2b 回归用例）；`send_message` 在 handler 退出后应报错而非静默成功。

### C-3（严重度：中｜设备列表脏数据/幽灵设备）
- **位置**：`rust/emote_core/src/discovery/browser.rs` L115-117（`ServiceRemoved` 被显式忽略，"按保留记录处理"）+ 全仓无 TTL/淘汰路径（`build_device` 恒置 `online: true`）；`app/lib/services/discovery_service.dart` L178-189 `generateDeviceId`：**每次启动新生成且不持久化**（协议注释声称"UUID v4 首次启动生成并持久化"，实际实现为 `emo-<毫秒时间戳hex>-<微秒派生伪随机 6hex>`，非 UUID、非密码学随机）。
- **触发条件**：任一对端应用重启一次（或用户换机名/重启）。
- **代码路径**：对端重启 → 旧 mDNS 服务失效但本端 `ServiceRemoved` 被忽略 → 旧条目（同显示名、旧端口）永久滞留设备列表；且本端新 id ≠ 旧 id → `isSelfDevice` 自过滤失效，**自己上一次的实例会出现在自己的设备列表里**。
- **影响**：列表持续累积幽灵设备（点击必连失败，叠加 C-1/C-2 无反馈）；为 S-1 的冒充攻击提供可预测 id（见安全部分）。
- **置信度**：高。
- **最小修复建议**：设备 id 持久化（SharedPreferences/文件，跨重启稳定，可用 uuid v4 + 真随机）；对 `ServiceRemoved` 按 `id` 主动剔除，或为缓存条目加 last-seen TTL（≈2×心跳超时）后台淘汰。
- **测试建议**：`DiscoveryStateHandle.upsert/remove` + 模拟 `ServiceRemoved` 事件的确定性单测；`generateDeviceId` 连续调用/两次启动不重复的回归断言（持久化后）。

### C-4（严重度：中｜仓库卫生/敏感内容入库，非运行时缺陷）
- **位置**：`.uploads/`（14 个本地草稿资产：截图 png ×9、草稿 txt ×4、`_new.md` ×1）被 `git ls-files` 跟踪且**不在 .gitignore 中**，随 b46a02b 入库。
- **触发条件**：仓库分发/克隆、CI checkout。
- **影响**：本地工作区草稿内容进入版本库与 release 工件链路；按审计规则未读取其内容（可能含个人草稿/PII）。
- **置信度**：高（`git ls-files .uploads` 直接证实）。
- **最小修复建议**：`git rm -r --cached .uploads` + `.gitignore` 增加 `.uploads/`（AUTO_FIX=true 周期执行；本周期仅建议）。

## 四、安全审计（仅针对非安全审计提交 b46a02b 与 32fb4ab）

已确认漏洞（高/中分组）：

> 提交 `32fb4ab` 复查：仅入库 Markdown 审计报告，无新增网络/解析/权限/密钥路径；报告正文经核不含密钥/令牌/PII，**未引入新的已确认漏洞**。

### S-1（高）局域网攻击者可伪造设备并劫持远程控制信道（无配对/无认证）
- **攻击者画像**：与受害者同网段（同 LAN / 同 Wi-Fi / 同蜂窝热点）的未授权设备；无需任何凭据。
- **可控输入**：mDNS 应答（`_emote._udp.local.` / `_emote._tcp.local.` 的 TXT 记录：`id/name/quic_port/tcp_port/...`）、QUIC 服务端自签证书、TCP 帧流。
- **确切代码路径**：
  1. `discovery/service.rs::build_props` —— TXT 无任何配对密钥/签名，仅公布 id、名称、明文端口；
  2. 攻击者注册同名/同 `id`（或新 `id` + 伪装名称）的 mDNS 服务，把 IP/端口指向自己；`discovery/browser.rs::handle_service_event` L108-112 以 `id` 为键 `upsert` → **直接覆盖**受害设备条目中的 IP/端口；
  3. 受害者点击连接：`connection/manager.rs::connect_async` → `quic::connect`（`SkipServerVerification`，见 `transport/quic.rs` L109-118，**信任任意证书**）或 `tcp::connect`（无任何应用层认证）→ 攻击者只需运行 `make_server_endpoint`/`tcp::bind` 接受连接并回读心跳帧即可维持"已连接"假象；
  4. 后果随功能演进放大：当前可劫持 Control/心跳信道；第 3 段（Video/Input）落地后 = 画面流与键盘鼠标输入被重定向至攻击者。
- **影响**：设备冒充（fake device injection）、连接重定向（MITM/流量劫持）、会话固定；对"远程控制"类产品属高影响。
- **证据**：`transport/quic.rs` L21-34（客户端跳过证书校验，注释自述"MVP 阶段…生产可后续加固"）、L44（服务端 `with_no_client_auth`）；`discovery/service.rs` L123-136（TXT 无密钥）；`discovery/browser.rs` L139（id 完全信任 TXT）。
- **修复建议**：① 建立首次配对：本地一次性输入/扫码交换设备公钥或共享密钥（持久化到各端本地存储）；② TXT 携带设备指纹（公钥 hash），浏览器端对未知指纹的 `id` 拒绝覆盖既有条目（防 S-1 步骤 2）；③ 用持久化的设备公钥替换 `SkipServerVerification`（QUIC 证书校验），TCP 回退信道增加与公钥绑定的会话级握手/PSK；④ 会话段（accept 侧）对未知设备 id 拒绝接入。
- **置信度**：高（端到端利用路径全部由已实现代码构成，无假设组件）。

### S-2（中）设备身份可预测且不持久化
- **位置**：`app/lib/services/discovery_service.dart` L178-189。
- **攻击者画像/可控输入**：同 S-1；攻击者无需控制任何输入——`id = emo-<启动时刻毫秒hex>-<微秒时钟派生 6hex>`，同一机器同一秒内可离线推算出全部候选 id。
- **代码路径/影响**：冒充"某台特定真实设备"（S-1 步骤 2 需要知道其 id）从"需嗅探"降级为"可预测"；`_randHex` 还重复调用 `DateTime.now()`，同毫秒内两次启动有碰撞概率。协议文档宣称 UUID v4，实现不符。
- **修复建议**：改用密码学随机源生成 UUIDv4 并持久化（与 C-3 修复合并）。
- **置信度**：高（代码直接可读）。

### 加固项（不计入已确认漏洞）
- S-3（低）`harmony_font_loader.dart` L598-601：zip 防穿越用**字符串前缀** `target.path.startsWith(outDir)` 判定，`../` 条目在字符串层面可通过检查（`/x/harmony_sans/../evil` 前缀成立）；因 zip 来源为固定 HTTPS 官方域名（developer.huawei.com），需 HTTPS 中间人/DNS 控制才可利用，非已确认可利用。建议改用规范化路径包含判定（canonicalize + 分隔符检查）。
- 残留观察（无需本周期动作）：`read_frame` 对每连接允许单次分配 ≤256MiB（`MAX_FRAME_LEN`），在"无认证"前提下同网攻击者可对未来的 accept 侧形成内存压力；随 S-1 认证落地与 accept 侧白名单收敛。

未发现：代码/配置中的硬编码密钥或令牌（QUIC 证书为运行时 `rcgen` 自签）；屏幕/剪贴板/文件内容写入日志（`AppLog` 仅记录版本、路径、异常栈；剪贴板仅日志页用户主动复制）；注入向量（无 SQL/Shell/模板；`fc-match` 子进程参数为固定族名常量，无用户输入拼接）。

## 五、测试缺口分析

对照现状（Rust 侧仅 `discovery/browser.rs` 有确定性用例 + 1 个 `#[ignore]` 组播链路用例；Flutter 侧仅 `widget_test.dart` 静态断言与 `perf_bench_test`）：

1. **P0｜mDNS 双实例集成测试（验收报告遗留项 #1）**：`browser.rs::live_mdns_browse_parses_txt_across_platforms` 依赖真实组播且 `#[ignore]`，CI 恒跳过。建议按验收报告建议补**确定性**双实例用例：`ServiceDaemon` 注册 + 浏览走 loopback/同进程（mdns-sd 支持 127.0.0.1 本地解析），断言 TXT→`DeviceInfo` 解析；并补畸形 TXT 边界（缺字段→端口 0、垃圾端口串、重复 id、超长 TXT 属性）。
2. **P0｜连接/QUIC/TCP 集成测试（验收报告遗留项 #2）**：`connection/manager.rs`、`transport/{quic,tcp,mod}.rs` 零测试。建议本地 127.0.0.1 起 `make_server_endpoint`+`tcp::bind`，注入 `ConnectionConfig` 短周期，覆盖：QUIC 优先/TCP 回退、心跳超时断线、**C-2 重连回归**、`send_message` 在 handler 退出后报错。
3. **P0｜帧编解码边界单测（零测试模块）**：`transport/mod.rs::read_frame`（`length > MAX_FRAME_LEN` 拒绝、10 字节头截断、魔数不符、0 长度 payload、EOF 中途断流）与 `protocol/message.rs` 头往返序列化；确定性、零网络，建议立即建立首个用例。
4. **P1｜Flutter 服务层/页面测试**：`DiscoveryService`/`ConnectionService` 无测试；`device_list_page` 连接失败路径无覆盖。建议为 FRB 层做 fake 注入的 widget 测试，覆盖 C-2a（失败时不再抛未处理异常、错误可见）。

FFI 同步校验（Emote 特有）：`app/lib/src/rust/api/*`、`frb_generated.dart`（2.13.0 生成标记）与 `rust/emote_core/src/frb_generated.rs` 的 API 表面（ConnectionHandle 6 方法、DiscoveryHandle 8 方法、`greet`、`BroadcastConfig` 字段）一一对应，**FFI 绑定已同步，无回归**。

## 六、建议动作

**必须立即修复（阻碍核心链路）**
- C-1：消除"公布端口但无监听"的虚标（session 段落地前，discovery 端口公布应受控），并排期服务端 accept 实现。
- C-2：`connect_to_device` 对 `Disconnected` 滞留条目重连 + Dart 三处 connect 调用异常捕获与错误呈现。

**建议本日修复（低成本高价值）**
- C-4：`.uploads/` 出仓 + 入 .gitignore（一行改动 + 一行 ignore）。
- C-3（id 持久化 + 幽灵淘汰）可随 C-2 同批处理。

**建议后续跟进（第 3 段落地前必须完成）**
- S-1：配对/设备公钥 + QUIC 证书校验替换 `SkipServerVerification` + accept 侧 id 白名单；S-2 并入 C-3 修复；S-3 路径包含判定加固。

**需人工确认**
- 版本漂移：README(Dev-2.0) vs pubspec(2.3.1+5) vs 验收报告(2.0.0+2) 三处不一致，且浅克隆无 tag 无法核对远端；建议维护者统一基线并补 tag。
- `Cargo.lock` 被 .gitignore 忽略（对二进制产品不寻常，影响可复现构建）——需确认是否有意。

**Release 建议**：本周期 AUTO_FIX=false，未应用任何修复，**不打 tag、不打包、不写 security-audit 更新日志**；C-1/C-2 修复合入后建议以 `v2.3.2`（hotfix 通道，沿用 `.github/release-notes/` 约定）发布，并在 release notes 中注明"断连重连/错误提示修复 + 端口公布与监听一致性"。

**更新日志建议**：无（本周期无修复提交）。

## 七、固定结论

存在已确认发现，不套用"无发现"结论。本日输出（覆盖 24h 窗口内 2 个非安全审计提交）：
- 提交 `b46a02b`（整库导入）：**存在 3 个关键正确性缺陷（C-1/C-2/C-3）与 1 项仓库卫生问题（C-4）**。
- 提交 `32fb4ab`（审计报告文档入库）：过去 24 小时的该提交中未发现关键缺陷；未引入新的已确认漏洞；未发现有意义的测试覆盖缺口。
- 安全审计完成（b46a02b）：**发现 1 个高危已确认漏洞（S-1 无认证设备冒充/信道劫持）与 1 个中危（S-2 可预测设备身份）**。
- 测试缺口（全窗口）：**4 项（3 个 P0 + 1 个 P1）**，含验收报告 2 个遗留项。
- AUTO_FIX=false：未修改代码、未新增提交、未打 tag、未打包；修复建议已列出待人工排期。

---
*审计代理：每日自动化审计（Agnes-3.0-flash）· 数据截止：2026-10-02（Asia/Shanghai）· 本报告为只读审计产物，未随仓库提交。*
