/// The application string table, byte-identical to FZonesStrings.cpp.
/// tools_diff_strings.py can be pointed at this file the same way it is pointed at the
/// HTML specimen: keep the 'key': ['中文','English'] shape.
library;

enum FzLang { zh, en }

const Map<String, List<String>> kStrings = {
  // Window chrome. The buttons live in the custom app bar, so these are its only strings.
  'win_minimize': ['最小化', 'Minimize'],
  'win_settings': ['打开设置', 'Open settings'],
  'win_close': ['关闭', 'Close'],
  'app_title': ['FZones 设置', 'FZones Settings'],
  'group_editor': ['编辑器', 'Editor'],
  'activation_shortcut': ['激活快捷键', 'Activation shortcut'],
  'launch_editor_display': ['编辑器打开所在的显示器', 'Launch editor on the display'],
  'opt_active_focus': ['跟随活动焦点', 'With active focus'],
  'opt_mouse_pointer': ['跟随鼠标指针位置', 'Where the mouse pointer is'],
  'group_zone_behavior': ['区域行为', 'Zone behavior'],
  'shift_drag': ['拖拽窗口时按住 Shift 键激活区域', 'Hold Shift key to activate zones while dragging a window'],
  'mouse_switch': ['使用非主鼠标按键切换区域激活', 'Use a non-primary mouse button to toggle zone activation'],
  'middle_click': ['使用鼠标中键切换跨区域', 'Use middle-click mouse button to toggle multiple zones spanning'],
  'show_all': ['拖拽窗口时在所有显示器上显示区域', 'Show zones on all monitors while dragging a window'],
  'span': ['允许区域跨显示器延伸', 'Allow zones to span across monitors'],
  'overlap': ['多个区域重叠时', 'When multiple zones overlap'],
  'ov_smallest': ['激活面积最小的区域', 'Activate the smallest zone by area'],
  'ov_largest': ['激活面积最大的区域', 'Activate the largest zone by area'],
  'ov_positional': ['将重叠区域拆分为多个激活目标', 'Split the overlapped area into multiple activation targets'],
  'ov_closest': ['激活中心最接近光标的区域', 'Activate the zone whose center is closest to the cursor'],
  'group_zone_appearance': ['区域外观', 'Zone appearance'],
  'colors': ['颜色', 'Colors'],
  'colors_custom': ['自定义颜色', 'Custom colors'],
  'colors_system': ['Windows 默认', 'Windows default'],
  'show_zone_number': ['显示区域编号', 'Show zone number'],
  'opacity': ['不透明度 (%)', 'Opacity (%)'],
  'highlight_color': ['高亮颜色', 'Highlight color'],
  'inactive_color': ['未激活颜色', 'Inactive color'],
  'border_color': ['边框颜色', 'Border color'],
  'number_color': ['编号颜色', 'Number color'],
  'group_window_behavior': ['窗口行为', 'Window behavior'],
  'keep_resolution': ['屏幕分辨率或工作区变化时让窗口保持在区域内', 'Keep windows in their zones when the screen resolution or work area changes'],
  'match_layout': ['区域布局变化时，已分配区域的窗口会跟随新的尺寸与位置', 'During zone layout changes, windows assigned to a zone will match new size/positions'],
  'last_zone': ['将新建窗口移动到其上次所在的区域', 'Move newly created windows to their last known zone'],
  'active_monitor': ['将新建窗口移动到当前活动显示器（实验性）', 'Move newly created windows to the current active monitor (Experimental)'],
  'restore_size': ['取消对齐时恢复窗口的原始尺寸', 'Restore the original size of windows when unsnapping'],
  'transparent': ['使被拖拽的窗口透明', 'Make the dragged window transparent'],
  'child_snap': ['允许子窗口对齐', 'Allow child window snapping'],
  'disable_round': ['窗口对齐时禁用圆角', 'Disable rounded corners when a window is snapped'],
  'group_switching': ['在当前区域内切换窗口', 'Switch between windows in the current zone'],
  'enable_switching': ['启用窗口切换', 'Enable window switching'],
  'next_window': ['下一个窗口', 'Next window'],
  'prev_window': ['上一个窗口', 'Previous window'],
  'group_rotation': ['跨显示器轮换窗口', 'Rotate windows across monitors'],
  'enable_rotation': ['启用随显示器轮换窗口', 'Enable rotating windows with the monitor'],
  'rotation_shortcut': ['轮换模式快捷键', 'Rotation mode shortcut'],
  'group_snap': ['覆盖 Windows 快照对齐', 'Override Windows Snap'],
  'override_snap': ['覆盖 Windows 快照快捷键（Win + 方向键）以在区域间移动窗口', 'Override the Windows Snap shortcut (Win + arrow) to move windows between zones'],
  'move_based': ['窗口移动依据', 'Move windows based on'],
  'opt_zone_index': ['区域序号', 'Zone index'],
  'opt_relative': ['相对位置', 'Relative position'],
  'move_across': ['在所有显示器的区域之间移动窗口', 'Move windows between zones across all monitors'],
  'group_quick': ['启用快速布局切换', 'Enable quick layout switch'],
  'enable_quick': ['使用数字快捷键在区域间切换', 'Switch between zones using the number hotkeys'],
  'flash': ['切换布局时闪烁区域', 'Flash zones when switching layout'],
  'group_excluded': ['排除的应用', 'Excluded apps'],
  'excluded_desc': ['排除的应用不参与区域对齐，仅响应 Windows 快照对齐；每行填写一个应用名', 'Excludes an application from snapping to zones and will only react to Windows Snap - add one application name per line'],
  'group_app': ['应用', 'App'],
  'theme': ['主题', 'Theme'],
  'theme_system': ['跟随系统', 'Follow system'],
  'theme_light': ['浅色', 'Light'],
  'theme_dark': ['深色', 'Dark'],
  'language': ['语言', 'Language'],
  'lang_system': ['跟随系统', 'Follow system'],
  'lang_en': ['英语', 'English'],
  'lang_zh': ['中文', 'Chinese'],
  'autostart': ['登录时自动启动', 'Start when I sign in'],

  // Chrome of the two editors: the hotkey capture box and the colour picker.
  'hotkey_capture': ['按下新的快捷键，Esc 取消', 'Press a new shortcut, Esc to cancel'],
  'pick_color': ['选择颜色', 'Pick a colour'],
  'ok': ['确定', 'OK'],

  // ---- layout editor ----
  'editor_title': ['FZones 布局编辑器', 'FZones Layout Editor'],
  'templates': ['模板', 'Templates'],
  'custom_layouts': ['自定义布局', 'Custom layouts'],
  'zone_count': ['区域数量', 'Zones'],
  'spacing': ['间距 (px)', 'Spacing (px)'],
  'show_spacing': ['显示间距', 'Show spacing'],
  'apply': ['应用并关闭', 'Apply and close'],
  'applied': ['已应用：', 'Applied: '],
  'delete_layout': ['删除布局', 'Delete layout'],
  'deleted': ['已删除：', 'Deleted: '],
  't_blank': ['空白', 'Blank'],
  't_focus': ['焦点', 'Focus'],
  't_columns': ['列', 'Columns'],
  't_rows': ['行', 'Rows'],
  't_grid': ['网格', 'Grid'],
  't_priority': ['优先网格', 'Priority grid'],
  'new_layout': ['新建网格', 'New grid'],
  'edit_grid': ['编辑网格', 'Edit grid'],
  'new_canvas': ['新建画布', 'New canvas'],
  'edit_canvas': ['编辑画布', 'Edit canvas'],
  'edit_template': ['编辑模板', 'Edit template'],
  'save_as_custom': ['另存为自定义', 'Save as custom'],
  // The template page's button keeps the page open, so it cannot borrow the browse page's wording.
  'apply_only': ['应用', 'Apply'],
  'template_hint': [
    '固定模板只能调整区域数量与间距。要拆分、合并或拖动区域，请先另存为自定义布局。',
    'A fixed template only takes a zone count and a spacing. To split, merge or drag zones, save it as a custom layout first.',
  ],
  'set_default_horizontal': ['设为横屏默认', 'Set as horizontal default'],
  'set_default_vertical': ['设为竖屏默认', 'Set as vertical default'],
  'quick_switch': ['快速切换', 'Quick switch'],
  'quick_switch_hint': ['Win + Ctrl + Alt + 数字键切换 · 仅自定义布局支持', 'Win + Ctrl + Alt + digit · custom layouts only'],
  'no_monitors': ['读不到显示器参数：先让引擎写入 editor-parameters.json（从托盘菜单打开一次编辑器即可）。', 'No monitor parameters: let the engine write editor-parameters.json first (open the editor once from the tray menu).'],
  'stage2b': ['网格/画布编辑器是下一阶段', 'Grid and canvas editors are the next slice'],
  'monitors': ['显示器', 'Displays'],
  'grid_rows': ['行数', 'Rows'],
  'grid_cols': ['列数', 'Columns'],
  'layout_name': ['名称', 'Name'],
  'save_layout': ['保存布局', 'Save layout'],
  'cancel': ['取消', 'Cancel'],
  'add_zone': ['添加区域', 'Add zone'],
  'delete_zone': ['删除区域', 'Delete zone'],
  'canvas_hint': ['拖动区域移动位置，拖动边缘或角点调整大小；贴着同一道缝的区域会一起变化，双击该缝可均分两侧。区域可以重叠。', 'Drag a zone to move it, an edge or corner to resize it. Zones sitting on the same border move with it, and double-clicking that border gives each side the same share. Zones may overlap.'],
  'split_lr': ['左右拆分', 'Split left/right'],
  'split_tb': ['上下拆分', 'Split top/bottom'],
  'merge_left': ['向左合并', 'Merge left'],
  'merge_up': ['向上合并', 'Merge up'],
  'merge_right': ['向右合并', 'Merge right'],
  'merge_down': ['向下合并', 'Merge down'],
  'grid_hint': ['在预览中点选区域，然后拆分或与相邻区域合并。', 'Select a zone in the preview, then split it or merge it with a neighbour.'],
};

String fzT(String key, FzLang lang) {
  final List<String>? entry = kStrings[key];
  if (entry == null) {
    return key;
  }
  return lang == FzLang.zh ? entry[0] : entry[1];
}

/// Resolves "follow system" the way Loc::SetLanguage does: the primary language id of the
/// user\'s UI locale decides, not the whole LANGID.
FzLang fzResolveLang(String systemLocale) =>
    systemLocale.toLowerCase().startsWith('zh') ? FzLang.zh : FzLang.en;
