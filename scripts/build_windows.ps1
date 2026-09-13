# ============================================================================
# Emote 第1.6段：Windows 端构建脚本
#   1) cargo build --release（host 目标由 rustup 默认 x86_64-pc-windows-msvc）
#   2) flutter build windows --release
#   3) 将 emote_core.dll 复制进 runner/Release，使运行时能找到 Rust 动态库
# 任一步失败立即退出（$ErrorActionPreference = "Stop"）。
# 产物：build/windows/x64/runner/Release/emote.exe（含 emote_core.dll）
# ============================================================================
$ErrorActionPreference = "Stop"

# 定位仓库根目录（scripts/ 的上一级）
$ROOT = Resolve-Path (Join-Path $PSScriptRoot "..")
$APP  = Join-Path $ROOT "app"
$RUST = Join-Path $ROOT "rust\emote_core"

# 若 flutter 不在 PATH，尝试常见安装位置
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $flutterDefault = "C:\src\flutter\bin"
    if ($env:FLUTTER_BIN) { $flutterDefault = $env:FLUTTER_BIN }
    $env:PATH = "$flutterDefault;$env:PATH"
}
Write-Host "==> flutter : $((Get-Command flutter).Source)"
Write-Host "==> rustc   : $(rustc --version)"

Write-Host "---- [1/3] cargo build --release (x86_64-pc-windows-msvc) ----"
Push-Location $RUST
cargo build --release
if ($LASTEXITCODE -ne 0) { throw "cargo build 失败" }
$DLL = Join-Path $RUST "target\release\emote_core.dll"
if (-not (Test-Path $DLL)) { throw "未找到 $DLL" }
(Get-Item $DLL) | Select-Object FullName, Length
Pop-Location

Write-Host "---- [2/3] flutter build windows --release ----"
Push-Location $APP
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows 失败" }
Pop-Location

$RELEASE = Join-Path $APP "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $RELEASE "emote.exe"))) { throw "未找到 emote.exe" }

Write-Host "---- [3/3] 复制 emote_core.dll 到 Release ----"
Copy-Item $DLL (Join-Path $RELEASE "emote_core.dll") -Force

Write-Host "=================================================="
Write-Host "Windows 构建成功："
Write-Host "  可执行文件 : $RELEASE\emote.exe"
Write-Host "  Rust 动态库: $RELEASE\emote_core.dll"
Write-Host "=================================================="