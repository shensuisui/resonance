<#
.SYNOPSIS
  release_check/run_app.ps1 —— 发版前集成检查专用启动器（Windows）

.DESCRIPTION
  detached 启动 resonance_app（--dart-define=RESONANCE_DRIVER=true），并把 VM service 的
  WebSocket 地址写进 .dsh/tmp/flutter_run.uri。

  为什么必须 detached：用工具的后台 job 托管 flutter run，一旦调用超时，
  进程树会被留下，其中构建子进程占住 .dart_tool/hooks_runner 的锁，
  之后所有构建都报 MSB8066（skill 红线第 2 条）。

  为什么用 dart.exe + flutter_tools.snapshot 而不是 flutter.bat：
  Start-Process 传 .bat 需经 cmd.exe，带空格路径的引号会被 cmd 二次解析，
  容易起不来；直接调 dart 跑 snapshot 无此问题。

.PARAMETER Attach
  只轮询已有日志里的 URI，不重新启动 App。

.PARAMETER Cleanup
  只做清理：列出/结束本工程的 resonance_app 与 flutter run 进程。

.EXAMPLE
  .\run_app.ps1
  .\run_app.ps1 -Attach
  .\run_app.ps1 -Cleanup -Force
#>
[CmdletBinding()]
param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$AppDir = 'resonance_app',
  [string]$Target = 'lib/main_v2.dart',
  [string]$DartDefine = 'RESONANCE_DRIVER=true',
  [int]$TimeoutSec = 120,
  [switch]$Attach,
  [switch]$Cleanup,
  [switch]$Force
)

$ErrorActionPreference = 'Continue'

$tmpDir    = Join-Path $ProjectRoot '.dsh\tmp'
$logOut    = Join-Path $tmpDir 'flutter_run.out.log'
$logErr    = Join-Path $tmpDir 'flutter_run.err.log'
$uriFile   = Join-Path $tmpDir 'flutter_run.uri'
$stateFile = Join-Path $tmpDir 'flutter_run.state.json'
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

function Get-ProjectAppProcesses {
  # 只认「进程名 resonance_app 且可执行文件在工程内」，不清别的工程、不杀 dart
  Get-Process -Name 'resonance_app' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and ($_.Path.StartsWith($ProjectRoot, [StringComparison]::OrdinalIgnoreCase))
  }
}

function Get-ProjectFlutterRunProcesses {
  # 本工程的 flutter run：命令行里同时出现 flutter_tools.snapshot 与工程路径
  Get-CimInstance Win32_Process -Filter "Name='dart.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and
      $_.CommandLine -like '*flutter_tools.snapshot*' -and
      $_.CommandLine -like "*$ProjectRoot*"
    }
}

function Show-Residuals {
  $apps = @(Get-ProjectAppProcesses)
  $runs = @(Get-ProjectFlutterRunProcesses)
  $appIds = ($apps | ForEach-Object { $_.Id }) -join ','
  $runIds = ($runs | ForEach-Object { $_.ProcessId }) -join ','
  Write-Output ("resonance_app 进程: " + $apps.Count + $(if ($apps) { ' -> ' + $appIds } else { '' }))
  Write-Output ("flutter run 进程: " + $runs.Count + $(if ($runs) { ' -> ' + $runIds } else { '' }))
  return ($apps.Count + $runs.Count)
}

function Invoke-Cleanup {
  foreach ($a in @(Get-ProjectAppProcesses)) { Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue }
  foreach ($r in @(Get-ProjectFlutterRunProcesses)) { Stop-Process -Id $r.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 600
  $left = Show-Residuals
  if ($left -gt 0) { Write-Output 'WARN 仍有残留（句柄可能未释放，稍后重试）' } else { Write-Output 'OK 已清理干净' }
}

if ($Cleanup) {
  if ($Force) { Invoke-Cleanup } else { Show-Residuals | Out-Null }
  exit 0
}

if (-not $Attach) {
  $stale = @(Get-ProjectAppProcesses)
  if ($stale.Count -gt 0) {
    Write-Output ('先杀掉上一轮 resonance_app（会锁住 build 产物）: ' + (($stale | ForEach-Object { $_.Id }) -join ','))
    foreach ($a in $stale) { Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 800
  }

  foreach ($f in @($logOut, $logErr, $uriFile, $stateFile)) {
    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
  }

  $dartExe  = Join-Path $ProjectRoot '.fvm\flutter_sdk\bin\cache\dart-sdk\bin\dart.exe'
  $snapshot = Join-Path $ProjectRoot '.fvm\flutter_sdk\bin\cache\flutter_tools.snapshot'
  if (-not (Test-Path $dartExe))  { Write-Output "ERR dart.exe 不存在: $dartExe"; exit 2 }
  if (-not (Test-Path $snapshot)) { Write-Output "ERR flutter_tools.snapshot 不存在: $snapshot"; exit 2 }

  $appPath = Join-Path $ProjectRoot $AppDir
  # -t 必须显式给 main_v2.dart：缺省会跑 lib/main.dart（v1 界面），
  # 检查跑错入口会得到一份"看起来正常"的假报告。
  $argList = @($snapshot, 'run', '-d', 'windows', '-t', $Target, '--debug', "--dart-define=$DartDefine")

  $p = Start-Process -FilePath $dartExe -ArgumentList $argList -WorkingDirectory $appPath -RedirectStandardOutput $logOut -RedirectStandardError $logErr -WindowStyle Hidden -PassThru
  $state = [ordered]@{
    runnerPid = $p.Id
    startedAt = (Get-Date).ToString('o')
    dartExe   = $dartExe
    appPath   = $appPath
    logOut    = $logOut
    logErr    = $logErr
  }
  ($state | ConvertTo-Json) | Set-Content -Path $stateFile -Encoding UTF8
  Write-Output ("已 detached 启动 flutter run，runnerPid=" + $p.Id)
  Write-Output ("日志: " + $logOut)
}

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$ws = $null
while ((Get-Date) -lt $deadline) {
  if (Test-Path $logOut) {
    $txt = Get-Content $logOut -Raw -ErrorAction SilentlyContinue
    if ($txt) {
      $ms = [regex]::Matches($txt, 'http://127\.0\.0\.1:(\d+)/(\S+?)=/')
      if ($ms.Count -gt 0) {
        $m = $ms[$ms.Count - 1]
        $ws = 'ws://127.0.0.1:' + $m.Groups[1].Value + '/' + $m.Groups[2].Value + '=/ws'
        break
      }
    }
  }
  Start-Sleep -Milliseconds 1500
}

if ($ws) {
  $ws | Set-Content -Path $uriFile -Encoding UTF8
  Write-Output ('OK VM service: ' + $ws)
  exit 0
}

Write-Output 'PENDING 还没拿到 VM service URI'
if (Test-Path $logOut) {
  Write-Output '--- 日志尾部 ---'
  Get-Content $logOut -Tail 15 -ErrorAction SilentlyContinue
}
if (Test-Path $logErr) {
  $e = Get-Content $logErr -Tail 10 -ErrorAction SilentlyContinue
  if ($e) { Write-Output '--- stderr 尾部 ---'; $e }
}
exit 3
