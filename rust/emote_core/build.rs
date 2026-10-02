// 构建脚本：为「桌面」target（Windows / Linux 非 Android）发出 `desktop` cfg。
// 各模块用 `#[cfg(desktop)]` 隔离平台特定实现（openh264 编解码 / 输入注入 / X11），
// 保证 Android target 的 `cargo ndk build` 不受桌面依赖影响。
fn main() {
    // 声明自定义 cfg，避免 `unexpected_cfgs` 告警。
    println!("cargo::rustc-check-cfg=cfg(desktop)");

    // 用 target OS 分量（非 arch 分量）判定桌面：`CARGO_CFG_TARGET_OS` = windows/macos/linux/android...
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target = std::env::var("TARGET").unwrap_or_default();
    let desktop = matches!(
        target_os.as_str(),
        "windows" | "macos" | "linux"
    ) && !target.contains("android")
        && !target.contains("ios");
    if desktop {
        println!("cargo:rustc-cfg=desktop");
    }

    // 依赖变更时触发重编译（openh264 等）。
    println!("cargo:rerun-if-changed=build.rs");
}
