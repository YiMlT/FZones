# fzones-ui — 方案 B 的 Flutter 前端（阶段 3：设置窗 + 完整布局编辑器，原生 UI 已下线）

> 整个工作区的结构与各文件作用见 [`../PROJECT_STRUCTURE.md`](../PROJECT_STRUCTURE.md)；本文件只讲这个子工程。

设置窗原型，实现 `documents/designs/fzones_ipc_contract.md` 里那条契约：
**和引擎之间只有 JSON 文件**。读、写、通知都走同一份 `settings.json`，不额外开协议。

已经过引擎级端到端验证：用本 app 的 `SettingsWriter` 改激活快捷键后，引擎重载并重新注册了全局热键——
按旧快捷键不再打开编辑器，按新快捷键会打开（`tool/e2e_hotkey.ps1`）。

## 跑起来

```powershell
cd test1\fzones-ui
flutter analyze
flutter test                       # 65 项（契约 + 写路径 + 窗口外壳 + 子编辑器 + 错峰进入 + 双窗同步 + 三方形状对照 + 集成）
flutter build windows --release    # 产物在 build\windows\x64\runner\Release
```

**一个 exe 两个窗口，没有"主页"**：不带参数就是设置窗，`--editor` 才是布局编辑器（引擎的托盘菜单和
激活快捷键传的就是它）。想直接跑编辑器：

```powershell
flutter run -a --editor        # -a / --dart-entrypoint-args，只在桌面平台有效
```

评审用的命令行开关（引擎只会传 `--editor --toggle`）：`--editor` 开编辑器、`--grid` / `--canvas` / `--template` 直进子编辑器或固定模板页、
`--app` 打开设置页并直接停在末尾的**应用**分组（那三行在最底下，而合成滚轮事件在这台机器上进不去——有了它，`tool/e2e_autostart.ps1` 才能按量好的坐标点中开关）、
`--dark` / `--light` 与 `--zh` / `--en` 钉住主题和语言，方便把某一组状态复现出来（配套的截图脚本已在 2026-10-04 的整理里删除）。
不带这些开关时永远是「跟随系统」。

## 它做什么

