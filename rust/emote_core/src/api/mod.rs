//! api —— Dart ↔ Rust 对外暴露的 FFI 接口层。
//!
//! 只在此处声明会生成桥接代码的函数，避免内部实现泄漏为 Dart 可见 API。

pub mod simple;

pub mod discovery;
pub mod connection;