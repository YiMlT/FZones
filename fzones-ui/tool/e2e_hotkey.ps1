
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class K {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public static IntPtr FindWindow(string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (found != IntPtr.Zero) return true;
      if (!IsWindowVisible(h)) return true;
      StringBuilder sb = new StringBuilder(256);
      GetWindowTextW(h, sb, 256);
      if (sb.ToString() == title) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@
$ErrorActionPreference='Continue'
function Say($m){ Write-Output $m }

Get-Process -Name FZones -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

Say '--- starting the engine in tray mode ---'
$engine = Start-Process 'D:\Desktop\java\Qoder\test1\PowerToys\x64\Release\FZones.exe' -PassThru
Start-Sleep -Seconds 3
Say ('engine pid ' + $engine.Id + ' alive=' + ($null -ne (Get-Process -Id $engine.Id -ErrorAction SilentlyContinue)))

function PressHotkey([bool]$win,[bool]$ctrl,[bool]$alt,[bool]$shift,[byte]$vk){
  if ($shift) { [K]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero) }
  if ($ctrl)  { [K]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero) }
  if ($alt)   { [K]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero) }
  if ($win)   { [K]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero) }
  Start-Sleep -Milliseconds 80
  [K]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [K]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
  if ($win)   { [K]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero) }
  if ($alt)   { [K]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero) }
  if ($ctrl)  { [K]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero) }
  if ($shift) { [K]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero) }
}
$editorTitle = 'FZones 布局编辑器'
function EditorOpen(){ return ([K]::FindWindow($editorTitle) -ne [IntPtr]::Zero) }
function CloseEditor(){
  $h = [K]::FindWindow($editorTitle)
  if ($h -ne [IntPtr]::Zero) { [void][K]::PostMessageW($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero); Start-Sleep -Milliseconds 1000 }
}

Say '--- step 1: fire the hotkey that is in settings.json right now (shift+win+backtick) ---'
PressHotkey $true $false $false $true 0xC0
Start-Sleep -Seconds 2
$step1 = EditorOpen
Say ('  editor opened: ' + $step1)
CloseEditor

Say '--- step 2: rewrite the hotkey to ctrl+alt+F9 with the app writer ---'
$jsonPath = "$env:TEMP\fz_hotkey.json"
Set-Content -Path $jsonPath -Value '{"win":false,"ctrl":true,"alt":true,"shift":false,"code":120,"key":"F9"}' -Encoding ASCII -NoNewline
$dart = & 'D:\Flutter\flutter\bin\dart.bat' run tool/set_setting.dart fancyzones_editor_hotkey ("@" + $jsonPath) 2>&1
Say ('  ' + ($dart -join ' | '))
Start-Sleep -Seconds 3

Say '--- step 3: the OLD hotkey must no longer do anything ---'
PressHotkey $true $false $false $true 0xC0
Start-Sleep -Seconds 2
$step3 = EditorOpen
Say ('  editor opened with the OLD hotkey: ' + $step3)
CloseEditor

Say '--- step 4: the NEW hotkey must work ---'
PressHotkey $false $true $true $false 0x78
Start-Sleep -Seconds 2
$step4 = EditorOpen
Say ('  editor opened with the NEW hotkey: ' + $step4)
CloseEditor

Get-Process -Name FZones -ErrorAction SilentlyContinue | Stop-Process -Force
Say ''
Say ('RESULT old-before=' + $step1 + '  old-after=' + $step3 + '  new-after=' + $step4)
