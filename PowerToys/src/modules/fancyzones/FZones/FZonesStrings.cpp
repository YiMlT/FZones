#include "pch.h"
#include "FZonesStrings.h"

namespace
{
    struct Entry
    {
        StrId id;
        const wchar_t* english;
        const wchar_t* chinese;
    };

    // Kept as an explicit id table so a missing translation cannot silently shift every later string.
    const Entry TABLE[] = {
        { STR_APP_TITLE, L"FZones Settings", L"FZones 设置" },
        { STR_GROUP_EDITOR, L"Editor", L"编辑器" },
        { STR_GROUP_ZONE_BEHAVIOR, L"Zone behavior", L"区域行为" },
        { STR_GROUP_ZONE_APPEARANCE, L"Zone appearance", L"区域外观" },
        { STR_GROUP_WINDOW_BEHAVIOR, L"Window behavior", L"窗口行为" },
        { STR_GROUP_WINDOW_SWITCHING, L"Switch between windows in the current zone", L"在当前区域内切换窗口" },
        { STR_GROUP_MONITOR_ROTATION, L"Rotate windows across monitors", L"跨显示器轮换窗口" },
        { STR_GROUP_OVERRIDE_SNAP, L"Override Windows Snap", L"覆盖 Windows 快照对齐" },
        { STR_GROUP_QUICK_SWITCH, L"Enable quick layout switch", L"启用快速布局切换" },
        { STR_GROUP_EXCLUDED, L"Excluded apps", L"排除的应用" },
        { STR_GROUP_APP, L"App", L"应用" },

        { STR_ACTIVATION_SHORTCUT, L"Activation shortcut", L"激活快捷键" },
        { STR_LAUNCH_EDITOR_DISPLAY, L"Launch editor on the display", L"编辑器打开所在的显示器" },
        { STR_OPT_ACTIVE_FOCUS, L"With active focus", L"跟随活动焦点" },
        { STR_OPT_MOUSE_POINTER, L"Where the mouse pointer is", L"跟随鼠标指针位置" },
        { STR_SHIFT_DRAG, L"Hold Shift key to activate zones while dragging a window", L"拖拽窗口时按住 Shift 键激活区域" },
        { STR_MOUSE_SWITCH, L"Use a non-primary mouse button to toggle zone activation", L"使用非主鼠标按键切换区域激活" },
        { STR_MIDDLE_CLICK_SPAN, L"Use middle-click mouse button to toggle multiple zones spanning", L"使用鼠标中键切换跨区域" },
        { STR_SHOW_ALL_MONITORS, L"Show zones on all monitors while dragging a window", L"拖拽窗口时在所有显示器上显示区域" },
        { STR_SPAN_MONITORS, L"Allow zones to span across monitors", L"允许区域跨显示器延伸" },
        { STR_OVERLAP, L"When multiple zones overlap", L"多个区域重叠时" },
        { STR_OVERLAP_SMALLEST, L"Activate the smallest zone by area", L"激活面积最小的区域" },
        { STR_OVERLAP_LARGEST, L"Activate the largest zone by area", L"激活面积最大的区域" },
        { STR_OVERLAP_POSITIONAL, L"Split the overlapped area into multiple activation targets", L"将重叠区域拆分为多个激活目标" },
        { STR_OVERLAP_CLOSEST, L"Activate the zone whose center is closest to the cursor", L"激活中心最接近光标的区域" },
        { STR_COLORS, L"Colors", L"颜色" },
        { STR_COLORS_CUSTOM, L"Custom colors", L"自定义颜色" },
        { STR_COLORS_SYSTEM, L"Windows default", L"Windows 默认" },
        { STR_SHOW_ZONE_NUMBER, L"Show zone number", L"显示区域编号" },
        { STR_OPACITY, L"Opacity (%)", L"不透明度 (%)" },
        { STR_HIGHLIGHT_COLOR, L"Highlight color", L"高亮颜色" },
        { STR_INACTIVE_COLOR, L"Inactive color", L"未激活颜色" },
        { STR_BORDER_COLOR, L"Border color", L"边框颜色" },
        { STR_NUMBER_COLOR, L"Number color", L"编号颜色" },
        { STR_KEEP_ON_RESOLUTION_CHANGE, L"Keep windows in their zones when the screen resolution or work area changes", L"屏幕分辨率或工作区变化时让窗口保持在区域内" },
        { STR_MATCH_ON_LAYOUT_CHANGE, L"During zone layout changes, windows assigned to a zone will match new size/positions", L"区域布局变化时，已分配区域的窗口会跟随新的尺寸与位置" },
        { STR_LAST_KNOWN_ZONE, L"Move newly created windows to their last known zone", L"将新建窗口移动到其上次所在的区域" },
        { STR_ACTIVE_MONITOR_EXPERIMENTAL, L"Move newly created windows to the current active monitor (Experimental)", L"将新建窗口移动到当前活动显示器（实验性）" },
        { STR_RESTORE_SIZE, L"Restore the original size of windows when unsnapping", L"取消对齐时恢复窗口的原始尺寸" },
        { STR_TRANSPARENT_DRAG, L"Make the dragged window transparent", L"使被拖拽的窗口透明" },
        { STR_CHILD_SNAP, L"Allow child windows snapping", L"允许子窗口对齐" },
        { STR_DISABLE_ROUND_CORNERS, L"Disable rounded corners when a window is snapped", L"窗口对齐时禁用圆角" },
        { STR_ENABLE_WINDOW_SWITCHING, L"Enable window switching", L"启用窗口切换" },
        { STR_NEXT_WINDOW, L"Next window", L"下一个窗口" },
        { STR_PREVIOUS_WINDOW, L"Previous window", L"上一个窗口" },
        { STR_ENABLE_ROTATION, L"Enable rotating windows with the monitor", L"启用随显示器轮换窗口" },
        { STR_ROTATION_SHORTCUT, L"Rotation mode shortcut", L"轮换模式快捷键" },
        { STR_OVERRIDE_SNAP, L"Override the Windows Snap shortcut (Win + arrow) to move windows between zones", L"覆盖 Windows 快照快捷键（Win + 方向键）以在区域间移动窗口" },
        { STR_MOVE_BASED_ON, L"Move windows based on", L"窗口移动依据" },
        { STR_OPT_ZONE_INDEX, L"Zone index", L"区域序号" },
        { STR_OPT_RELATIVE_POSITION, L"Relative position", L"相对位置" },
        { STR_MOVE_ACROSS_MONITORS, L"Move windows between zones across all monitors", L"在所有显示器的区域之间移动窗口" },
        { STR_ENABLE_QUICK_SWITCH, L"Switch between zones using the number hotkeys", L"使用数字快捷键在区域间切换" },
        { STR_FLASH_ON_SWITCH, L"Flash zones when switching layout", L"切换布局时闪烁区域" },
        { STR_EXCLUDED_DESCRIPTION, L"Excludes an application from snapping to zones and will only react to Windows Snap - add one application name per line", L"排除的应用不参与区域对齐，仅响应 Windows 快照对齐；每行填写一个应用名" },

        { STR_THEME, L"Theme", L"主题" },
        { STR_THEME_SYSTEM, L"Follow system", L"跟随系统" },
        { STR_THEME_LIGHT, L"Light", L"浅色" },
        { STR_THEME_DARK, L"Dark", L"深色" },
        { STR_LANGUAGE, L"Language", L"语言" },
        { STR_LANGUAGE_SYSTEM, L"Follow system", L"跟随系统" },
        { STR_LANGUAGE_ENGLISH, L"English", L"英语" },
        { STR_LANGUAGE_CHINESE, L"Chinese", L"中文" },
        { STR_AUTOSTART, L"Start when I sign in", L"登录时自动启动" },
        { STR_TRAY_EXIT, L"Exit", L"退出" },
        { STR_TRAY_SETTINGS, L"Settings", L"设置" },
        { STR_TRAY_EDIT_LAYOUTS, L"Edit layouts", L"编辑布局" },

        { STR_EDITOR_TITLE, L"FZones Layout Editor", L"FZones 布局编辑器" },
        { STR_TEMPLATES, L"Templates", L"模板" },
        { STR_CUSTOM_LAYOUTS, L"Custom layouts", L"自定义布局" },
        { STR_ZONE_COUNT, L"Zones", L"区域数量" },
        { STR_SPACING, L"Spacing (px)", L"间距 (px)" },
        { STR_SHOW_SPACING, L"Show spacing", L"显示间距" },
        { STR_APPLY, L"Apply and close", L"应用并关闭" },
        { STR_APPLIED, L"Applied: ", L"已应用：" },
        { STR_TEMPLATE_BLANK, L"Blank", L"空白" },
        { STR_TEMPLATE_FOCUS, L"Focus", L"焦点" },
        { STR_TEMPLATE_COLUMNS, L"Columns", L"列" },
        { STR_TEMPLATE_ROWS, L"Rows", L"行" },
        { STR_TEMPLATE_GRID, L"Grid", L"网格" },
        { STR_TEMPLATE_PRIORITY_GRID, L"Priority grid", L"优先网格" },

        { STR_NEW_LAYOUT, L"New grid", L"新建网格" },
        { STR_EDIT_GRID, L"Edit grid", L"编辑网格" },
        { STR_NEW_CANVAS, L"New canvas", L"新建画布" },
        { STR_EDIT_CANVAS, L"Edit canvas", L"编辑画布" },
        { STR_ADD_ZONE, L"Add zone", L"添加区域" },
        { STR_DELETE_ZONE, L"Delete zone", L"删除区域" },
        { STR_CANVAS_HINT, L"Drag a zone to move it, an edge or corner to resize it. Zones sitting on the same border move with it, and double-clicking that border gives each side the same share. Zones may overlap.", L"拖动区域移动位置，拖动边缘或角点调整大小；贴着同一道缝的区域会一起变化，双击该缝可均分两侧。区域可以重叠。" },
        { STR_SPLIT_LR, L"Split left/right", L"左右拆分" },
        { STR_SPLIT_TB, L"Split top/bottom", L"上下拆分" },
        { STR_MERGE_LEFT, L"Merge left", L"向左合并" },
        { STR_MERGE_UP, L"Merge up", L"向上合并" },
        { STR_MERGE_RIGHT, L"Merge right", L"向右合并" },
        { STR_MERGE_DOWN, L"Merge down", L"向下合并" },
        { STR_GRID_ROWS, L"Rows", L"行数" },
        { STR_GRID_COLS, L"Columns", L"列数" },
        { STR_LAYOUT_NAME, L"Name", L"名称" },
        { STR_SAVE_LAYOUT, L"Save layout", L"保存布局" },
        { STR_CANCEL, L"Cancel", L"取消" },
        { STR_GRID_HINT, L"Select a zone in the preview, then split it or merge it with a neighbour.", L"在预览中点选区域，然后拆分或与相邻区域合并。" },
        { STR_QUICK_SWITCH, L"Quick switch", L"快速切换" },
        { STR_QUICK_SWITCH_HINT, L"Win + Ctrl + Alt + digit · custom layouts only", L"Win + Ctrl + Alt + 数字键切换 · 仅自定义布局支持" },
        { STR_SET_DEFAULT_HORIZONTAL, L"Set as horizontal default", L"设为横屏默认" },
        { STR_SET_DEFAULT_VERTICAL, L"Set as vertical default", L"设为竖屏默认" },
        { STR_HOTKEY_CAPTURE, L"Press a new shortcut, Esc to cancel", L"按下新的快捷键，Esc 取消" },
    };

    Language requested = Language::System;
    Language active = Language::English;

    bool SystemPrefersChinese()
    {
        // LOWORD of a LANGID is the whole id (0x0804), not the primary language, so comparing it to
        // LANG_CHINESE (0x04) is never true and "follow system" silently resolved to English.
        return PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_CHINESE;
    }

    void ResolveActive()
    {
        active = requested == Language::System ? (SystemPrefersChinese() ? Language::Chinese : Language::English) : requested;
    }
}

namespace Loc
{
    void SetLanguage(Language language)
    {
        requested = language;
        ResolveActive();
    }

    Language RequestedLanguage()
    {
        return requested;
    }

    bool UsesChinese()
    {
        return active == Language::Chinese;
    }

    const wchar_t* T(StrId id)
    {
        const bool chinese = active == Language::Chinese;
        for (const Entry& entry : TABLE)
        {
            if (entry.id == id)
            {
                return chinese ? entry.chinese : entry.english;
            }
        }

        return L"?";
    }
}
