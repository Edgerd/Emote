# 主题系统文档

> 与代码同步基线：Dev-5.0。实现位于 `app/lib/theme/` 与 `app/lib/services/settings_controller.dart`。

## M3E 主题结构

Material Design 3 Expressive 主题由 `theme/app_theme.dart` 统一构建：

- 以 `ColorScheme.fromSeed` 为基底，接入动态颜色覆盖后派生全部组件主题（输入框、卡片、列表、对话框、悬浮层等）。
- 间距 / 圆角常量定义于 `theme/app_theme.dart`（如 `spacingX1`），组件（`metrics_overlay.dart`、`session_tabs.dart` 等）统一引用，不写死像素值。
- 动效规范在 `theme/motion.dart`（M3E 强调型曲线与时长）；M3E 波浪进度条组件为 `widgets/m3e_wave_progress.dart`。
- 三端共用同一套 `MaterialApp` 主题入口（`app/lib/main.dart`），Windows / Linux / Android 视觉一致。

## 动态颜色汲取来源

`theme/dynamic_color.dart` 使用 `dynamic_color` 1.9.0 包：

- Android 12+：从系统壁纸汲取 `DynamicColorScheme`（`DynamicColorBuilder`），取不到时回退种子色方案。
- Windows / Linux：无系统动态色，直接使用种子色方案。
- 回退优先级：系统动态色 → 自定义主题色 → 默认种子色。

## 自定义主题色

`settings_controller.dart`（设置持久化经 `shared_preferences`）：

1. 入口：「设置 → 个性化 → 主题色」。
2. 用户选定颜色后写入设置；`main.dart` 构建 `ColorScheme.fromSeed(seedColor: 自定义色)` 覆盖动态色方案。
3. 选择「跟随系统」即恢复动态颜色优先级。
4. 组件层禁止硬编码品牌色：图标底色用 `colorScheme.secondaryContainer`、前景 `onSecondaryContainer`（见 `more_page.dart` 的 `_MoreTile`），浅色 / 深色 / 动态色下均保证对比度。

## 深色模式

- 三种模式：跟随系统 / 浅色 / 深色，由 `settings_controller.dart` 持久化为 `themeMode`，映射到 `MaterialApp.themeMode`。
- 跟随系统时监听平台 `platformBrightness` 变化自动切换。
- 深色方案同样经 `fromSeed` 派生；深色下组件颜色一律从 `colorScheme` 取（如 `surfaceContainerLow` 分组卡片、`outlineVariant` 分隔线），不出现写死的黑/白。

## 桌面适配

- `theme/window_size_class.dart`：Material 窗口尺寸类（Compact / Medium / Expanded），驱动导航形态（底栏 vs 侧栏）与内容最大宽度（如「更多」页 720 dp 约束）。
- `theme/desktop_adaptation.dart`：桌面端悬停态、滚轮与快捷键行为适配；移动端页面栈（`mobile_session_stack.dart`）与桌面标签（`session_tabs.dart`）按平台路由（`more_page.dart` 的 `_openMultiSession`）。

## 字体

- 默认字体 HarmonyOS Sans：首次启动经 `services/harmony_font_loader.dart` 流式下载（约 49.7 MB，华为官方域，SHA-256 校验），失败回退系统字体；「设置 → 个性化 → 纯局域网模式」可禁止该公网下载。
- 缓存管理：「更多 → 缓存管理」清理字体缓存副本（`FontManager`）。
