
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class E {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public static string WindowsOf(string imageName) {
    StringBuilder all = new StringBuilder();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      StringBuilder t = new StringBuilder(256); GetWindowTextW(h, t, 256);
      if (t.Length == 0) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      try {
        var p = System.Diagnostics.Process.GetProcessById((int)pid);
        if (string.Equals(p.ProcessName, imageName, StringComparison.OrdinalIgnoreCase)) {
          all.Append(p.ProcessName + ":" + t.ToString() + " | ");
        }
      } catch {}
      return true;
    }, IntPtr.Zero);
    return all.ToString();
  }
}
"@
$ErrorActionPreference='Continue'
function Say($m){ Write-Output $m }

# ---- stage the deployment layout the installer produces, then clean it up at the end ----
$dist = Join-Path $PSScriptRoot '_e2e_stage'
Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item 'D:\Desktop\java\Qoder\test1\PowerToys\x64\Release\FZones.exe' $dist -Force
Copy-Item 'D:\Desktop\java\Qoder\test1\fzones-ui\build\windows\x64\runner\Release\*' $dist -Recurse -Force
Say '--- staged layout ---'
Get-ChildItem $dist | ForEach-Object { '  ' + $_.Name }

function PressEditorHotkey(){
  [E]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
  [E]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [E]::keybd_event(0xC0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [E]::keybd_event(0xC0, 0, 2, [UIntPtr]::Zero)
  [E]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
  [E]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
}

function RunCase([string]$label, [string]$engineExe, [string]$expect){
  Get-Process -Name FZones,FZonesUI -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 900
  $params = "$env:LOCALAPPDATA\FZones\FancyZones\editor-parameters.json"
  $before = if (Test-Path $params) { (Get-Item $params).LastWriteTime.Ticks } else { 0 }
  $engine = Start-Process $engineExe -PassThru
  Start-Sleep -Seconds 3
  PressEditorHotkey
  Start-Sleep -Seconds 4
  $windows = [E]::WindowsOf('FZonesUI')
  $after = if (Test-Path $params) { (Get-Item $params).LastWriteTime.Ticks } else { 0 }
  $opened = [bool]$windows
  $verdict = if (($expect -eq 'present') -eq $opened) { 'PASS' } else { 'FAIL' }
  Say ($label + '  ->  ' + $verdict)
  Say ('  windows owned by FZonesUI: ' + $(if ($windows) { $windows } else { '(none)' }))
  Say ('  editor-parameters.json rewritten: ' + ($after -ne $before))
  Get-Process -Name FZones,FZonesUI -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 900
}

# Stage 3 deleted the built-in editor, so the old "engine alone falls back" case is gone. These two
# assert both halves of the new contract instead: with a sibling UI the hotkey opens it, and with
# the sibling removed the hotkey launches nothing at all. The parameters file is still written in
# both cases -- that file is the handshake a UI reads, not a promise that one is running.
RunCase 'A . both exes side by side (the shipped layout)' "$dist\FZones.exe" 'present'

Remove-Item "$dist\FZonesUI.exe" -Force
Remove-Item "$dist\data" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$dist\flutter_windows.dll" -Force -ErrorAction SilentlyContinue
RunCase 'B . sibling UI removed (nothing should launch)' "$dist\FZones.exe" 'absent'

Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
Say ('staging dir cleaned: ' + (-not (Test-Path $dist)))
