# ============================================================================
# Emote 第1.6段：Windows 性能基线快照脚本
# 采集三类指标：
#   1) 应用启动到首帧耗时   —— integration_test 在 Windows 真实设备下 runApp
#                              并等待 firstFrameRasterized
#   2) 空闲内存占用         —— 顺序运行 release 应用后读取进程 WorkingSet64
#   3) greet FFI 调用 1000 次平均耗时 / p50 / p95
# 输出：dist\perf_snapshot_windows.json
# 依赖：integration_test 依赖已加入 dev_dependencies
# ============================================================================
$ErrorActionPreference = "Stop"

$ROOT = Resolve-Path (Join-Path $PSScriptRoot "..")
$APP  = Join-Path $ROOT "app"
$RELEASE = Join-Path $APP "build\windows\x64\runner\Release"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $env:PATH = "C:\src\flutter\bin;$env:PATH"
}
if ($env:FLUTTER_BIN) { $env:PATH = "$env:FLUTTER_BIN;$env:PATH" }

$Result = [ordered]@{ platform = "windows" }

# ---- 1) 首帧 + 3) greet FFI（integration_test 真实设备） ----
Write-Host "==> [perf] 驱动 integration_test（-d windows）..."
$log = Join-Path $env:TEMP "emote_perf_win.log"
flutter test (Join-Path $APP "integration_test\perf_bench_test.dart") -d windows *> $log
if ($LASTEXITCODE -ne 0) { throw "integration_test 失败，见 $log" }
$txt = Get-Content $log -Raw
function Get-Perf($key) {
    $m = [regex]::Match($txt, "$key=([0-9.]+)")
    if ($m.Success) { return $m.Groups[1].Value } else { return "n/a" }
}
$Result.launch_to_first_frame_ms = Get-Perf "PERF_LAUNCH_TO_FIRST_FRAME_MS"
$Result.greet_n                 = Get-Perf "PERF_GREET_N"
$Result.greet_avg_ms            = Get-Perf "PERF_GREET_AVG_MS"
$Result.greet_p50_ms            = Get-Perf "PERF_GREET_P50_MS"
$Result.greet_p95_ms            = Get-Perf "PERF_GREET_P95_MS"

# ---- 2) 空闲内存：跑 release 应用，采样 WorkingSet ----
Write-Host "==> [perf] 采样 release 应用空闲内存..."
if (Test-Path (Join-Path $RELEASE "emote.exe")) {
    $p = Start-Process (Join-Path $RELEASE "emote.exe") -PassThru
    Start-Sleep -Seconds 6
    $p.Refresh()
    $Result.idle_rss_mib = [math]::Round($p.WorkingSet64 / 1MB, 1)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
} else {
    $Result.idle_rss_mib = "n/a"
    Write-Warning "未找到 $RELEASE\emote.exe，先运行 scripts/build_windows.ps1"
}

$outDir = Join-Path $ROOT "dist"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = Join-Path $outDir "perf_snapshot_windows.json"
$Result | ConvertTo-Json | Set-Content -Path $out -Encoding UTF8
Write-Host "== 性能基线快照已写入：$out"
Get-Content $out