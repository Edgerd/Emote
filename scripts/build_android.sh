#!/usr/bin/env bash
# ============================================================================
# Emote 第1.6段：Android 端构建脚本
#   1) cargo build --release 交叉编译三个 ABI：arm64-v8a / armeabi-v7a / x86_64
#      （NDK 交叉编译器经 CARGO_TARGET_<t>_LINKER 与 CC_<t>/AR_<t> 指定）
#   2) flutter build apk --release（Gradle 会把 jniLibs/*.so 打进 APK）
# 任一步失败立即退出（set -euo pipefail）。
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app"
RUST="$ROOT/rust/emote_core"

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${FLUTTER_BIN:-/opt/flutter/bin}:$PATH"
fi

# ---- Android SDK / NDK 定位 ----
SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK_DIR" ] && [ -f "$APP/android/local.properties" ]; then
  SDK_DIR="$(grep '^sdk.dir=' "$APP/android/local.properties" | cut -d= -f2)"
fi
[ -n "$SDK_DIR" ] && [ -d "$SDK_DIR" ] || { echo "ERROR: 找不到 Android SDK" >&2; exit 1; }

NDK_ROOT="$SDK_DIR/ndk/$(ls "$SDK_DIR/ndk" | sort -V | tail -n1)"
LLVM_BIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
[ -d "$LLVM_BIN" ] || { echo "ERROR: 找不到 NDK LLVM 工具链 $LLVM_BIN" >&2; exit 1; }
echo "==> NDK : $NDK_ROOT"
export ANDROID_NDK_HOME="$NDK_ROOT"

# 目标 ABI -> (Rust target, NDK clang)
declare -A ABIS=(
  [arm64-v8a]=aarch64-linux-android
  [armeabi-v7a]=armv7-linux-androideabi
  [x86_64]=x86_64-linux-android
)
# 统一输出到 default cargo dir（rust/emote_core/target/<target>/release/），
# 与 Gradle 打包任务（从 rustRoot/target 复制到 jniLibs）保持一致。
printf '%s\n' "=================================================="
echo "jniLibs 输出目录：$APP/android/app/src/main/jniLibs/"
rm -rf "$APP/android/app/src/main/jniLibs/emote"
printf '%s\n' "=================================================="

echo "---- [1/2] cargo build --release 交叉编译 3 个 ABI ----"
for ABI in "${!ABIS[@]}"; do
  TARGET="${ABIS[$ABI]}"
  # cargo 以大写、连字符转下划线命名 target 相关环境变量，如：
  #   aarch64-linux-android -> CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
  t="${TARGET//-/_}"; t="${t^^}"
  LINKER_KEY="CARGO_TARGET_${t}_LINKER"
  case "$TARGET" in
    aarch64-linux-android)      CLANG="aarch64-linux-android24-clang" ;;
    armv7-linux-androideabi)    CLANG="armv7a-linux-androideabi24-clang" ;;
    x86_64-linux-android)       CLANG="x86_64-linux-android24-clang" ;;
  esac
  echo "    -> $ABI (target: $TARGET, clang: $CLANG)"
  env \
    "$LINKER_KEY=$LLVM_BIN/$CLANG" \
    "CC_${TARGET//-/_}=$LLVM_BIN/$CLANG" \
    "AR_${TARGET//-/_}=$LLVM_BIN/llvm-ar" \
    ANDROID_NDK_HOME="$NDK_ROOT" \
    cargo build --release --manifest-path "$RUST/Cargo.toml" --target "$TARGET"

  SO="$RUST/target/$TARGET/release/libemote_core.so"
  [ -f "$SO" ] || { echo "ERROR: 未找到 $SO" >&2; exit 1; }
  ls -lh "$SO"
done

echo "---- [2/2] flutter build apk --release ----"
(cd "$APP/android" && flutter build apk --release)

APK="$APP/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$APK" ] || { echo "ERROR: 未找到 $APK" >&2; exit 1; }

echo "=================================================="
echo "Android 构建成功："
echo "  APK : $APK"
echo "  内置 ABI : ${!ABIS[@]}"
echo "=================================================="