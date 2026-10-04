# FZones

独立的窗口分区工具：把屏幕切成可自定义的区域，拖窗口时按住 Shift 即可吸附，还能直接拖动**两个已排布窗口之间**的那条边界来重新分配空间。

[中文](README.md) | [English](README.en.md)

---

## 它是什么

FZones 是 FancyZones 从 PowerToys 里剥离出来的独立版本，由**两个进程**组成，彼此通过磁盘上的 JSON 文件通信：

| 可执行文件 | 角色 |
|---|---|
| `FZones.exe` | 引擎。托盘、全局热键、区域绘制与吸附、窗口间分割条。没有窗口，常驻托盘 |
| `FZonesUI.exe` | 界面。Flutter 写的布局浏览/编辑器与设置页 |

两者互不内嵌：换界面不用重编引擎，引擎崩了也不带走界面。代价是它们必须对同一份 JSON 达成一致——这个契约是本项目最重要的约束。

---

## 功能

### 分区与吸附

- **内置模板**：`blank` / `focus` / `columns` / `rows` / `grid` / `priority-grid`。每个模板的**区域数量**和**间距**可以单独调整，互不影响
- **自定义布局**：
  - 网格编辑器——按行/列切分，支持合并区域、拆分区域、行列比例
  - 画布编辑器——自由摆放矩形；贴着的边界会**联动**（拖动一条公共边，所有贴着它的区域一起动），双击某条边界则把这一组空间均分
- 按住 **Shift** 拖动窗口时显示区域，松手吸附到对应区域
- **快速切换布局**：在编辑器里把某个自定义布局绑到数字 `0`–`9`，之后 `Win`+`Ctrl`+`Alt`+该数字直接套用（可设置在切换时闪显一次区域）
- 每个显示器、每个虚拟桌面各自记住自己套用的布局
- 可选行为：新窗口开到当前活动显示器、把窗口送回它上次所在的区域、恢复窗口原始尺寸、跨显示器移动窗口、接管系统 `Win`+方向键的贴边行为、排除指定应用不参与分区
- 支持多显示器、每显示器不同 DPI 缩放、显示器旋转/热插拔后重算布局

### 窗口间分割条

布局套好之后，还可以像系统分屏那样调两侧比例：

- 按住 **Shift**，把指针放到两个已排布窗口**相接的那条边界**上（±6px 内），按下并拖动
- 两侧互相让位：一侧得到多少，另一侧就失去多少，总宽度不变
- 一对一等量反向；一对多（左边一个窗口、右边两个上下叠放）时，右侧两个窗口一起动
- 在**同一条边界上再按一次**（系统双击节奏内、且指针没离开 8px）→ 这一组空间均分
- 最小尺寸保护：任何一侧都不会被压到 `max(80px, 该应用自身的最小轨道宽度)` 以下；拖到极限时边界会停住而不是整段拒绝
- 按住 Shift 悬停时有**提示线**：**绿色 = 这条能拖**，**灰色 = 这里确实有边界但不会动**（那一侧空着、窗口跨了多个区域、或窗口处于最大化/最小化/不可调尺寸）
- 已知限制：比例**不持久**——重新套用布局、改分辨率或重启引擎后，窗口会回到布局自身定义的比例

### 界面

- 没有系统标题栏：自绘标题带 + 8px 圆角（Windows 10 上 DWM 不认圆角属性，改用区域裁剪）
- **中文 / English** 双语，**深色 / 浅色 / 跟随系统**三态
- 所有状态变化都带动效，时长取自统一的设计令牌
- 设置页可改：区域颜色、边框色、高亮色、编号颜色与开关、高亮不透明度、重叠区域的判定算法、编辑器与窗口切换热键、显示器旋转热键、排除的应用列表、开机自动启动
- 窗口位置会被记住（按"编辑器/设置页"分别记），设置页第一次打开时居中在主页之上
- **引擎退出后界面窗口自动关闭**（托盘菜单的"退出"、崩溃、被结束进程都算）

---

## 安装

