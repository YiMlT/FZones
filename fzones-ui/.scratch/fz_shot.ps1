$ErrorActionPreference = 'Stop'
$root = 'D:\Desktop\java\Qoder\test1'
$real = $env:LOCALAPPDATA
$data = Join-Path $root '.scratch\view'
$dir  = Join-Path $data 'FZones\FancyZones'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
foreach ($n in 'editor-parameters.json','custom-layouts.json','layout-hotkeys.json') {
  $src = Join-Path $real "FZones\FancyZones\$n"
  if (Test-Path $src) { Copy-Item $src $dir -Force }
}
$sig = @'
using System;
using System.Runtime.InteropServices;
public static class W5 {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
}
'@
Add-Type -TypeDefinition $sig
[void][W5]::SetProcessDpiAwarenessContext([IntPtr](-4))
$env:LOCALAPPDATA = $data
$p = Start-Process -FilePath (Join-Path $root 'fzones-ui\build\windows\x64\runner\Release\FZonesUI.exe') -ArgumentList '--editor' -PassThru
Start-Sleep -Seconds 5
[void][W5]::MoveWindow([IntPtr]$p.MainWindowHandle, 20, 20, 1320, 1720, $true)
Start-Sleep -Seconds 2
powershell -File (Join-Path $root 'tools_shot.ps1') -Title 'FZones' -Out (Join-Path $root 'shots\fix10_editor.png')
Stop-Process -Id $p.Id -Force
