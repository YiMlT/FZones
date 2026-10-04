
# Checks the autostart switch against the real registry: one click writes HKCU\...\Run\FZones with
# the quoted path of the engine beside the UI, the next click removes it.
#
#   flutter build windows --release          # and FZones.exe built
#   powershell -File tool\e2e_autostart.ps1
#
# The staged layout is what the installer produces, because the runner only offers the switch when
# FZones.exe is actually next to it. Whatever Run value the user had before is put back at the end,
# and LOCALAPPDATA is staged so the app's own data folder is not touched either.
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class A {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint data, uint extra, IntPtr msg);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public const uint DOWN = 0x0002, UP = 0x0004;
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(150);
    mouse_event(DOWN, 0, 0, IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    mouse_event(UP, 0, 0, IntPtr.Zero);
  }
}
"@
$ErrorActionPreference = 'Continue'
function Say($m) { Write-Output $m }

$root = Join-Path $PSScriptRoot '..\..'
$dist = Join-Path $PSScriptRoot '_e2e_autostart'
$engine = 'D:\Desktop\java\Qoder\test1\PowerToys\x64\Release\FZones.exe'
$ui = Join-Path $root 'fzones-ui\build\windows\x64\runner\Release'
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$failures = 0
$pids = @()

function Check($name, $ok, $detail) {
  if ($ok) { Say "PASS  $name" } else { $script:failures++; Say "FAIL  $name - $detail" }
}
function RunValue { (Get-ItemProperty $runPath -ErrorAction SilentlyContinue).FZones }

$before = RunValue
if (-not (Test-Path $engine)) { Say "ABORT  no engine at $engine"; exit 2 }
if (-not (Test-Path (Join-Path $ui 'FZonesUI.exe'))) { Say 'ABORT  no release UI build'; exit 2 }

Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$distFull = (Resolve-Path $dist).Path
Copy-Item $engine $dist -Force
Copy-Item (Join-Path $ui '*') $dist -Recurse -Force
$env:LOCALAPPDATA = Join-Path $dist 'appdata'
New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
[void][A]::SetProcessDpiAwarenessContext([IntPtr](-4))

try {
  # --app is the review deep link that opens the list already on the App group, so the switch is
  # where the widget test measured it instead of somewhere behind a scroll gesture.
  $p = Start-Process (Join-Path $dist 'FZonesUI.exe') -ArgumentList '--app' -PassThru
  $pids += $p.Id
  Start-Sleep -Seconds 6
  $hwnd = [IntPtr]$p.MainWindowHandle
  # The window is frameless, so its rect is the client area: the logical layout starts at 0,0.
  [void][A]::MoveWindow($hwnd, 40, 40, 1050, 840, $true)
  Start-Sleep -Seconds 3

  $r = New-Object A+RECT
  [void][A]::GetWindowRect($hwnd, [ref]$r)
  $scale = ($r.Right - $r.Left) / 700.0
  Say ("window $($r.Left),$($r.Top) $($r.Right - $r.Left)x$($r.Bottom - $r.Top) scale $scale")
  $clickX = [int]($r.Left + 636 * $scale)
  $clickY = [int]($r.Top + 506 * $scale)

  [A]::Click($clickX, $clickY)
  Start-Sleep -Seconds 2
  $after = RunValue
  Check 'one click registers the engine' ($after -eq "`"$distFull\FZones.exe`"") "value was: '$after'"

  powershell -File (Join-Path $root 'tools_shot.ps1') -Title 'FZones' -Out (Join-Path $root 'shots\fix9_autostart_on.png') | Out-Null

  [A]::Click($clickX, $clickY)
  Start-Sleep -Seconds 2
  Check 'the next click removes it again' ([string](RunValue) -eq '') "value was: '$(RunValue)'"

  powershell -File (Join-Path $root 'tools_shot.ps1') -Title 'FZones' -Out (Join-Path $root 'shots\fix9_autostart_off.png') | Out-Null
}
finally {
  foreach ($id in $pids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 600
  # Put the machine back the way it was found, whatever that was.
  if ($before) {
    New-ItemProperty -Path $runPath -Name FZones -Value $before -PropertyType String -Force | Out-Null
  } else {
    Remove-ItemProperty -Path $runPath -Name FZones -ErrorAction SilentlyContinue
  }
  Say "run value restored to: '$(RunValue)'"
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith(($dist | Resolve-Path).Path, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
}

Say ''
if ($failures -eq 0) { Say 'ALL PASS' } else { Say "$failures FAILED" }
exit [Math]::Min($failures, 1)