1. 运行 `installer\dist\FZones-1.0.0-x64-setup.exe`
2. 默认装到 `%LOCALAPPDATA%\Programs\FZones`。**per-user 安装，不需要管理员权限**，可以改安装目录
3. 完成页的"开机自动启动"**默认不勾选**；勾上才写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\FZones`。这个开关在设置页里也有，两边管的是同一条注册表值
4. 安装时会结束正在运行的旧版本（两个 exe 都会把映像映射在内存里，不结束就换不掉文件）

静默安装：

```powershell
.\FZones-1.0.0-x64-setup.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES
```

卸载：控制面板 → 应用，或运行安装目录里的 `unins000.exe`。卸载会清掉自启项，并**询问**是否连同 `%LOCALAPPDATA%\FZones`（你的布局数据）一起删除——不选删除的话布局会留着，重装后还在。

### 数据放在哪

`%LOCALAPPDATA%\FZones\FancyZones\`：

| 文件 | 内容 |
|---|---|
| `settings.json` | 引擎侧的功能开关与热键 |
| `ui-settings.json` | 界面侧的主题与语言（存的是 `dark` / `zh` 这样的**名字**，不是数字） |
| `custom-layouts.json` | 你保存的自定义布局（网格与画布两种） |
| `applied-layouts.json` | 每个显示器 + 每个虚拟桌面当前套用的是哪个布局 |
| `layout-templates.json` | 每个内置模板各自的区域数量与间距（调过才会生成） |
| `app-zone-history.json` | 应用上次所在的区域 |
| `layout-hotkeys.json` | 数字键 `0`–`9` 各绑定哪个自定义布局（绑过才生成） |
| `default-layouts.json` · `editor-parameters.json` · `last-used-virtual-desktop.json` | 每显示器的默认布局、编辑器启动参数、上次使用的虚拟桌面 |

---

## 使用

托盘图标右键菜单：**编辑布局** / **设置** / **退出**。

默认热键（都可在设置页改）：

| 快捷键 | 作用 |
|---|---|
| `Win` + `Shift` + `` ` `` | 打开/关闭布局编辑器 |
| `Win` + `Ctrl` + `Alt` + `0`…`9` | 套用绑到该数字的自定义布局（绑定在编辑器的布局卡片上做） |
| `Win` + `PageUp` / `PageDown` | 在已排布的窗口间切换 |
| `Shift` + 拖动窗口 | 显示区域并吸附 |
| `Shift` + 拖动两窗口之间的边界 | 调整分割条（见上文） |

`FZonesUI.exe` 的命令行参数（主要给脚本和调试用）：`--editor` 直接进编辑器、`--settings` 打开设置页、`--app` 显示主页、`--grid` / `--canvas` / `--template` 指定进哪一页、`--dark` / `--light` 与 `--zh` / `--en` 钉住主题和语言、`--toggle` 让已经开着的窗口关掉。

---

## 构建

### 依赖

| 需要 | 说明 |
|---|---|
| Visual Studio 2022/2026 + "使用 C++ 的桌面开发" 工作负载 | 编引擎 |
| Windows SDK | 需要 `dwmapi`、`tlhelp32` 等 |
| vcpkg（含已装好的 x64-windows triplet） | 提供 wil 等头文件库 |
| Flutter SDK（Windows 桌面支持） | 编界面 |
| Inno Setup 6 | 打包 |

`tools_build_installer.ps1` 顶部**写死了本机路径**，换机器要改这几行：

```powershell
$flutter = "D:\Flutter\flutter\bin\flutter.bat"
$iscc    = "D:\Inno Setup 6\ISCC.exe"
$msbuild = "D:\VSCode\MSBuild\Current\Bin\MSBuild.exe"
# 以及命令行参数里的 -p:VcpkgRoot=D:\tools\vcpkg-fz\
```

### 一条命令

```powershell
cd <仓库根目录>
powershell -File tools_build_installer.ps1
```

依次做三件事：MSBuild 编引擎 → `flutter build windows --release` 编界面 → ISCC 打包，产物在 `installer\dist\FZones-1.0.0-x64-setup.exe`。

开关：`-SkipCompile` 跳过所有编译只重打包、`-SkipUi` 保留现有界面产物。

### 分步

