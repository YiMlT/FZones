
# Checks the whole loop the activation hotkey drives: an editor window that the engine did not
# start must still close when the user presses it again.
#
#   flutter build windows --release                  # and FZones.exe built
#   powershell -File tool\e2e_toggle_closes_editor.ps1
#
# The engine only tracks the child process it launched, so it cannot tell an editor it started from
# one started by hand - it always launches `--editor --toggle` and lets the runner's single-instance
# guard decide. This script is the half that only the two together can show.
#
# It fires the same named event the tray menu item does rather than synthesising the global hotkey:
# both land in FancyZones::ToggleEditor(), and the event cannot be swallowed by another app.
# LOCALAPPDATA is staged for the UI - FzPaths reads the variable - but the engine resolves the
# folder through the shell API, so it still refreshes editor-parameters.json in the real profile.
# That file is the engine's own handshake and it rewrites the process-id on every editor launch;
# nothing else in there is touched, and nothing the UI reads is decision-bearing.
# The clean-up only ever reaches a process whose image path is inside the staging directory, so it
# can never touch an install of the user's own.
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class T {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr OpenEventW(uint access, bool inherit, string name);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CreateEventW(IntPtr sa, bool manual, bool state, string name);
  [DllImport("kernel32.dll")] public static extern bool SetEvent(IntPtr h);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public static int Count(string title) {
    int n = 0;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      StringBuilder t = new StringBuilder(256); GetWindowTextW(h, t, 256);
      if (t.ToString() == title) n++;
      return true;
    }, IntPtr.Zero);
    return n;
  }
}
"@
$ErrorActionPreference = 'Continue'
function Say($m) { Write-Output $m }

$toggle_event = 'Local\FancyZones-ToggleEditorEvent-1e174338-06a3-472b-874d-073b21c62f14'
$editor_title = 'FZones 布局编辑器'
$root = 'D:\Desktop\java\Qoder\test1'
$dist = Join-Path $PSScriptRoot '_e2e_toggle'
$failures = 0
$pids = @()

function Check($name, $ok, $detail) {
  if ($ok) { Say "PASS  $name" } else { $script:failures++; Say "FAIL  $name - $detail" }
}
function Wait-For([scriptblock]$test, [int]$tries = 24) {
  for ($i = 0; $i -lt $tries; $i++) {
    if (& $test) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return $false
}
function Press-Toggle {
  # The tray's own two steps: open what the engine created, and signal it.
  $h = [T]::OpenEventW(0x2, $false, $toggle_event)
  if ($h -eq [IntPtr]::Zero) { $h = [T]::CreateEventW([IntPtr]::Zero, $false, $false, $toggle_event) }
  if ($h -eq [IntPtr]::Zero) { return $false }
  $ok = [T]::SetEvent($h)
  [void][T]::CloseHandle($h)
  return $ok
}

$engine_src = Join-Path $root 'PowerToys\x64\Release\FZones.exe'
$ui_src = Join-Path $root 'fzones-ui\build\windows\x64\runner\Release'
if (-not (Test-Path $engine_src)) { Say "ABORT  no engine at $engine_src"; exit 2 }
if (-not (Test-Path (Join-Path $ui_src 'FZonesUI.exe'))) { Say 'ABORT  no release UI build'; exit 2 }
if (Get-Process -Name FZones -ErrorAction SilentlyContinue) {
  Say 'ABORT  an engine is already running - it holds the instance mutex and the hotkeys.'
  exit 2
}
if ([T]::Count($editor_title) -gt 0) {
  Say 'ABORT  an editor window is already open. Close it first; this script stops nothing it did not start.'
  exit 2
}

Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item $engine_src $dist -Force
Copy-Item (Join-Path $ui_src '*') $dist -Recurse -Force
$env:LOCALAPPDATA = Join-Path $dist 'appdata'
New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null

try {
  $engine = Start-Process (Join-Path $dist 'FZones.exe') -PassThru
  $pids += $engine.Id
  Start-Sleep -Seconds 3
  Check 'the engine is up' (-not $engine.HasExited) 'it exited straight away'

  # An editor the engine knows nothing about - started by hand, exactly the case it used to be
  # unable to close.
  $hand = Start-Process (Join-Path $dist 'FZonesUI.exe') -ArgumentList '--editor' -PassThru
  $pids += $hand.Id
  Check 'a hand-started editor opens' (Wait-For { [T]::Count($editor_title) -eq 1 }) "found $([T]::Count($editor_title))"

  Check 'the toggle event fires' (Press-Toggle) 'SetEvent failed'
  $closed = Wait-For { [T]::Count($editor_title) -eq 0 }
  Check 'the hotkey closes an editor the engine did not start' $closed "still $([T]::Count($editor_title)) window(s)"

  # ---- the two paths that already worked must still work ----
  [void](Press-Toggle)
  Check 'with nothing open the hotkey opens the editor' (Wait-For { [T]::Count($editor_title) -eq 1 }) 'nothing opened'
  [void](Press-Toggle)
  Check 'and closes the one it started itself' (Wait-For { [T]::Count($editor_title) -eq 0 }) "still $([T]::Count($editor_title)) window(s)"

  [void](Press-Toggle)
  Check 'the toggle still opens it a second time' (Wait-For { [T]::Count($editor_title) -eq 1 }) 'nothing opened'
}
finally {
  # The last toggle leaves an editor running that *the engine* started, so it is not in $pids -
  # and while it holds the staged exe open, the staging directory cannot be deleted. Matching on
  # the image path is what makes this safe: it can only ever reach a process started from here.
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($dist, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force -ErrorAction SilentlyContinue
  foreach ($id in $pids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
  $cleaned = $false
  for ($i = 0; $i -lt 12 -and -not $cleaned; $i++) {
    Start-Sleep -Milliseconds 400
    Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
    $cleaned = -not (Test-Path $dist)
  }
  Say "staging dir cleaned: $cleaned"
}

Say ''
if ($failures -eq 0) { Say 'ALL PASS' } else { Say "$failures FAILED" }
exit [Math]::Min($failures, 1)
