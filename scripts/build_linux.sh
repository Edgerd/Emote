#!/usr/bin/env bash
# ============================================================================
# Emote 第1.6段：Linux 端构建脚本
#   1) cargo build（host 目标 x86_64-unknown-linux-gnu）
#   2) flutter build linux --release
# 任一步失败立即退出（set -euo pipefail）。
# 产物：build/linux/x64/release/bundle/ 下 emote 可执行文件 + lib/libemote_core.so
# ============================================================================
set -euo pipefail

# 定位仓库根目录（scripts/ 的上一级）
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app"
RUST="$ROOT/rust/emote_core"

# 若 flutter 不在 PATH，则补充到默认安装位置
if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${FLUTTER_BIN:-/opt/flutter/bin}:$PATH"
fi
echo "==> flutter : $(command -v flutter)"
# rust-toolchain.toml 已锁定 1.92.0，cargo/rustc 由 rustup 按目录自动选用
echo "==> rustc   : $(rustc --version)"
echo "==> cargo   : $(cargo --version)"

echo "---- [1/2] cargo build (host: x86_64-unknown-linux-gnu) ----"
cargo build --release --manifest-path "$RUST/Cargo.toml" \
    --target x86_64-unknown-linux-gnu

LIB="$RUST/target/x86_64-unknown-linux-gnu/release/libemote_core.so"
if [ ! -f "$LIB" ]; then
  echo "ERROR: 未找到 Rust 产物 $LIB" >&2
  exit 1
fi
ls -lh "$LIB"

echo "---- [2/2] flutter build linux --release ----"
(cd "$APP" && flutter build linux --release)

BUNDLE="$APP/build/linux/x64/release/bundle"
[ -f "$BUNDLE/emote" ] || { echo "ERROR: 未找到 $BUNDLE/emote" >&2; exit 1; }
[ -f "$BUNDLE/lib/libemote_core.so" ] || { echo "ERROR: 未找到 libemote_core.so" >&2; exit 1; }

echo "=================================================="
echo "Linux 构建成功："
echo "  可执行文件 : $BUNDLE/emote"
echo "  Rust 动态库: $BUNDLE/lib/libemote_core.so"
echo "=================================================="