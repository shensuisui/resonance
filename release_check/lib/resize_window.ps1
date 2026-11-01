<#
.SYNOPSIS
  release_check/lib/resize_window.ps1 —— 把运行中的 fm_app 窗口调到指定尺寸
.DESCRIPTION
  用 Win32 MoveWindow 改**真实窗口尺寸**（不是改 MediaQuery），这样布局断点、
  LayoutBuilder、导航栏切换走的都是真实路径。
  尺寸是外框尺寸，客户区约减去标题栏与边框；断点断言请留出余量。
#>
param(
  [Parameter(Mandatory=$true)][int]$Width,
  [Parameter(Mandatory=$true)][int]$Height
)

$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
if (-not ('FmWindow' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class FmWindow {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
}

$p = Get-Process fm_app -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output 'NO_APP'; exit 2 }
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { Write-Output 'NO_HANDLE'; exit 3 }

[void][FmWindow]::MoveWindow($h, 40, 30, $Width, $Height, $true)
[void][FmWindow]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 400

$r = New-Object FmWindow+RECT
[void][FmWindow]::GetClientRect($h, [ref]$r)
Write-Output ('RESIZED outer=' + $Width + 'x' + $Height + ' client=' + ($r.Right - $r.Left) + 'x' + ($r.Bottom - $r.Top))
