# Builds both halves of FZones and packs them into installer\dist\FZones-<version>-x64-setup.exe.
#   tools_build_installer.ps1              full build (native engine + Flutter UI + Inno Setup)
#   tools_build_installer.ps1 -SkipUi      keep the current Flutter build, rebuild the rest
#   tools_build_installer.ps1 -SkipCompile skip every compile, just repack
param([switch]$SkipCompile, [switch]$SkipUi)
$ErrorActionPreference = "Stop"

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo    = Join-Path $root "PowerToys"
$ui      = Join-Path $root "fzones-ui"
$exe     = Join-Path $repo "x64\Release\FZones.exe"
$uiExe   = Join-Path $ui "build\windows\x64\runner\Release\FZonesUI.exe"
$flutter = "D:\Flutter\flutter\bin\flutter.bat"
$iscc    = "D:\Inno Setup 6\ISCC.exe"
$msbuild = "D:\VSCode\MSBuild\Current\Bin\MSBuild.exe"

# Both processes keep their exe mapped while running, and a link step cannot replace a locked file.
foreach ($name in @("FZones", "FZonesUI")) {
  Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force
}
Start-Sleep -Milliseconds 500

if (-not $SkipCompile) {
  if (-not (Test-Path $msbuild)) { throw "MSBuild not found at $msbuild" }
  Push-Location $repo
  # No -m, no file tracker, no CL server: all three spawn helper processes over named pipes, which
  # a confined shell denies. Sequential is slower but is the one form that runs everywhere.
  & $msbuild "src\modules\fancyzones\FZones\FZones.vcxproj" `
    -nologo "-p:Configuration=Release" -p:Platform=x64 `
    "-p:VcpkgRoot=D:\tools\vcpkg-fz\\" "-p:SolutionDir=$repo\" `
    -p:TrackFileAccess=false -p:UseSharedCompilation=false -v:minimal -clp:ErrorsOnly
  $code = $LASTEXITCODE
  Pop-Location
  if ($code -ne 0) { throw "MSBuild failed with exit code $code" }
}

if ((-not $SkipCompile) -and (-not $SkipUi)) {
  if (-not (Test-Path $flutter)) { throw "flutter not found at $flutter" }
  Push-Location $ui
  # --release AOT-compiles data\app.so; the bundle it drops (FZonesUI.exe + flutter_windows.dll
  # + data\) is exactly what the installer ships, so the two never drift.
  & $flutter build windows --release
  $code = $LASTEXITCODE
  Pop-Location
  if ($code -ne 0) { throw "flutter build failed with exit code $code" }
}

if (-not (Test-Path $iscc)) { throw "ISCC.exe not found at $iscc" }

# Half a payload is worse than none: check both before either packer runs.
foreach ($payload in @($exe, $uiExe)) {
  if (-not (Test-Path $payload)) { throw "no payload at $payload" }
}

# ISCC resolves the payload paths relative to the script's own folder as well as the caller's cwd,
# so run it from installer\ with a bare file name.
Push-Location (Join-Path $root "installer")
New-Item -ItemType Directory -Force -Path "dist" | Out-Null
# UTF-8 with a BOM, for the Chinese custom messages - re-applied here because an editor or a
# scripted edit can drop it without anyone noticing.
$iss = (Resolve-Path "fzones.iss").Path
[IO.File]::WriteAllText($iss, [IO.File]::ReadAllText($iss, [Text.Encoding]::UTF8), (New-Object Text.UTF8Encoding $true))
& $iscc /Q "fzones.iss"
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { throw "ISCC failed with exit code $code" }

Get-ChildItem (Join-Path $root "installer\dist") | ForEach-Object {
  Write-Output ("{0}  {1:N0} KB" -f $_.FullName, ($_.Length / 1KB))
}