引擎（在 `PowerToys\` 下执行）：

```powershell
VCPKG_FORCE_SYSTEM_BIN=1 "<MSBuild>" `
  src/modules/fancyzones/FZones/FZones.vcxproj `
  -p:Configuration=Release -p:Platform=x64 `
  "-p:VcpkgRoot=<vcpkg 根>\\" `
  "-p:SolutionDir=<仓库根>\PowerToys\\" -m
```

产物 `PowerToys\x64\Release\FZones.exe`。

界面（在 `fzones-ui\` 下）：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

产物 `fzones-ui\build\windows\x64\runner\Release\`（`FZonesUI.exe` + `flutter_windows.dll` + `data\`）。

打包：

```powershell
cd installer
"<ISCC.exe>" /Q fzones.iss
```

### 会踩到的坑

- **`LNK1201 写入程序数据库 … FZones.pdb 时出错`**：通常**不是磁盘空间**。原因是上一次链接留下的 `FZones.pdb`（或一个残留的 `mspdbsrv`）占着文件。先 `del PowerToys\x64\Release\FZones.pdb`、必要时结束 `mspdbsrv.exe`，再编一次。失败的链接会**删掉旧的 FZones.exe 而不写新的**，所以别以为产物还在
- **单独构建某个 `.vcxproj` 必须传 `-p:SolutionDir`**：原生工程按 `..\..\..\..\packages\` 这种相对路径导入 NuGet，路径不对会在 `EnsureNuGetPackageBuildImports` 处失败，而且包会被散落到工程自己目录下
- **`VcpkgRoot` 必须显式传**：仓库里没有 `deps/vcpkg`
- **系统盘快满时 Flutter 编译会报" The Dart compiler exited unexpectedly"**：真实原因是 `%TEMP%` 写不下。把 `TMP`/`TEMP` 指到剩余空间大的盘再跑
- **`installer/fzones.iss` 需要 UTF-8 with BOM**，否则中文自定义消息会乱码；`tools_build_installer.ps1` 每次打包前会强制补上 BOM
- 在 Git Bash 里调 PowerShell 单行命令时，`$` 会被 bash 先吃掉——写进 `.ps1` 文件再执行

---

## 目录结构

```
.
├─ PowerToys/                     引擎（C++/Win32，只保留 FZones 依赖到的部分）
│  ├─ src/modules/fancyzones/
│  │  ├─ FancyZonesLib/           核心：布局、区域、吸附、分割条几何
│  │  └─ FZones/                  引擎 main、托盘、应用侧设置
│  ├─ src/common/                 日志、设置 API、DPI、钩子等公共库
│  ├─ packages/                   NuGet 还原目标（构建引用，勿删）
│  ├─ vcpkg_installed/            vcpkg 还原产物（构建引用，勿删）
│  └─ x64/Release/FZones.exe     [生成] 引擎，打包输入之一
├─ fzones-ui/                     界面（Flutter）
│  ├─ lib/                        主页、编辑器、设置页、设计令牌、字符串表
│  ├─ windows/runner/             无边框外壳：命中测试、圆角、窗口位置、跟随引擎
│  ├─ test/                       widget 与单元测试（flutter test）
│  ├─ tool/                       端到端脚本（需要能发全局热键的环境）
│  └─ build/windows/x64/runner/Release/  [生成] 界面产物，打包输入之一
├─ installer/
│  ├─ fzones.iss                  Inno Setup 脚本（唯一的打包器）
│  └─ dist/FZones-1.0.0-x64-setup.exe   [生成] 安装包
├─ tools_build_installer.ps1      构建 + 打包主入口
├─ tools_make_icon.ps1            生成图标（写进两个 .ico，二者都被编译进 exe）
└─ README.md / README.en.md       本文件
```

## 这一版明确没有的

- **分割条比例的持久化**：拖动只在本次生效。要留住比例，引擎得开始写 `custom-layouts.json`（目前只有界面写它），那是带契约变更和测试的独立改动
- **分割条悬停时的光标形状**（只有那条提示线）
- 引擎自身的单元测试工程（几何部分是纯函数，可以脱离桌面验证；界面侧的测试在 `fzones-ui/test/`）