- 读写 `%LOCALAPPDATA%\FZones\FancyZones\settings.json`——**引擎真实的那份**，不是样例数据。
  （注意是 `\FZones\`，不是 `\Microsoft\PowerToys\`；那一个是正版 PowerToys 的遗留目录，指错了不会报错，只会让引擎一直读自己的文件。见契约 §3。）
- **自绘窗口外壳**：48px 自定义标题栏（标题 + 最小化 ·〔设置〕· 关闭）、无边框窗口 + 8px 圆角、
  客户区最外一圈 1px `frame` 描边。圆角在 Win11 交给 DWM，本机 Win10 忽略该属性，回落到 `SetWindowRgn`；
  最大化时半径归 0。拖拽带与缩放手由 `WM_NCHITTEST` 判给系统，标题栏右侧按钮所在的那一条留给 Flutter 自己收点击。
- 按 v3 设计令牌渲染 34 行设置 + 9 个分组卡片：圆角 8 阶梯、行高 44 / 控件 32、开关 40×20、分段控件、下拉、键帽、颜色行。
- 键帽可点击捕获：点一下换成「按下新的快捷键，Esc 取消」的输入框，只按修饰键是待命，修饰键 + 普通键才提交，
  按引擎的 shift+ctrl+win+alt+key 顺序写成 `{key,ctrl,alt,shift,win}`，引擎随即重注册全局热键。
  颜色行的 `...` 打开自绘取色器（饱和度/明度面 + 色相条 + hex 框），不是系统对话框。
- 末尾的**应用**分组放主题与语言两个分段开关（跟随系统 / 浅色 / 深色，跟随系统 / 英语 / 中文），
  写进 `ui-settings.json`——引擎不读这个文件，另一个窗口监听它并实时跟随（用 `--dark` / `--zh` 这类评审链接启动的那扇窗不受影响，它的值是钉死的）。
- **登录时自动启动**：开关写的是 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 的 `FZones` 值，内容是**旁边那个 `FZones.exe` 的带引号全路径**
  （要在登录时跑的是引擎——热键、托盘、分区都归它）。安装包写的是同一条，但只在**完成页那个默认不勾的"开机自动启动"**被勾上时才写；`/S` 静默安装什么都不写，
  之后这条值归设置页管。旁边没有引擎时（比如只 `flutter build` 出来的裸产物）这一行是**禁用**状态，而不是点了没反应。
- 跟随系统主题与语言：两个值都默认 `system`，语言按 PRIMARYLANGID 判定，主题随平台亮度变化。
- 改一项就写回：**读-改-写 + 临时文件重命名覆盖**（契约 §5），只碰目标键，其余键连同顺序原样保留。
  开关/分段/下拉即时提交；数字、颜色、多行文本在失焦或回车时提交——每次写入都会让引擎重读整个文件，原生窗也是这么做的（`OnEditLostFocus`）。
- 监听该目录，`settings.json` 一变就重载（顶栏右侧会闪一下"已重新载入"）。外部改动（引擎或原生窗写的）优先于本地待提交值。
- 行内标注 `default` 表示该键不在文件里、显示的是引擎默认值。

两个窗口共用一个 exe：`FZonesUI.exe` 开设置窗，`FZonesUI.exe --editor` 开布局编辑器。

可执行文件名是**契约的一部分**：`FancyZones::ToggleEditor()` 按这个固定名字在 `FZones.exe` 旁边找它，找到就带 `--editor` 拉起来。**阶段 3 删掉了内置编辑器，所以找不到时不再回落**——按快捷键什么都不会发生，引擎只刷新 `editor-parameters.json`。改名前先读契约 §7.6。

## 它不做什么

- 画布的拖拽做了吸附/最小边/不越界；松手后区域矩形走 200ms 过渡，拖动期间直接跟随指针不插值。
- 单实例保护在 runner 里，按**角色**各一把锁：编辑器一把、设置窗一把，所以两扇窗可以同时开，但同一角色再启动只会把已开的那扇唤到前台
  （最小化的会先还原），第二个进程随即退出并在终端留一行说明。锁名按 exe 自己的路径生成，所以 release 和 `flutter run` 的 debug 是两个程序、互不挡。
  引擎传的是 `--editor --toggle`：带着 `--toggle` 的第二次启动会把已开的那扇**关掉**而不是唤到前台，所以激活快捷键对"引擎自己拉的"和"你手动开的"
  窗口行为一致（引擎只认自己那个子进程，这个前提没变，只是不再需要它认得窗口）。

## 文件

| 文件 | 内容 |
|------|------|
| `lib/design.dart` | 设计令牌：圆角/尺寸/时长/调色板，以及让主题切换能 240ms 交叉淡入的 `ThemeExtension.lerp` |
| `lib/app_bar.dart` | 窗口外壳：`FzWindowFrame`（圆角 + 1px 外框描边 + 八条缩放手）、`FzAppBar`（48px 标题栏 + 46×32 按钮，靠右依次为最小化 ·〔设置〕· 关闭，关闭按钮右侧留白 = 页面右侧留白 16） |
| `lib/window_bridge.dart` | 与 `windows/runner/flutter_window.cpp` 之间那条 `fzones/window` 通道：拖拽 / 缩放 / 最小化 / 关闭 / 打开设置 / 最大化状态回传，以及开机自启的 `getAutostart` / `setAutostart`。非 Windows 或 `flutter test` 下自动降级成空操作 |
| `lib/color_picker.dart` | 取色器面板：饱和度/明度面、色相条、hex 输入、取消/确定，全部走本应用令牌 |
| `lib/ui_settings.dart` | 主题与语言的持久化：`ui-settings.json`，读-改-写 + 原子替换，引擎不碰这个文件 |
| `lib/strings.dart` | 中英文表，与 `FZonesStrings.cpp` 同形 |
| `lib/settings_model.dart` | 34 行设置表（与 `SettingsWindow.cpp` 的 `ROWS[]` 同序同门控）、settings.json 读取、门控规则、数据目录 |
| `lib/settings_writer.dart` | 原子写 + 读-改-写 |
| `lib/layout_store.dart` | `LayoutStore.cpp` 的 Dart 移植：6 个文件、冻结字段名、`FzRect`/`FzDevice`/`FzLayout`/`FzCustomLayout` |
| `lib/grid_model.dart` | 网格模型：拆分/合并/重编号/带取整的矩形计算，与 C++ 的 `GridModel` 逐条对应 |
| `lib/widgets.dart` | 两个窗口共用的 v3 控件，含自绘下拉（`FzDropdown`：弹层与字段等宽，开 200ms / 收 150ms，向上翻转、Esc 与遮罩关闭） |
| `lib/editor_page.dart` | 编辑器浏览页、磁贴预览（含重排动画）、模板形状（含引擎那张 `predefinedPriorityGridLayouts` 的逐条移植）、**固定模板页**（只有区域数量/间距/显示间距 + 实时预览，另存为自定义才进子编辑器）、动作行（新建/编辑/删除，删除悬停变红且需二次确认）、页面切换 |
| `lib/grid_editor.dart` | 网格子编辑器：拆分/合并、点选区域、保存 |
| `lib/canvas_editor.dart` | 画布子编辑器：拖动/缩放/增删区域，贴着同一道缝的区域随边界联动，双击该缝均分两侧，几何规则是纯函数 |
| `lib/editor_shell.dart` | 三个编辑器页共用的外壳、字段标签与文本框 |
| `test/contract_test.dart` | 行表对齐、门控规则、真实文件 round-trip |
| `test/chrome_test.dart` | 窗口外壳：标题栏按钮数量与顺序、双语 tooltip、没有 runner 时点击不抛、外框描边取 `frame` 令牌、评审条三段标签不被截断、聚焦字段长出双环 |
| `test/writer_test.dart` | 写路径：只改目标键、原子、缺文件时补形状，以及在真实 widget 树里点开关 |
| `test/layout_store_test.dart` | 6 个文件的字段名、单显示器替换、数字/默认布局的读-改-写 |
| `test/grid_model_test.dart` | 网格数学：铺满、百分比守恒、拆分合并、与 `LayoutConfigurator::Grid` 同形 |
| `test/editor_page_test.dart` | 浏览页：显示器选项卡（含悬停色带的逐帧取色）、"应用"写入 `applied-layouts.json`、应用模板后选中项不被重载抢走、底部两行在 620 最小宽度下不溢出且仍然右对齐、删除按钮（编辑右侧第四枚 / 悬停变红 / 二次确认 / 无自定义时禁用）、模板进子编辑器另存为自定义布局、区域数量与间距确实在自定义分组内 |
| `test/ui_settings_test.dart` | 两个窗口之间的全部协议：`ui-settings.json` 的读写 round-trip、按值比较，以及一扇窗改主题后另一扇窗跟着变 |
| `test/autostart_test.dart` | 自启那一行：用**假的通道**答两个注册表动词（绝不碰 HKCU），点开关跟随回执、旁边没引擎时整行禁用；另有一条把 runner / 引擎 / 安装包三处 `RUN_VALUE` 字面量对在一起的检查 |
| `test/editors_test.dart` | 画布几何纯函数、深链接、网格/画布子编辑器端到端保存 |
| `test/priority_grid_test.dart` | 优先网格：解析 `LayoutConfigurator.cpp` 与样例 HTML，把 C++ / Dart / 样例三方逐字段对一遍；再加形状断言（25/50/25、通高的优先区、1–10 区无缝隙、11 区回落网格） |
| `tool/e2e_hotkey.ps1` | 引擎级回归：改快捷键 → 引擎重载 → 旧键失效、新键生效 |
| `tool/e2e_editor_launch.ps1` | 引擎级回归：自己暂存一份部署布局，验证 A"快捷键 → 引擎 → Flutter 编辑器"、B"删掉 UI 后按快捷键什么都不该发生" |
| `tool/e2e_single_instance.ps1` | 单实例回归：二次启动只唤起不新开（退出码 0 + 那句提示）、`--toggle` 关掉已开的、两个角色并存、最小化后能被唤回、关掉后锁就释放 |
| `tool/e2e_toggle_closes_editor.ps1` | 含引擎的闭环：手动开的编辑器也能被激活快捷键关掉（用托盘那个命名事件触发，不发全局热键），顺带回归引擎自己那两条路径 |
| `tool/e2e_autostart.ps1` | 真注册表回归：暂存一份出货布局，按 `--app` 打开设置页，用**量好的坐标**点开关，断言 `HKCU\...\Run\FZones` 变成带引号的引擎路径、再点一次消失；结束时把用户原来的值放回去 |
| `tool/set_setting.dart` | 命令行写入一个键（`@file` 传对象字面量，避开 Windows shell 吃引号） |

## 改代码前先知道

- `applied-layouts.json` 是引擎与 UI **双写**文件，写它时必须读-改-写。
- 开机自启那条注册表值有**三个写入方**：runner 的 `kRunValue`、引擎 `AppSettings.cpp` 的 `RUN_VALUE`、安装包 `fzones.nsi` 的 `!define RUN_VALUE`。
  三处字面量必须都是 `FZones`，否则设置页的开关和安装包管的是两个条目，而且不会有任何报错——`test/autostart_test.dart` 里那条检查就是钉这个的。
  写进去的值是**旁边那个 `FZones.exe` 的带引号全路径**（引号不能省：Program Files 路径带空格）。
- 编辑器只是**读写 JSON 的前端**：点"应用并关闭"写的是 `applied-layouts.json`，真的把窗口排进区域里的是
  `FZones.exe`。引擎没在跑（`tasklist /FI "IMAGENAME eq FZones.exe"`）时写盘照样成功、状态条照样亮，但桌面上
  什么都不会发生；引擎在跑时，还得设置页里"改变布局时移动窗口"（`fancyzones_zoneSetChange_moveWindows`，
  **引擎默认 false**）开着，已经打开的窗口才会被挪动。`flutter run -a --editor` 只启动这一侧。
- 窗口外壳的尺寸是**三处共用**的：`lib/design.dart` 的 `FzMetrics.bar/captionButton`、`windows/runner/flutter_window.h`
  的 `frame::kBarLogical/kCaptionButtonLogical`，以及 Dart 报给原生那条 `setCaptionBar` 的预留宽度。
  改了任一处而没改另两处，表现是标题栏拖不动或者按钮点不动——因为那块区域被系统当成 caption 收走了。
- 测试**必须**设 `FzPaths.overrideDir`：这些用例真的点控件，真的写文件。曾经有一轮 chrome 测试没隔离，
  把捕获到的 `Ctrl+Q` 写进了引擎的 `settings.json`，激活快捷键当场失效且没人报错。
- 卡片的 1px 描边放在 `foregroundDecoration`，不是 `decoration.border`：后者会从内容宽度里吃掉 2px，
  于是 280 的控件带变成 278，行就溢出了（`flutter test` 会直接报 RenderFlex overflowed）。
- **颜色过渡的起点不能是 `Colors.transparent`**：透明 = 透明黑，插值中途会经过灰色，
  所以行悬停色带看起来比 `hover` 令牌深，两行同时淡入淡出时更像"两条阴影"。用 `design.dart` 的
  `fade(color)`（同色零 alpha）作为过渡的终点。
- 行内的左右留白分两层：色带内缩 `rowInset`（6/3），内容再内缩 `rowContentInset`（12），
  这样色带在文字与控件外面各留 6px，不会贴着元素边缘。标签列宽 320 就是这么算出来的。
- `lib/settings_model.dart` 的行表是**键清单的唯一副本**——原生 `SettingsWindow.cpp` 已删除，没有第二份可以对照。
- 改文案要同时改 `lib/strings.dart`、引擎的 `FZonesStrings.cpp` 和设计稿 `fzones-ui-v3.html`——三处人工对齐（逐条比对的脚本已删除）。
- 构建与打包走工作区根目录的 `tools_build_installer.ps1`，不要手敲 MSBuild。

## 实测（150% 缩放，窗口逻辑宽 700）

| | 原生 `FZones.exe --settings` | 本 POC |
|---|---|---|
| 冷启动到出窗 | 413 ms | 548 ms |
| 工作集 | 73.0 MB | 78.6 MB |
| 私有字节 | 61.8 MB | 106.6 MB |
| 磁盘 | 2.65 MB | 27.47 MB |

原生那 73 MB 含整个区域引擎；方案 B 下引擎仍要跑，所以设置窗打开时是两份内存。

## 已知的上游修复

阶段 1 顺带修了 `common/SettingsAPI/FileWatcher.cpp` 的三个缺陷——不修的话原子写对引擎是隐形的：

1. 只订阅 `LastWriteTime`，而"临时文件改名覆盖"在目录上是**文件名**变更 → 加了 `FileName`。
2. `m_lastWrite` 只在第一次通知时预热，导致启动后第一次变更被吞掉 → 改为构造时预热。
3. 文件名比较拿小写去比未转小写的原名 → 改用已转小写的副本。
