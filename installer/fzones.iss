; FZones - per-user installer, Inno Setup edition.
;
; Follows the modern Windows wizard. The contract it implements - where the
;   FZones.exe    the always-resident engine: tray icon, hotkeys, zone overlays.
;   FZonesUI.exe  the Flutter settings window and layout editor, launched on demand.
; They talk over the JSON files in %LOCALAPPDATA%\FZones, so the UI is just a sibling exe and only
; the folder name has to stay in sync. Autostart covers the engine only; the UI is never resident.
;
; Build:  "D:\Inno Setup 6\ISCC.exe" installer\fzones.iss
;       (or tools_build_installer.ps1, which builds both payloads first)
;
; Three writers of the autostart value name: here, RUN_VALUE in the engine's AppSettings.cpp, and
; kRunValue in fzones-ui/windows/runner/flutter_window.cpp. fzones-ui/test/autostart_test.dart reads
; all three and compares them, because a mismatch means each manages a different entry silently.

#define AppName "FZones"
#define AppVersion "1.0.0"
#define ExeEngine "FZones.exe"
#define ExeUi "FZonesUI.exe"
#define RunValue "FZones"
#define PayloadEngine "..\PowerToys\x64\Release\FZones.exe"
#define PayloadUi "..\fzones-ui\build\windows\x64\runner\Release"
#define AppIcon "..\PowerToys\src\modules\fancyzones\FancyZonesLib\icon.ico"

[Setup]
AppId={#AppName}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppName}
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
DisableProgramGroupPage=yes
; The welcome page is what the NSIS build had; turning it back off would make the two installs
; differ in steps as well as in looks.
DisableWelcomePage=no
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Inno's solid LZMA2 gets the Flutter bundle down; the NSIS build shipped at ~9.3 MB.
Compression=lzma2/ultra64
SolidCompression=yes
OutputDir=dist
; The shipping name, same as the NSIS build's: one artefact per run, and the smoke test plus any
; link to it stay put whichever packer was used.
OutputBaseFilename={#AppName}-{#AppVersion}-x64-setup
UninstallDisplayIcon={app}\{#ExeEngine}
SetupIconFile={#AppIcon}
; No admin prompt, ever: everything this app touches is per-user.
WizardStyle=modern
CloseApplications=no
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "zh"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
; Unchecked on purpose, exactly like the NSIS finish-page box: a silent install must write nothing
; to the sign-in run key, and the settings page is what owns the toggle afterwards.
Name: "autostart"; Description: "{cm:AutostartTask}"; Flags: unchecked

[CustomMessages]
en.AutostartTask=Start automatically at sign-in
zh.AutostartTask=开机自动启动
en.KeepDataMsg=Also delete your layouts and settings?%n%n{localappdata}\FZones%n%nChoose No to keep them.
zh.KeepDataMsg=是否同时删除布局与设置数据？%n%n{localappdata}\FZones%n%n选择“否”会保留你的布局。

[Files]
Source: "{#PayloadEngine}"; DestDir: "{app}"; DestName: "{#ExeEngine}"; Flags: ignoreversion
; The Flutter tree's shape belongs to the SDK, so take all of it rather than a list that the next
; Flutter version would silently invalidate.
Source: "{#PayloadUi}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\{#AppName}"; Filename: "{app}\{#ExeEngine}"; IconFilename: "{app}\{#ExeEngine}"

[Run]
Filename: "{app}\{#ExeEngine}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

[Code]
// Both exes keep their own image mapped while running, so an upgrade over a live install would
// leave the old files behind.
procedure KillRunning;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM ' + '{#ExeEngine}' + ' /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM ' + '{#ExeUi}' + ' /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    KillRunning;
    if WizardIsTaskSelected('autostart') then
      // Quoted full path, the same string the settings-page toggle writes.
      RegWriteStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run',
        '{#RunValue}', '"' + ExpandConstant('{app}\{#ExeEngine}') + '"')
    else
      RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#RunValue}');
  end;
end;

function InitializeUninstall(): Boolean;
begin
  KillRunning;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#RunValue}');
    // UninstallSilent, not WizardSilent: the Wizard* functions belong to Setup's wizard, and calling
    // one from uninstall code aborts the rest of this step with
    // "Cannot call "WizardSilent" function during Uninstall".
    // Never prompt during /SILENT, and never delete layouts without asking when somebody is
    // watching - the same rule the NSIS uninstaller follows.
    if not UninstallSilent then
      if MsgBox(CustomMessage('KeepDataMsg'), mbConfirmation, MB_YESNO) = IDYES then
        DelTree(ExpandConstant('{localappdata}\FZones'), True, True, True);
  end;
end;
