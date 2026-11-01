<#
.SYNOPSIS
  release_check/run_release_check.ps1 —— 发版前集成检查的唯一入口

.DESCRIPTION
  预检 -> detached 启动 App -> 抓 VM service URI -> 跑 driver
  （三断点布局巡检 + 功能用例）-> 生成 report.md/results.json -> 精确清理。

  平时不要调用：用例不在 test/ 下、不接 CI、不接 pre-commit、不进默认构建目标。
  退出码：0 全通过 / 1 有用例失败 / 2 环境或前置错误

.PARAMETER Mode
  full（默认）= 三断点巡检 + 功能用例；sweep = 只跑巡检；smoke = 只跑功能用例

.EXAMPLE
  .\release_check\run_release_check.ps1
  .\release_check\run_release_check.ps1 -Mode smoke
#>
[CmdletBinding()]
param(
  [ValidateSet('full', 'sweep', 'smoke')][string]$Mode = 'full',
  [int]$StartTimeoutSec = 240
)

$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dart = Join-Path $root '.fvm\flutter_sdk\bin\cache\dart-sdk\bin\dart.exe'
$appDir = Join-Path $root 'fm_app'
$checkDir = $PSScriptRoot

# ---------- 预检 ----------
foreach ($f in @($dart, (Join-Path $appDir 'pubspec.yaml'), (Join-Path $checkDir 'pubspec.yaml'))) {
  if (-not (Test-Path $f)) {
    Write-Output ('ENV 错误：缺少 ' + $f)
    exit 2
  }
}

# ---------- 启动（detached）----------
& (Join-Path $checkDir 'run_app.ps1') -TimeoutSec $StartTimeoutSec
if ($LASTEXITCODE -ne 0) {
  Write-Output 'ENV 错误：App 未就绪（见 .dsh/tmp/flutter_run.out.log）'
  exit 2
}

$stamp = (Get-Date).ToString('yyyy-MM-ddTHH-mm-ss')
$outRoot = Join-Path $root ('build\release_check\' + $stamp)
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null

Push-Location $checkDir
& $dart pub get | Out-Null

$fail = 0
$sizes = @(
  @{ n = 'phone'; w = 430; h = 900 },
  @{ n = 'tablet'; w = 910; h = 1020 },
  @{ n = 'desktop'; w = 1290; h = 840 }
)

if ($Mode -ne 'smoke') {
  foreach ($s in $sizes) {
    Write-Output ('=== 巡检 ' + $s.n + ' ' + $s.w + 'x' + $s.h + ' ===')
    & (Join-Path $checkDir 'lib\resize_window.ps1') -Width $s.w -Height $s.h
    Start-Sleep -Milliseconds 1500
    & $dart run bin/driver.dart --plan config/sweep_plan.yaml --out (Join-Path $outRoot $s.n) --size $s.n
    if ($LASTEXITCODE -ne 0) { $fail = 1 }
  }
  & $dart run bin/driver.dart --index-root $outRoot
  if ($LASTEXITCODE -ne 0) { $fail = 1 }
}

if ($Mode -ne 'sweep') {
  Write-Output '=== 功能用例 desktop（重启拿干净基线）==='
  # 三轮 resize 巡检之后应用侧状态会劣化（截图与 route 对不上、点击落到旧帧），
  # 功能阶段单独重启一次，避免跨阶段互相污染。
  & (Join-Path $checkDir 'run_app.ps1') -TimeoutSec $StartTimeoutSec
  if ($LASTEXITCODE -ne 0) {
    Write-Output 'ENV 错误：功能阶段 App 未就绪'
    Pop-Location
    exit 2
  }
  & (Join-Path $checkDir 'lib\resize_window.ps1') -Width 1290 -Height 840
  Start-Sleep -Milliseconds 1500
  & $dart run bin/driver.dart --plan config/test_plan.yaml --out (Join-Path $outRoot 'functional') --size desktop
  if ($LASTEXITCODE -ne 0) { $fail = 1 }
}
Pop-Location

# ---------- 归档日志 ----------
$logDir = Join-Path $outRoot 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
foreach ($n in @('flutter_run.out.log', 'flutter_run.err.log')) {
  $src = Join-Path $root ('.dsh\tmp\' + $n)
  if (Test-Path $src) { Copy-Item $src (Join-Path $logDir $n) -Force }
}

# ---------- 精确清理 ----------
& (Join-Path $checkDir 'run_app.ps1') -Cleanup -Force
Write-Output ('产物: ' + $outRoot)
exit $fail
