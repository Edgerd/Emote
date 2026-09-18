# Emote 2.1.0

> **发布通道**：Pre-release（预览版） · **标签**：`Dev-2.1`
> **建议安装**：尝鲜预览版本，主要用于功能迭代验证；生产环境请选用正式版。

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

### 🚀 新特性
- 集成 Rust 核心（`emote_core`）与 Flutter 端 FFI 桥接，三端共用设备发现 / 连接协议栈。
- 基于 mDNS（`mdns-sd`）的局域网设备发现框架：同时广播本机服务并浏览同网段设备。
- 美化 MD3 设置界面：深浅色 / 动态颜色 / 种子色可配置并持久化。
- 设备列表页接入发现状态指示（扫描中 / 运行中 / 出错）与单设备连接入口。

### 🔧 修复
- 修复设置页若干交互与状态回显问题。
- 修复桌面端窗口尺寸自适应与导航栏适配（NavigationRail / NavigationBar 切换）。

### 📋 其它
- 发布流水线支持 `v*` / `Dev-*` 标签触发三端构建。
- 应用版本号提升至 `2.1.0`（预览版）。

---

## 已知问题
- Android 模拟器默认 NAT 会过滤 mDNS 组播、扫不到宿主机，需真机或同一桥接网段验证移动端。

---

## 下一步计划

- [ ] 修复 mDNS TXT 属性解析，正确显示系统类型 / 端口 / 名称
- [ ] 实现 Windows ↔ Linux 双向控制
- [ ] 实现 Android 控制桌面端
- [ ] 复用 scrcpy 实现桌面端控制 Android
- [ ] MD3E（Material Design 3 Expressive）界面统一
- [ ] 多会话标签页与自适应码率控制

---

## 使用说明

1. 三端设备连接**同一局域网**。
2. 启动 Emote，授予必要权限（Android 需「本地网络 / 组播」权限）。
3. 在设备列表页使用 mDNS 发现对端并建立连接。
4. 若发现失败：Android 请确认已获取 MulticastLock；桌面端请确认防火墙放行 UDP 组播与 QUIC/TCP 端口。

> 仅面向**纯局域网**使用，请勿跨公网部署。

## 下载

见本 Release 页面下方 **Assets**。