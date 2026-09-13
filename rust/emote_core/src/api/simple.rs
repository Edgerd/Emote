//! simple —— 最小 FFI 演示接口。
//!
//! 本段仅实现 `greet`，用于验证 Dart ↔ Rust 桥接链路打通。

/// 返回一条问候语，证明 Dart 能同步拿到 Rust 的返回值。
///
/// 修改此处返回值并重新运行 `flutter_rust_bridge_codegen generate`，
/// Flutter 侧 `greet` 的返回将同步变化。
pub fn greet(name: String) -> String {
    format!("Hello, {name}! (from emote_core via flutter_rust_bridge)")
}