# Emote · Flutter 应用 `app/`

三端（Windows / Linux / Android）共用的 Flutter UI，与 Rust 核心 `emote_core`（`../rust/emote_core`）通过 `flutter_rust_bridge` 通信。

## 结构

```text
lib/
├── main.dart              # 应用入口，加载 Rust 动态库
├── pages/                 # 设备列表 / 连接状态 / 设置
├── services/              # 发现 / 连接 / Android 权限
├── src/rust/              # FRB 生成的绑定
└── theme/                 # Material 3 主题与桌面适配
```

## 构建

> 先回到仓库根目录生成 FFI 绑定、编译核心库，再在本目录构建应用。详见根目录 [README](../README.md)。

```sh
# 依赖安装
flutter pub get

# 静态检查
flutter analyze

# 构建
flutter build linux --release
flutter build windows --release
flutter build apk --release
```