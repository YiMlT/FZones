# FZones

A standalone window manager: split the screen into zones you define, hold Shift while dragging a window to snap it into one, and drag the border **between two laid-out windows** to rebalance them.

[中文](README.md) | [English](README.en.md)

---

## What it is

FZones is FancyZones extracted from PowerToys into its own app. It is **two processes** that talk to each other through JSON files on disk:

| Executable | Role |
|---|---|
| `FZones.exe` | The engine. Tray icon, global hotkeys, zone drawing and snapping, the window splitter. No window of its own - it lives in the tray |
| `FZonesUI.exe` | The UI. A Flutter app for browsing and applying layouts, the layout editors, and settings |

Neither embeds the other: the UI can be replaced without rebuilding the engine. The price is that both must agree on the same JSON - that contract is the tightest constraint in this project.

---

## Features

### Zones and snapping

- **Built-in templates**: `blank` / `focus` / `columns` / `rows` / `grid` / `priority-grid`. The **zone count** and the **spacing** can be tuned per template, and each template keeps its own values
- **Custom layouts**:
  - Grid editor - split by rows and columns, merge zones, split them again, set per-row/column proportions
  - Canvas editor - place rectangles freely; edges that touch are **linked** (dragging one shared border moves every zone touching it), and double-clicking a border splits that group evenly
- Hold **Shift** while dragging a window to reveal the zones; release to snap
- **Quick layout switch**: bind a custom layout to a digit `0`-`9` in the editor, then `Win`+`Ctrl`+`Alt`+that digit applies it straight away (optionally flashing the zones once)
- Every monitor and every virtual desktop remembers which layout it is using
- Optional behaviours: open new windows on the active monitor, send an app back to the zone it last used, restore a window's original size, move windows across monitors, take over the system `Win`+arrow snapping, exclude specific apps from zoning
- Multi-monitor, per-monitor DPI scaling, and re-layout after rotation or hot-plug

### The splitter between windows

Once windows are laid out you can rebalance them like the system's own divider:

- Hold **Shift**, put the pointer on the border where two laid-out windows **touch** (within ±6px), press and drag
- The two sides trade space: whatever one gains, the other gives up, and the total stays fixed
- One-to-one is equal and opposite; one-to-many (a tall window against two stacked ones) moves every window on that border together
- **Press the same border again** (within the double-click time and within 8px of the last press) to split the group evenly
- Minimum-size protection: no side is squeezed below `max(80px, that app's own minimum track width)`. A drag that cannot finish stops at the limit rather than being refused outright
- Hovering with Shift held shows a **hint bar**: **green = this border will move**, **grey = there is a border here but it will not** (an empty zone on one side, a window spanning several zones, or a maximised / minimised / non-resizable window)
- Known limit: proportions are **not persisted** - re-applying the layout, a resolution change or an engine restart puts the windows back on the layout's own geometry

### The UI

- No native title bar: a self-drawn caption strip and an 8px corner radius (on Windows 10, where DWM ignores the corner attribute, a clipped region does it instead)
- **中文 / English** and **dark / light / follow-system**
- Every state change animates, with durations taken from one design-token set
- Settings cover: zone fill, border, highlight and number colours, number visibility, highlight opacity, the algorithm used for overlapping zones, the editor and window-switching hotkeys, the monitor-rotation hotkey, the excluded-apps list, and start-with-windows
- Window positions are remembered per role (editor vs settings); the settings page opens centred on the main page the first time
- **Closing the engine closes the UI windows** - whether it was the tray's Exit entry, a crash, or a killed process

---

## Install

