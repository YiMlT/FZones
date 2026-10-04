
# Checks the runner's single-instance guard: one window per role, and a second launch of the same
# exe raises the window that is already open instead of opening another one. The roles are the
# layout editor and the settings page, which share this one executable.
#
#   flutter build windows --release      # then:
#   powershell -File tool\e2e_single_instance.ps1
#
# LOCALAPPDATA is redirected into a staging folder, so the engine's real data directory is never
# read or written. Nothing here kills a window it did not open: an editor left running by hand
# would make every count wrong, so the script says so and stops instead.
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class I {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string title);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  // Every top-level window whose title matches, whatever process owns it.
  public static int Count(string title) {
    int n = 0;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      StringBuilder t = new StringBuilder(256); GetWindowTextW(h, t, 256);
      if (t.ToString() == title) n++;
      return true;
    }, IntPtr.Zero);
    return n;
  }
  public static IntPtr First(string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      StringBuilder t = new StringBuilder(256); GetWindowTextW(h, t, 256);
      if (t.ToString() == title) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@
$ErrorActionPreference = 'Continue'
function Say($m) { Write-Output $m }

$editor_title  = 'FZones 布局编辑器'
$settings_title = 'FZones 设置'
$exe = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\FZonesUI.exe'
$staged = Join-Path $PSScriptRoot '_e2e_instance'
$failures = 0
$pids = @()

function Check($name, $ok, $detail) {
  if ($ok) { Say "PASS  $name" } else { $script:failures++; Say "FAIL  $name - $detail" }
}
function Start-Ui {
  param([string[]]$Arguments)
  # `$args` is a PowerShell automatic variable, and Start-Process rejects an empty ArgumentList,
  # so the settings role - which takes no arguments at all - starts without the parameter.
  $command = @{ FilePath = $exe; PassThru = $true }
  if ($Arguments) { $command['ArgumentList'] = $Arguments }
  $p = Start-Process @command
  $script:pids += $p.Id
  return $p
}
function Wait-Window($title) {
  for ($i = 0; $i -lt 40; $i++) {
    if ([I]::First($title) -ne [IntPtr]::Zero) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return $false
}

# Start-Process' -PassThru object reports no ExitCode once its stdout has been redirected, and a
# bare `exit code ` is the worst possible test failure to read. The .NET process API keeps both.
function Start-UiCaptured {
  param([string[]]$Arguments)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  if ($Arguments) { $psi.Arguments = ($Arguments -join ' ') }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  $script:pids += $proc.Id
  $text = $proc.StandardOutput.ReadToEnd()
  if (-not $proc.WaitForExit(8000)) { return @{ Code = -1; Text = $text } }
  return @{ Code = $proc.ExitCode; Text = $text }
}

if (-not (Test-Path $exe)) { Say "ABORT  no release build at $exe"; exit 2 }
if ([I]::Count($editor_title) -gt 0 -or [I]::Count($settings_title) -gt 0) {
  Say 'ABORT  an FZones window is already open - close it first, or every count below is wrong.'
  exit 2
}

New-Item -ItemType Directory -Force -Path $staged | Out-Null
$env:LOCALAPPDATA = $staged

try {
  # ---- 1. a second editor launch raises the first instead of opening a second window ----
  $e1 = Start-Ui -Arguments '--editor'
  Check 'the first editor opens' (Wait-Window $editor_title) 'no window appeared'
  $second = Start-UiCaptured -Arguments '--editor'
  # An exit that is not EXIT_SUCCESS is a crash, and a crash raises nothing. The line it printed is
  # what makes the code path unambiguous: only the guard writes it.
  Check 'a second editor launch exits successfully' ($second.Code -eq 0) "exit code $($second.Code)"
  Check 'and it says what it did' ($second.Text -match 'already open') "output was: '$($second.Text)'"
  Start-Sleep -Seconds 1
  Check 'still exactly one editor window' ([I]::Count($editor_title) -eq 1) "found $([I]::Count($editor_title))"

  # ---- 2. the settings role is its own instance, and guards itself the same way ----
  $s1 = Start-Ui
  Check 'the settings window opens' (Wait-Window $settings_title) 'no window appeared'
  $s2 = Start-Ui
  Check 'a second settings launch ends on its own' ($s2.WaitForExit(5000) -and $s2.ExitCode -eq 0) "still running, or exit code $($s2.ExitCode)"
  Start-Sleep -Seconds 1
  Check 'still exactly one settings window' ([I]::Count($settings_title) -eq 1) "found $([I]::Count($settings_title))"
  Check 'the editor and the settings page coexist' (([I]::Count($editor_title) -eq 1) -and ([I]::Count($settings_title) -eq 1)) 'one of them is gone'

  # ---- 3. raising works from a minimised window ----
  $hwnd = [I]::First($editor_title)
  # A minimize the target thread has not gotten to yet is a precondition, not a result, so wait
  # for it rather than losing the run over it.
  $minimised = $false
  for ($i = 0; $i -lt 12; $i++) {
    [void][I]::ShowWindow($hwnd, 6)   # SW_MINIMIZE
    Start-Sleep -Milliseconds 250
    if ([I]::IsIconic($hwnd)) { $minimised = $true; break }
  }
  Check 'the editor is minimised for the test' $minimised 'it never minimised'
  $e3 = Start-Ui -Arguments '--editor'
  Check 'a launch while minimised ends on its own' ($e3.WaitForExit(5000) -and $e3.ExitCode -eq 0) "still running, or exit code $($e3.ExitCode)"
  Start-Sleep -Seconds 1
  $again = [I]::First($editor_title)
  Check 'the minimised editor came back up' (-not [I]::IsIconic($again)) 'still minimised'
  Check 'and it is still one window' ([I]::Count($editor_title) -eq 1) "found $([I]::Count($editor_title))"

  # ---- 4. closing releases the lock, so the next launch gets a window ----
  Stop-Process -Id $e1.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  Check 'the closed editor is gone' ([I]::Count($editor_title) -eq 0) "found $([I]::Count($editor_title))"
  $e4 = Start-Ui -Arguments '--editor'
  Check 'after the editor is closed a new one opens' (Wait-Window $editor_title) 'no window appeared'
  Check 'and it is the only one' ([I]::Count($editor_title) -eq 1) "found $([I]::Count($editor_title))"

  # ---- 5. `--toggle`, which is what the engine's hotkey and the tray now pass ----
  # The engine only tracks the child it launched. When the window came from somewhere else the
  # launch lands on this guard instead, and `--toggle` is what makes it a close rather than a raise.
  $toggled = Start-UiCaptured -Arguments '--editor', '--toggle'
  Check 'a toggle launch exits successfully' ($toggled.Code -eq 0) "exit code $($toggled.Code)"
  Check 'and it says it closed rather than raised' ($toggled.Text -match 'closed it instead') "output was: '$($toggled.Text)'"
  for ($i = 0; $i -lt 20; $i++) {
    if ([I]::Count($editor_title) -eq 0) { break }
    Start-Sleep -Milliseconds 250
  }
  Check 'the editor window the toggle found is gone' ([I]::Count($editor_title) -eq 0) "found $([I]::Count($editor_title))"

  # ---- 6. a toggle with nothing open is just an open ----
  [void](Start-Ui -Arguments '--editor', '--toggle')
  Check 'a toggle with no window open still opens one' (Wait-Window $editor_title) 'no window appeared'
  Check 'and it is the only one' ([I]::Count($editor_title) -eq 1) "found $([I]::Count($editor_title))"

  # ---- 7. the settings role closes the same way; the gear never sends the flag ----
  $s3 = Start-UiCaptured -Arguments '--toggle'
  Check 'a toggle closes the settings window too' ($s3.Code -eq 0 -and $s3.Text -match 'closed it instead') "exit $($s3.Code), output '$($s3.Text)'"
  for ($i = 0; $i -lt 20; $i++) {
    if ([I]::Count($settings_title) -eq 0) { break }
    Start-Sleep -Milliseconds 250
  }
  Check 'the settings window is gone' ([I]::Count($settings_title) -eq 0) "found $([I]::Count($settings_title))"
  # Open it again, so the next line tests a launch that *does* find a window: without one the
  # guard opens a window and prints nothing, which would make the assertion below pass by accident.
  [void](Start-Ui)
  Check 'the settings window opens again' (Wait-Window $settings_title) 'no window appeared'
  $plain = Start-UiCaptured
  Check 'a plain second settings launch raises instead' ($plain.Code -eq 0 -and $plain.Text -match 'raised it instead') "exit $($plain.Code), output '$($plain.Text)'"
  Start-Sleep -Seconds 1
  Check 'and the settings window is still one' ([I]::Count($settings_title) -eq 1) "found $([I]::Count($settings_title))"
}
finally {
  foreach ($id in $pids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 500
  if (Test-Path $staged) { Remove-Item $staged -Recurse -Force -ErrorAction SilentlyContinue }
}

Say ''
if ($failures -eq 0) { Say 'ALL PASS' } else { Say "$failures FAILED" }
exit [Math]::Min($failures, 1)
