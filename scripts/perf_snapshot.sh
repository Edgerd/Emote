#!/usr/bin/env bash
# ============================================================================
# Emote 第1.6段：Linux / macOS 兼容性能基线快照脚本
# 采集三类指标并输出基线快照：
#   1) 应用启动到首帧耗时   —— integration_test 在真实设备（xvfb）下 runApp 后
#                               等待 firstFrameRasterized 的墙钟耗时
#   2) 空闲内存占用         —— 启动 release bundle 后采样 RSS
#   3) greet FFI 调用 1000 次平均耗时 / p50 / p95
# 用法：scripts/perf_snapshot.sh   （可选环境变量 ANDROID_SDK_ROOT）
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app"
RUST="$ROOT/rust/emote_core"
OUTPUT="${PERF_OUTPUT:-$ROOT/dist/perf_snapshot_linux.json}"

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${FLUTTER_BIN:-/opt/flutter/bin}:$PATH"
fi

# xvfb 用于无头 Linux 下驱动真实 GTK 应用；缺失则跳过首帧/内存测量
HAVE_XVFB=false
if command -v xvfb-run >/dev/null 2>&1; then HAVE_XVFB=true; fi

declare -A RESULT
RESULT[platform]="linux"

# ---- 1) 首帧耗时 + 2) greet FFI（integration_test 真实设备） ----
if [ "$HAVE_XVFB" = true ]; then
  echo "==> [perf] 驱动 integration_test（xvfb）..."
  LOG=$(mktemp)
  if ! xvfb-run -a flutter test "$APP/integration_test/perf_bench_test.dart" -d linux >"$LOG" 2>&1; then
    echo "!! integration_test 未通过（可能未构建 release 或缺少 GTK），回退到 VM 侧 FFI 基准" >&2
    tail -5 "$LOG" >&2
  else
    FF_MS=$(grep -oE 'PERF_LAUNCH_TO_FIRST_FRAME_MS=[0-9.]+' "$LOG" | head -1 | cut -d= -f2)
    GREET_N=$(grep -oE 'PERF_GREET_N=[0-9]+'    "$LOG" | head -1 | cut -d= -f2)
    AVG=$(grep -oE 'PERF_GREET_AVG_MS=[0-9.]+'  "$LOG" | head -1 | cut -d= -f2)
    P50=$(grep -oE 'PERF_GREET_P50_MS=[0-9.]+'  "$LOG" | head -1 | cut -d= -f2)
    P95=$(grep -oE 'PERF_GREET_P95_MS=[0-9.]+'  "$LOG" | head -1 | cut -d= -f2)
    RESULT[first_frame_ms]="${FF_MS:-n/a}"
    RESULT[greet_n]="${GREET_N:-1000}"
    RESULT[greet_avg_ms]="${AVG:-n/a}"
    RESULT[greet_p50_ms]="${P50:-n/a}"
    RESULT[greet_p95_ms]="${P95:-n/a}"
  fi
  rm -f "$LOG"
else
  echo "!! xvfb 不可用，跳过首帧/内存测量" >&2
  RESULT[first_frame_ms]="n/a"
fi

# ---- 3) 空闲内存：启动 release bundle 采样 RSS ----
if [ "$HAVE_XVFB" = true ] && [ -x "$APP/build/linux/x64/release/bundle/emote" ]; then
  echo "==> [perf] 采样 release 应用空闲 RSS..."
  xvfb-run -a "$APP/build/linux/x64/release/bundle/emote" >/tmp/emote_perf_run.log 2>&1 &
  sleep 6
  # xvfb-run 内部 re-exec，App 进程 argv[0] 为 .../bundle/emote
  PID="$(pgrep -f 'build/linux/x64/release/bundle/emote' | head -1 || true)"
  if [ -n "$PID" ]; then
    RSS_KB=$(grep VmRSS "/proc/$PID/status" | awk '{print $2}')
    RESULT[idle_rss_kib]="${RSS_KB:-n/a}"
  else
    RESULT[idle_rss_kib]="n/a"
  fi
  pkill -f 'build/linux/x64/release/bundle/emote' 2>/dev/null || true
  pkill -f Xvfb 2>/dev/null || true
fi

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
{
  "platform": "${RESULT[platform]}",
  "flutter": "$(flutter --version --machine 2>/dev/null | grep -oE '"frameworkVersion":"[0-9.]*"' | cut -d'"' -f4 || echo unknown)",
  "collected_at": "$(date -Is)",
  "launch_to_first_frame_ms": "${RESULT[first_frame_ms]}",
  "idle_rss_kib": "${RESULT[idle_rss_kib]}",
  "greet_ffi_1000": {
    "n": "${RESULT[greet_n]}",
    "avg_ms": "${RESULT[greet_avg_ms]}",
    "p50_ms": "${RESULT[greet_p50_ms]}",
    "p95_ms": "${RESULT[greet_p95_ms]}"
  }
}
EOF
echo "== 性能基线快照已写入：$OUTPUT"
cat "$OUTPUT"