1. Run `installer\dist\FZones-1.0.0-x64-setup.exe`
2. It installs to `%LOCALAPPDATA%\Programs\FZones` by default. **Per-user: no administrator rights needed**, and the folder can be changed
3. The "start with Windows" checkbox on the finish page is **off by default**; only ticking it writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\FZones`. The same switch exists in the settings page and both manage the one registry value
4. Setup stops any running copy first - both executables keep their own image mapped, so a live install cannot be replaced

Silent install:

```powershell
.\FZones-1.0.0-x64-setup.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES
```

Uninstall from Settings → Apps, or run `unins000.exe` in the install folder. It removes the autostart value and **asks** whether to delete `%LOCALAPPDATA%\FZones` (your layouts) as well; say no and they survive a reinstall.

### Where the data lives

`%LOCALAPPDATA%\FZones\FancyZones\`:

| File | Contents |
|---|---|
| `settings.json` | Engine feature toggles and hotkeys |
| `ui-settings.json` | UI theme and language - stored as **names** (`dark`, `zh`), not numbers |
| `custom-layouts.json` | Custom layouts you saved (grid and canvas) |
| `applied-layouts.json` | Which layout each monitor and virtual desktop is using |
| `layout-templates.json` | Per-template zone count and spacing (created once you change one) |
| `app-zone-history.json` | The zone each app was last in |
| `layout-hotkeys.json` | Which custom layout each digit `0`-`9` applies (created once you bind one) |
| `default-layouts.json` · `editor-parameters.json` · `last-used-virtual-desktop.json` | Per-monitor default layout, editor launch parameters, last virtual desktop |

---

## Using it

Right-click the tray icon: **Edit layouts** / **Settings** / **Exit**.

Default hotkeys (all rebindable in settings):

| Shortcut | What it does |
|---|---|
| `Win` + `Shift` + `` ` `` | Open or close the layout editor |
| `Win` + `Ctrl` + `Alt` + `0`…`9` | Apply the custom layout bound to that digit (bound from the editor's layout cards) |
| `Win` + `PageUp` / `PageDown` | Cycle between zoned windows |
| `Shift` + drag a window | Reveal zones and snap |
| `Shift` + drag the border between two windows | Move the splitter (see above) |

`FZonesUI.exe` command-line arguments - mostly for scripts and debugging: `--editor` opens the editor, `--settings` the settings page, `--app` the main page, `--grid` / `--canvas` / `--template` pick an editor page, `--dark` / `--light` and `--zh` / `--en` pin the theme and language, and `--toggle` closes the window if it was already open.

---

## Building

### Requirements

| Needed | For |
|---|---|
| Visual Studio 2022/2026 with the "Desktop development with C++" workload | The engine |
| Windows SDK | `dwmapi`, `tlhelp32`, … |
| vcpkg with an installed x64-windows triplet | wil and the other header libraries |
| Flutter SDK with Windows desktop support | The UI |
| Inno Setup 6 | Packaging |

`tools_build_installer.ps1` has **this machine's paths hard-coded** near the top; change them on a new machine:

```powershell
$flutter = "D:\Flutter\flutter\bin\flutter.bat"
$iscc    = "D:\Inno Setup 6\ISCC.exe"
$msbuild = "D:\VSCode\MSBuild\Current\Bin\MSBuild.exe"
# plus -p:VcpkgRoot=D:\tools\vcpkg-fz\ on the MSBuild command line
```

### One command

```powershell
cd <repo root>
powershell -File tools_build_installer.ps1
```

It builds the engine with MSBuild, builds the UI with `flutter build windows --release`, then packs with ISCC. Output: `installer\dist\FZones-1.0.0-x64-setup.exe`.

Switches: `-SkipCompile` repacks without compiling anything, `-SkipUi` keeps the current Flutter output.

### Step by step

Engine, from `PowerToys\`:

```powershell
VCPKG_FORCE_SYSTEM_BIN=1 "<MSBuild>" `
  src/modules/fancyzones/FZones/FZones.vcxproj `
  -p:Configuration=Release -p:Platform=x64 `
  "-p:VcpkgRoot=<vcpkg root>\\" `
  "-p:SolutionDir=<repo root>\PowerToys\\" -m
```

Output: `PowerToys\x64\Release\FZones.exe`.

UI, from `fzones-ui\`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

Output: `fzones-ui\build\windows\x64\runner\Release\` (`FZonesUI.exe` + `flutter_windows.dll` + `data\`).

Packaging:

```powershell
cd installer
"<ISCC.exe>" /Q fzones.iss
```

### Known traps

- **`LNK1201 error writing program database … FZones.pdb`** is usually **not** disk space here. The cause is the `FZones.pdb` left by the previous link (or a lingering `mspdbsrv`) holding the file. Delete `PowerToys\x64\Release\FZones.pdb`, kill `mspdbsrv.exe` if one is running, and build again. A failed link **deletes the old FZones.exe without writing a new one**, so do not assume the output is still there
- **Building a single `.vcxproj` requires `-p:SolutionDir`**: native projects import NuGet packages through `..\..\..\..\packages\`, so without it the restore scatters packages into the project folder and the build dies at `EnsureNuGetPackageBuildImports`
- **`VcpkgRoot` must be passed explicitly** - there is no `deps/vcpkg` in this tree
- **"The Dart compiler exited unexpectedly" when the system drive is nearly full**: the real error is `%TEMP%` running out. Point `TMP`/`TEMP` at a drive with room
- **`installer/fzones.iss` must be UTF-8 with a BOM** or the Chinese custom messages arrive mangled; `tools_build_installer.ps1` re-applies the BOM before every pack
- Calling PowerShell as a one-liner from Git Bash eats `$` before PowerShell sees it - put it in a `.ps1` file

---

## Repository layout

```
.
├─ PowerToys/                     Engine (C++/Win32, only what FZones depends on)
│  ├─ src/modules/fancyzones/
│  │  ├─ FancyZonesLib/           Core: layouts, zones, snapping, splitter geometry
│  │  └─ FZones/                  Engine main, tray, app-side settings
│  ├─ src/common/                 Logging, settings API, DPI, hooks
│  ├─ packages/                   NuGet restore target (referenced by the build - keep)
│  ├─ vcpkg_installed/            vcpkg restore output (referenced by the build - keep)
│  └─ x64/Release/FZones.exe     [generated] engine, one of the two payloads
├─ fzones-ui/                     UI (Flutter)
│  ├─ lib/                        Main page, editors, settings, design tokens, strings
│  ├─ windows/runner/             Frameless shell: hit-testing, rounding, placement, engine follow
│  ├─ test/                       Widget and unit tests (flutter test)
│  ├─ tool/                       End-to-end scripts (need a machine that can send global hotkeys)
│  └─ build/windows/x64/runner/Release/  [generated] UI payload, the other half of the package
├─ installer/
│  ├─ fzones.iss                  Inno Setup script (the only packer)
│  └─ dist/FZones-1.0.0-x64-setup.exe    [generated] the installer
├─ tools_build_installer.ps1      Build and pack entry point
├─ tools_make_icon.ps1            Generates the icons (writes two .ico files, both compiled in)
└─ README.md / README.en.md       This file
```

## Not in this cut

- **Persisting splitter proportions.** A drag holds until the layout is recomputed. Keeping them means the engine starting to write `custom-layouts.json` (today only the UI writes it), which is a contract change with its own tests
- **A resize cursor over the border** - only the hint bar
- A C++ unit-test project for the engine. The splitter's geometry is deliberately pure functions so it can be reasoned about without a desktop; the UI's tests live in `fzones-ui/test/`
