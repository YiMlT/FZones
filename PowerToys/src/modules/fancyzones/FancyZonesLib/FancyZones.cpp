#include "pch.h"
#include "FancyZones.h"

#include <common/interop/shared_constants.h>
#include <common/logger/logger.h>
#include <common/logger/call_tracer.h>
#include <common/utils/EventWaiter.h>
#include <common/utils/winapi_error.h>
#include <common/SettingsAPI/FileWatcher.h>

#include <FancyZonesLib/DraggingState.h>
#include <FancyZonesLib/EditorParameters.h>
#include <FancyZonesLib/FancyZonesData.h>
#include <FancyZonesLib/FancyZonesData/AppliedLayouts.h>
#include <FancyZonesLib/FancyZonesData/AppZoneHistory.h>
#include <FancyZonesLib/FancyZonesData/CustomLayouts.h>
#include <FancyZonesLib/FancyZonesData/DefaultLayouts.h>
#include <FancyZonesLib/FancyZonesData/LastUsedVirtualDesktop.h>
#include <FancyZonesLib/FancyZonesData/LayoutHotkeys.h>
#include <FancyZonesLib/FancyZonesData/LayoutTemplates.h>
#include <FancyZonesLib/FancyZonesWindowProcessing.h>
#include <FancyZonesLib/FancyZonesWindowProperties.h>
#include <FancyZonesLib/FancyZonesWinHookEventIDs.h>
#include <FancyZonesLib/KeyboardInput.h>
#include <FancyZonesLib/MonitorUtils.h>
#include <FancyZonesLib/on_thread_executor.h>
#include <FancyZonesLib/Settings.h>
#include <FancyZonesLib/SettingsObserver.h>
#include <FancyZonesLib/trace.h>
#include <FancyZonesLib/VirtualDesktop.h>
#include <FancyZonesLib/WindowKeyboardSnap.h>
#include <FancyZonesLib/WindowMouseSnap.h>
#include <FancyZonesLib/WindowUtils.h>
#include <FancyZonesLib/WorkArea.h>
#include <FancyZonesLib/ZoneSplitter.h>
#include <FancyZonesLib/SplitterHint.h>
#include <FancyZonesLib/WorkAreaConfiguration.h>

enum class DisplayChangeType
{
    WorkArea,
    DisplayChange,
    VirtualDesktop,
    Initialization
};

constexpr wchar_t* DisplayChangeTypeName (const DisplayChangeType type){
    switch (type)
    {
    case DisplayChangeType::WorkArea:
        return L"WorkArea";
    case DisplayChangeType::DisplayChange:
        return L"DisplayChange";
    case DisplayChangeType::VirtualDesktop:
        return L"VirtualDesktop";
    case DisplayChangeType::Initialization:
        return L"Initialization";
    default:
        return L"";
    }
}

// Non-localizable strings
namespace NonLocalizable
{
    const wchar_t ToolWindowClassName[] = L"SuperFancyZones";
    // `--toggle` is what makes the UI close a window we did not start rather than raise it: this
    // process only tracks the child it launched, but the window may have been opened by hand, by
    // the runner's own gear, or by `flutter run`. See single_instance in the UI's runner.
    const wchar_t EditorCommandLine[] = L"--editor --toggle";
}

namespace
{
    constexpr UINT_PTR MonitorRotationCommitTimerId = 0x4D525443;
    constexpr UINT MonitorRotationCommitDelayMillis = 760;

    struct WindowRotationSnapshot
    {
        HWND window{};
        HMONITOR sourceMonitor{};
        RECT sourceRect{};
    };

    std::optional<size_t> FindMonitorIndex(HMONITOR monitor, const std::vector<std::pair<HMONITOR, RECT>>& monitors) noexcept
    {
        const auto iter = std::find_if(monitors.begin(), monitors.end(), [monitor](const auto& entry) {
            return entry.first == monitor;
        });

        if (iter == monitors.end())
        {
            return std::nullopt;
        }

        return static_cast<size_t>(std::distance(monitors.begin(), iter));
    }

    std::vector<WindowRotationSnapshot> CollectWindowRotationSnapshots()
    {
        std::vector<WindowRotationSnapshot> windows;
        EnumWindows(
            [](HWND window, LPARAM param) -> BOOL {
                if (!FancyZonesWindowProcessing::IsProcessableManually(window))
                {
                    return TRUE;
                }

                RECT rect{};
                if (!GetWindowRect(window, &rect) || rect.left == rect.right || rect.top == rect.bottom)
                {
                    return TRUE;
                }

                auto sourceMonitor = MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
                if (!sourceMonitor)
                {
                    return TRUE;
                }

                auto& snapshots = *reinterpret_cast<std::vector<WindowRotationSnapshot>*>(param);
                snapshots.push_back({ .window = window, .sourceMonitor = sourceMonitor, .sourceRect = rect });
                return TRUE;
            },
            reinterpret_cast<LPARAM>(&windows));

        return windows;
    }

    constexpr bool IsRotationPreviewReleaseKey(DWORD vkCode) noexcept
    {
        return vkCode == VK_LWIN || vkCode == VK_RWIN || vkCode == VK_CONTROL || vkCode == VK_LCONTROL || vkCode == VK_RCONTROL || vkCode == VK_MENU || vkCode == VK_LMENU || vkCode == VK_RMENU || vkCode == VK_SHIFT || vkCode == VK_LSHIFT || vkCode == VK_RSHIFT;
    }

    constexpr bool IsWinKey(DWORD vkCode) noexcept
    {
        return vkCode == VK_LWIN || vkCode == VK_RWIN;
    }

    constexpr bool IsCtrlKey(DWORD vkCode) noexcept
    {
        return vkCode == VK_CONTROL || vkCode == VK_LCONTROL || vkCode == VK_RCONTROL;
    }

    constexpr bool IsAltKey(DWORD vkCode) noexcept
    {
        return vkCode == VK_MENU || vkCode == VK_LMENU || vkCode == VK_RMENU;
    }

    constexpr bool IsShiftKey(DWORD vkCode) noexcept
    {
        return vkCode == VK_SHIFT || vkCode == VK_LSHIFT || vkCode == VK_RSHIFT;
    }

    size_t GetMonitorDisplayNumber(HMONITOR monitor, size_t fallback) noexcept
    {
        MONITORINFOEX monitorInfo{};
        monitorInfo.cbSize = sizeof(MONITORINFOEX);
        if (!GetMonitorInfoW(monitor, &monitorInfo))
        {
            return fallback;
        }

        std::wstring deviceName = monitorInfo.szDevice;
        const auto digitStart = deviceName.find_last_not_of(L"0123456789");
        if (digitStart == std::wstring::npos || digitStart + 1 >= deviceName.size())
        {
            return fallback;
        }

        try
        {
            return static_cast<size_t>(std::stoul(deviceName.substr(digitStart + 1)));
        }
        catch (...)
        {
            return fallback;
        }
    }
}

namespace MonitorRotation
{
    LONG ScaleCoordinate(LONG value, LONG sourceStart, LONG sourceSize, LONG targetStart, LONG targetSize) noexcept
    {
        if (sourceSize == 0)
        {
            return targetStart;
        }

        return targetStart + MulDiv(value - sourceStart, targetSize, sourceSize);
    }

    RECT MapRectBetweenMonitorWorkAreas(const RECT& windowRect, const RECT& sourceWorkArea, const RECT& targetWorkArea) noexcept
    {
        const LONG sourceWidth = sourceWorkArea.right - sourceWorkArea.left;
        const LONG sourceHeight = sourceWorkArea.bottom - sourceWorkArea.top;
        const LONG targetWidth = targetWorkArea.right - targetWorkArea.left;
        const LONG targetHeight = targetWorkArea.bottom - targetWorkArea.top;

        return RECT{
            .left = ScaleCoordinate(windowRect.left, sourceWorkArea.left, sourceWidth, targetWorkArea.left, targetWidth),
            .top = ScaleCoordinate(windowRect.top, sourceWorkArea.top, sourceHeight, targetWorkArea.top, targetHeight),
            .right = ScaleCoordinate(windowRect.right, sourceWorkArea.left, sourceWidth, targetWorkArea.left, targetWidth),
            .bottom = ScaleCoordinate(windowRect.bottom, sourceWorkArea.top, sourceHeight, targetWorkArea.top, targetHeight),
        };
    }

    size_t GetRotatedMonitorIndex(size_t sourceIndex, size_t monitorCount, bool reverse) noexcept
    {
        if (reverse)
        {
            return sourceIndex == 0 ? monitorCount - 1 : sourceIndex - 1;
        }

        return (sourceIndex + 1) % monitorCount;
    }
}

struct FancyZones : public winrt::implements<FancyZones, IFancyZones, IFancyZonesCallback>, public SettingsObserver
{
public:
    FancyZones(HINSTANCE hinstance, std::function<void()> disableModuleCallbackFunction) noexcept :
        SettingsObserver({ SettingId::EditorHotkey, SettingId::WindowSwitching, SettingId::PrevTabHotkey, SettingId::NextTabHotkey, SettingId::SpanZonesAcrossMonitors, SettingId::MonitorRotation, SettingId::MonitorRotationHotkey, SettingId::ShiftDrag }),
        m_hinstance(hinstance),
        m_draggingState([this]() {
            PostMessageW(m_window, WM_PRIV_LOCATIONCHANGE, NULL, NULL);
        })
    {
        if (!SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_NORMAL))
        {
            Logger::warn("Failed to set main thread priority");
        }

        this->disableModuleCallback = std::move(disableModuleCallbackFunction);

        FancyZonesSettings::instance().LoadSettings();

        FancyZonesDataInstance().ReplaceZoneSettingsFileFromOlderVersions();
        LayoutTemplates::instance().LoadData();
        CustomLayouts::instance().LoadData();
        LayoutHotkeys::instance().LoadData();
        AppliedLayouts::instance().LoadData();
        AppZoneHistory::instance().LoadData();
        DefaultLayouts::instance().LoadData();
        LastUsedVirtualDesktop::instance().LoadData();

        // The one place that can see a press landing on the border between two windows that are not
        // ours. Cheap to answer, and it decides there and then whether the click is a splitter grab.
        MouseButtonsHook::setLeftButtonHandler([this](UINT message, POINT pt) {
            return OnSplitterMouseButton(message, pt);
        });
    }

    // IFancyZones
    IFACEMETHODIMP_(void)
    Run() noexcept;
    IFACEMETHODIMP_(void)
    Destroy() noexcept;

    IFACEMETHODIMP_(void)
    HandleWinHookEvent(const WinHookEvent* data) noexcept
    {
        const auto wparam = reinterpret_cast<WPARAM>(data->hwnd);
        const LONG lparam = 0;
        switch (data->event)
        {
        case EVENT_SYSTEM_MOVESIZESTART:
            PostMessageW(m_window, WM_PRIV_MOVESIZESTART, wparam, lparam);
            break;
        case EVENT_SYSTEM_MOVESIZEEND:
            PostMessageW(m_window, WM_PRIV_MOVESIZEEND, wparam, lparam);
            break;
        case EVENT_OBJECT_LOCATIONCHANGE:
            PostMessageW(m_window, WM_PRIV_LOCATIONCHANGE, wparam, lparam);
            break;
        case EVENT_OBJECT_NAMECHANGE:
            PostMessageW(m_window, WM_PRIV_NAMECHANGE, wparam, lparam);
            break;

        case EVENT_OBJECT_UNCLOAKED:
        case EVENT_OBJECT_SHOW:
        case EVENT_OBJECT_CREATE:
            if (data->idObject == OBJID_WINDOW)
            {
                PostMessageW(m_window, WM_PRIV_WINDOWCREATED, wparam, lparam);
            }
            break;

        case EVENT_OBJECT_DESTROY:
            if (data->idObject == OBJID_WINDOW)
            {
                PostMessageW(m_window, WM_PRIV_WINDOWDESTROYED, wparam, lparam);
            }
            break;
        }
    }

    IFACEMETHODIMP_(void)
    VirtualDesktopChanged() noexcept;
    IFACEMETHODIMP_(bool)
    OnKeyDown(PKBDLLHOOKSTRUCT info) noexcept;
    IFACEMETHODIMP_(bool)
    OnKeyUp(PKBDLLHOOKSTRUCT info) noexcept;

    void MoveSizeStart(HWND window, HMONITOR monitor);
    void MoveSizeUpdate(HMONITOR monitor, POINT const& ptScreen);
    void MoveSizeEnd();
    void AbortMoveSize();

    void WindowCreated(HWND window) noexcept;
    void ToggleEditor() noexcept;

    LRESULT WndProc(HWND, UINT, WPARAM, LPARAM) noexcept;
    void OnKeyboardInput(WPARAM flags, HRAWINPUT hInput) noexcept;
    void OnDisplayChange(DisplayChangeType changeType) noexcept;
    bool AddWorkArea(HMONITOR monitor, const FancyZonesDataTypes::WorkAreaId& id, const FancyZonesUtils::Rect& rect) noexcept;

protected:
    static LRESULT CALLBACK s_WndProc(HWND, UINT, WPARAM, LPARAM) noexcept;

private:
    void UpdateWorkAreas(bool updateWindowPositions) noexcept;
    bool ShouldWorkAreasBeRecreated(const std::vector<FancyZonesDataTypes::MonitorId>& monitors, const GUID& virtualDesktop, const std::unordered_map<HMONITOR, std::unique_ptr<WorkArea>>& workAreas) noexcept;
    void CycleWindows(bool reverse) noexcept;
    void RotateWindowsAcrossMonitors(bool reverse) noexcept;
    void ShowMonitorRotationPreview(std::optional<bool> reverse = std::nullopt, bool animateRotation = false) noexcept;
    void HideMonitorRotationPreview() noexcept;
    void EnsureMonitorRotationContentNumbers(const std::vector<std::pair<HMONITOR, RECT>>& monitors) noexcept;
    void RotateMonitorRotationContentNumbers(bool reverse) noexcept;
    bool IsMonitorRotationActivatorKey(DWORD vkCode) const noexcept;
    bool IsMonitorRotationChordDown() const noexcept;

    void SyncVirtualDesktops() noexcept;

    void UpdateHotkey(int hotkeyId, const PowerToysSettings::HotkeyObject& hotkeyObject, bool enable) noexcept;
    
    bool MoveToAppLastZone(HWND window, HMONITOR monitor, GUID currentVirtualDesktop) noexcept;

    void RefreshLayouts() noexcept;
    bool ShouldProcessSnapHotkey(DWORD vkCode) noexcept;
    void ApplyQuickLayout(int key) noexcept;
    void FlashZones() noexcept;

    HMONITOR WorkAreaKeyFromWindow(HWND window) noexcept;

    // Dragging the seam between two snapped windows, with Shift held. See ZoneSplitter.h for the
    // geometry and MouseButtonsHook for why the click has to be taken away from the desktop.
    bool OnSplitterMouseButton(UINT message, POINT pt) noexcept;
    void SplitterMove(LPARAM lparam) noexcept;
    void SplitterEnd() noexcept;
    void SplitterApply(long to, bool settle) noexcept;
    void UpdateSplitterHook() noexcept;
    // The bar that says "there is a border under the pointer, and here is whether it will move".
    void UpdateSplitterHint(POINT pt) noexcept;
    struct SplitterDrag
    {
        // The geometry as it was when the grab began - the windows' visible frames, not the
        // layout's rects. Every frame is recomputed from these, so a neighbour that already moved
        // is not pushed a second time, and the next grab measures them again where they landed.
        ZoneSplitter::Geometry zones{};
        std::map<ZoneIndex, std::vector<HWND>> windowsByZone{};
        // Each window's own rect as it stood when the grab began. The drag moves these by a delta
        // rather than recomputing a target from measurements: the invisible border is a property of
        // the window, so adding the same delta to both sides keeps the two frames touching no matter
        // how far behind an application is in applying the request. Re-measuring it every frame is
        // what made windows overshoot, undershoot and finally tear apart.
        std::map<HWND, RECT> windowRects{};
        ZoneSplitter::Seam seam{};
        // The overlay window this drag's zone rects are expressed in. Zone coordinates are relative
        // to it, not to the screen, so both the cursor and the resulting rect have to be mapped.
        HWND workAreaWindow{};
        long minSide{};
        // Where the border actually landed. Not `lastTo`: a minimum size can stop a drag short of
        // the cursor, and the hint has to sit on the border rather than on the pointer.
        long appliedTo{};
        // Where the cursor asked for, which is what the final settled placement repeats.
        long lastTo{};
        bool active{};
        // Set when this press is the second one on the same seam: the message loop evens the split
        // once and stops listening, rather than starting a drag.
        bool equalise{};
        // The press before this one, to tell a double-click on a seam from two single drags.
        DWORD lastPressTick{};
        POINT lastPress{};
        bool lastPressVertical{};
        long lastPressAt{};
    } m_splitter;

    virtual void SettingsUpdate(SettingId type) override;

    const HINSTANCE m_hinstance{};

    HWND m_window{};
    std::unique_ptr<WindowMouseSnap> m_windowMouseSnapper{};
    WindowKeyboardSnap m_windowKeyboardSnapper{};
    WorkAreaConfiguration m_workAreaConfiguration;
    DraggingState m_draggingState;
    // The splitter's own hold on the low-level mouse hook. DraggingState only keeps that hook up
    // while a window is being dragged and only when mouse switching is on, but a press on a border
    // happens before any drag exists - so this is the other owner, and the one that is up all the
    // time. See MouseButtonsHook's reference count.
    MouseButtonsHook m_splitterHook;
    // The bar drawn on a seam while Shift is held. Click-through, so it never gets in the way of
    // the gesture it is advertising.
    SplitterHint m_splitterHint;
    bool m_monitorRotationPreviewActive = false;
    MonitorRotation::KeyState m_monitorRotationKeyState;
    std::optional<bool> m_pendingMonitorRotationReverse;
    std::unordered_map<HMONITOR, size_t> m_monitorRotationContentNumbers;

    wil::unique_handle m_terminateEditorEvent; // Handle of FancyZonesEditor.exe we launch and wait on

    OnThreadExecutor m_dpiUnawareThread;

    EventWaiter m_toggleEditorEventWaiter;

    // If non-recoverable error occurs, trigger disabling of entire FancyZones.
    static std::function<void()> disableModuleCallback;

    // Did we terminate the editor or was it closed cleanly?
    enum class EditorExitKind : byte
    {
        Exit,
        Terminate
    };

    // IDs used to register hot keys (keyboard shortcuts).
    enum class HotkeyId : int
    {
        Editor = 1,
        NextTab = 2,
        PrevTab = 3,
    };
};

std::function<void()> FancyZones::disableModuleCallback = {};

// IFancyZones
IFACEMETHODIMP_(void)
FancyZones::Run() noexcept
{
    WNDCLASSEXW wcex{};
    wcex.cbSize = sizeof(WNDCLASSEX);
    wcex.lpfnWndProc = s_WndProc;
    wcex.hInstance = m_hinstance;
    wcex.lpszClassName = NonLocalizable::ToolWindowClassName;
    RegisterClassExW(&wcex);

    BufferedPaintInit();

    m_window = CreateWindowExW(WS_EX_TOOLWINDOW, NonLocalizable::ToolWindowClassName, L"", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, m_hinstance, this);
    if (!m_window)
    {
        Logger::critical(L"Failed to create FancyZones window");
        return;
    }

    if (!KeyboardInput::Initialize(m_window))
    {
        Logger::critical(L"Failed to register raw input device");
        return;
    }

    UpdateHotkey(static_cast<int>(HotkeyId::Editor), FancyZonesSettings::settings().editorHotkey, true);
    UpdateHotkey(static_cast<int>(HotkeyId::PrevTab), FancyZonesSettings::settings().prevTabHotkey, FancyZonesSettings::settings().windowSwitching);
    UpdateHotkey(static_cast<int>(HotkeyId::NextTab), FancyZonesSettings::settings().nextTabHotkey, FancyZonesSettings::settings().windowSwitching);

    UpdateSplitterHook();

    // Initialize COM. Needed for WMI monitor identifying
    HRESULT comInitHres = CoInitializeEx(0, COINIT_MULTITHREADED);
    if (FAILED(comInitHres))
    {
        Logger::error(L"Failed to initialize COM library. {}", get_last_error_or_default(comInitHres));
        return;
    }

    // Initialize security. Needed for WMI monitor identifying
    HRESULT comSecurityInitHres = CoInitializeSecurity(NULL, -1, NULL, NULL, RPC_C_AUTHN_LEVEL_DEFAULT, RPC_C_IMP_LEVEL_IMPERSONATE, NULL, EOAC_NONE, NULL);
    if (FAILED(comSecurityInitHres))
    {
        Logger::error(L"Failed to initialize security. {}", get_last_error_or_default(comSecurityInitHres));
        return;
    }

    m_dpiUnawareThread.submit(OnThreadExecutor::task_t{ [] {
                          SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_UNAWARE);
                          SetThreadDpiHostingBehavior(DPI_HOSTING_BEHAVIOR_MIXED);
                      } })
        .wait();

    m_toggleEditorEventWaiter.start(CommonSharedConstants::FANCY_ZONES_EDITOR_TOGGLE_EVENT, [&](DWORD err) {
        if (err == ERROR_SUCCESS)
        {
            Logger::trace(L"{} event was signaled", CommonSharedConstants::FANCY_ZONES_EDITOR_TOGGLE_EVENT);
            PostMessage(m_window, WM_HOTKEY, 1, 0);
        }
    });

    SyncVirtualDesktops();

    // id format of applied-layouts and app-zone-history was changed in 0.60
    auto monitors = MonitorUtils::IdentifyMonitors();
    AppliedLayouts::instance().AdjustWorkAreaIds(monitors);
    AppZoneHistory::instance().AdjustWorkAreaIds(monitors);

    PostMessage(m_window, WM_PRIV_INIT, 0, 0);
}

// IFancyZones
IFACEMETHODIMP_(void)
FancyZones::Destroy() noexcept
{
    m_splitterHook.disable();
    m_workAreaConfiguration.Clear();
    BufferedPaintUnInit();
    if (m_window)
    {
        DestroyWindow(m_window);
        m_window = nullptr;
    }

    CoUninitialize();
}

// IFancyZonesCallback
IFACEMETHODIMP_(void)
FancyZones::VirtualDesktopChanged() noexcept
{
    // VirtualDesktopChanged is called from a reentrant WinHookProc function, therefore we must postpone the actual logic
    // until we're in FancyZones::WndProc, which is not reentrant.
    PostMessage(m_window, WM_PRIV_VD_SWITCH, 0, 0);
}

void FancyZones::MoveSizeStart(HWND window, HMONITOR monitor)
{
    m_windowMouseSnapper = WindowMouseSnap::Create(window, m_workAreaConfiguration.GetAllWorkAreas());
    if (m_windowMouseSnapper)
    {
        if (FancyZonesSettings::settings().spanZonesAcrossMonitors)
        {
            monitor = NULL;
        }

        m_draggingState.Enable();
        m_draggingState.UpdateDraggingState();
        m_windowMouseSnapper->MoveSizeStart(monitor, m_draggingState.IsDragging());
    }
}

void FancyZones::MoveSizeUpdate(HMONITOR monitor, POINT const& ptScreen)
{
    if (m_windowMouseSnapper)
    {
        if (FancyZonesSettings::settings().spanZonesAcrossMonitors)
        {
            monitor = NULL;
        }

        m_draggingState.UpdateDraggingState();
        m_windowMouseSnapper->MoveSizeUpdate(monitor, ptScreen, m_draggingState.IsDragging(), m_draggingState.IsSelectManyZonesState());
    }
}

void FancyZones::MoveSizeEnd()
{
    if (m_windowMouseSnapper)
    {
        m_windowMouseSnapper->MoveSizeEnd();
        m_windowMouseSnapper = nullptr;
    }

    // Always disable dragging state, even if m_windowMouseSnapper was already null.
    // This prevents stuck drag state when a window is destroyed mid-drag.
    m_draggingState.Disable();
}

void FancyZones::AbortMoveSize()
{
    if (m_windowMouseSnapper)
    {
        m_windowMouseSnapper->Abort();
        m_windowMouseSnapper = nullptr;
    }

    m_draggingState.Disable();
}

bool FancyZones::MoveToAppLastZone(HWND window, HMONITOR monitor, GUID currentVirtualDesktop) noexcept
{
    const auto& workAreas = m_workAreaConfiguration.GetAllWorkAreas();
    WorkArea* workArea{ nullptr };
    ZoneIndexSet indexes{};

    if (monitor)
    {    
        if (workAreas.contains(monitor))
        {
            workArea = workAreas.at(monitor).get();
            if (workArea && workArea->UniqueId().virtualDesktopId == currentVirtualDesktop)
            {
                indexes = AppZoneHistory::instance().GetAppLastZoneIndexSet(window, workArea->UniqueId(), workArea->GetLayoutId());
            }
        }
        else
        {
            Logger::error(L"Unable to find work area for requested monitor on the active virtual desktop");
        }
    }
    else
    {
        for (const auto& [_, secondaryWorkArea] : workAreas)
        {
            if (secondaryWorkArea && secondaryWorkArea->UniqueId().virtualDesktopId == currentVirtualDesktop)
            {
                indexes = AppZoneHistory::instance().GetAppLastZoneIndexSet(window, secondaryWorkArea->UniqueId(), secondaryWorkArea->GetLayoutId());
                workArea = secondaryWorkArea.get();
                if (!indexes.empty())
                {
                    break;
                }
            }
        }
    }
    
    if (!indexes.empty() && workArea)
    {
        Trace::FancyZones::SnapNewWindowIntoZone(workArea->GetLayout().get(), workArea->GetLayoutWindows());
        workArea->Snap(window, indexes);

        return true;
    }

    return false;
}

void FancyZones::WindowCreated(HWND window) noexcept
{
    const bool moveToAppLastZone = FancyZonesSettings::settings().appLastZone_moveWindows;
    const bool openOnActiveMonitor = FancyZonesSettings::settings().openWindowOnActiveMonitor;
    if (!moveToAppLastZone && !openOnActiveMonitor)
    {
        // Nothing to do here then.
        return;
    }

    if (!FancyZonesWindowProcessing::IsProcessableAutomatically(window))
    {
        return;
    }

    // Avoid already stamped (zoned) windows
    const bool isZoned = !FancyZonesWindowProperties::RetrieveZoneIndexProperty(window).empty();
    if (isZoned)
    {
        return;
    }

    HMONITOR primary = MonitorFromWindow(nullptr, MONITOR_DEFAULTTOPRIMARY);
    HMONITOR active = primary;

    POINT cursorPosition{};
    if (GetCursorPos(&cursorPosition))
    {
        active = MonitorFromPoint(cursorPosition, MONITOR_DEFAULTTOPRIMARY);
    }

    bool windowMovedToZone = false;
    auto currentVirtualDesktop = VirtualDesktop::instance().GetCurrentVirtualDesktopIdFromRegistry();
    if (moveToAppLastZone)
    {
        if (FancyZonesSettings::settings().spanZonesAcrossMonitors)
        {
            windowMovedToZone = MoveToAppLastZone(window, nullptr, currentVirtualDesktop);
        }
        else
        {
            // Search application history on currently active monitor.
            windowMovedToZone = MoveToAppLastZone(window, active, currentVirtualDesktop);

            if (!windowMovedToZone && primary != active)
            {
                // Search application history on primary monitor.
                windowMovedToZone = MoveToAppLastZone(window, primary, currentVirtualDesktop);
            }

            if (!windowMovedToZone)
            {
                // Search application history on remaining monitors.
                windowMovedToZone = MoveToAppLastZone(window, nullptr, currentVirtualDesktop);
            }
        }
    }
    

    // Open on active monitor if window wasn't zoned
    if (openOnActiveMonitor && !windowMovedToZone)
    {
        // window is recreated after switching virtual desktop
        // avoid moving already opened windows after switching vd
        bool isMoved = FancyZonesWindowProperties::RetrieveMovedOnOpeningProperty(window);
        if (!isMoved)
        {
            FancyZonesWindowProperties::StampMovedOnOpeningProperty(window);
            m_dpiUnawareThread.submit(OnThreadExecutor::task_t{ [&] { MonitorUtils::OpenWindowOnActiveMonitor(window, active); } }).wait();
        }
    }
}

// IFancyZonesCallback
IFACEMETHODIMP_(bool)
FancyZones::OnKeyDown(PKBDLLHOOKSTRUCT info) noexcept
{
    m_monitorRotationKeyState.Update(info->vkCode, true);

    // Return true to swallow the keyboard event
    bool const shift = GetAsyncKeyState(VK_SHIFT) & 0x8000;
    bool const win = GetAsyncKeyState(VK_LWIN) & 0x8000 || GetAsyncKeyState(VK_RWIN) & 0x8000;
    bool const alt = GetAsyncKeyState(VK_MENU) & 0x8000;
    bool const ctrl = GetAsyncKeyState(VK_CONTROL) & 0x8000;
    if (IsMonitorRotationChordDown())
    {
        if (!m_monitorRotationPreviewActive)
        {
            m_monitorRotationPreviewActive = true;
            PostMessageW(m_window, WM_PRIV_MONITOR_ROTATION_PREVIEW_SHOW, 0, 0);
        }

        if (info->vkCode == VK_LEFT || info->vkCode == VK_RIGHT)
        {
            if (!m_pendingMonitorRotationReverse.has_value())
            {
                const bool reverse = info->vkCode == VK_LEFT;
                PostMessageW(m_window, WM_PRIV_MONITOR_ROTATION_PREVIEW_ROTATE, static_cast<WPARAM>(reverse), 0);
            }

            m_monitorRotationKeyState.Consume(info->vkCode);
            return true;
        }

        if (IsMonitorRotationActivatorKey(info->vkCode))
        {
            m_monitorRotationKeyState.Consume(info->vkCode);
            return true;
        }

        if (IsRotationPreviewReleaseKey(info->vkCode))
        {
            return false;
        }
    }
    else if (m_monitorRotationPreviewActive)
    {
        m_monitorRotationPreviewActive = false;
        PostMessageW(m_window, WM_PRIV_MONITOR_ROTATION_PREVIEW_HIDE, 0, 0);
    }

    if ((win && !shift && !ctrl) || (win && ctrl && alt))
    {
        if ((info->vkCode == VK_RIGHT) || (info->vkCode == VK_LEFT) || (info->vkCode == VK_UP) || (info->vkCode == VK_DOWN))
        {
            if (ShouldProcessSnapHotkey(info->vkCode))
            {
                Trace::FancyZones::OnKeyDown(info->vkCode, win, ctrl, false /*inMoveSize*/);
                // Win+Left, Win+Right will cycle through Zones in the active ZoneSet when WM_PRIV_SNAP_HOTKEY's handled
                PostMessageW(m_window, WM_PRIV_SNAP_HOTKEY, 0, info->vkCode);
                return true;
            }
        }
    }

    if (FancyZonesSettings::settings().quickLayoutSwitch)
    {
        int digitPressed = -1;
        if ('0' <= info->vkCode && info->vkCode <= '9')
        {
            digitPressed = info->vkCode - '0';
        }
        else if (VK_NUMPAD0 <= info->vkCode && info->vkCode <= VK_NUMPAD9)
        {
            digitPressed = info->vkCode - VK_NUMPAD0;
        }

        bool dragging = m_draggingState.IsDragging();
        bool changeLayoutWhileNotDragging = !dragging && !shift && win && ctrl && alt && digitPressed != -1;
        // Require Win+Ctrl+Alt even while dragging to prevent accidental layout switches
        // when drag state is stuck (root cause of #410 "steals number keys")
        bool changeLayoutWhileDragging = dragging && win && ctrl && alt && digitPressed != -1;

        if (changeLayoutWhileNotDragging || changeLayoutWhileDragging)
        {
            auto layoutId = LayoutHotkeys::instance().GetLayoutId(digitPressed);
            if (layoutId.has_value())
            {
                PostMessageW(m_window, WM_PRIV_QUICK_LAYOUT_KEY, 0, static_cast<LPARAM>(digitPressed));
                Trace::FancyZones::QuickLayoutSwitched(changeLayoutWhileNotDragging);
                return true;
            }
        }
    }

    // Only suppress the bare Shift key itself during drag (used for drag-toggle).
    // Do NOT swallow Shift+<other key> combos - that steals keystrokes from apps.
    if (m_windowMouseSnapper &&
        (info->vkCode == VK_LSHIFT || info->vkCode == VK_RSHIFT))
    {
        // Record the press before swallowing it. Returning 1 removes the key from the input stream
        // for every listener - including this module's own WM_INPUT handler, which is what normally
        // calls SetShiftState - so without this the zones could never be switched off with Shift.
        m_draggingState.SetShiftState(true);
        return true;
    }
    return false;
}

IFACEMETHODIMP_(bool)
FancyZones::OnKeyUp(PKBDLLHOOKSTRUCT info) noexcept
{
    const bool wasMonitorRotationPreviewActive = m_monitorRotationPreviewActive;
    const bool isActivatorKey = IsMonitorRotationActivatorKey(info->vkCode);
    const bool wasConsumed = m_monitorRotationKeyState.ReleaseWasConsumed(info->vkCode);
    m_monitorRotationKeyState.Update(info->vkCode, false);

    if (wasMonitorRotationPreviewActive && !IsMonitorRotationChordDown())
    {
        m_monitorRotationPreviewActive = false;
        PostMessageW(m_window, WM_PRIV_MONITOR_ROTATION_PREVIEW_HIDE, 0, 0);
        return isActivatorKey || wasConsumed;
    }

    return wasConsumed;
}

bool FancyZones::IsMonitorRotationChordDown() const noexcept
{
    if (!FancyZonesSettings::settings().monitorRotation)
    {
        return false;
    }

    const auto& hotkey = FancyZonesSettings::settings().monitorRotationHotkey;
    const bool winDown = m_monitorRotationKeyState.IsAnyDown({ VK_LWIN, VK_RWIN });
    const bool ctrlDown = m_monitorRotationKeyState.IsAnyDown({ VK_CONTROL, VK_LCONTROL, VK_RCONTROL });
    const bool altDown = m_monitorRotationKeyState.IsAnyDown({ VK_MENU, VK_LMENU, VK_RMENU });
    const bool shiftDown = m_monitorRotationKeyState.IsAnyDown({ VK_SHIFT, VK_LSHIFT, VK_RSHIFT });
    return hotkey.win_pressed() == winDown &&
           hotkey.ctrl_pressed() == ctrlDown &&
           hotkey.alt_pressed() == altDown &&
           hotkey.shift_pressed() == shiftDown &&
           m_monitorRotationKeyState.IsDown(hotkey.get_code());
}

bool FancyZones::IsMonitorRotationActivatorKey(DWORD vkCode) const noexcept
{
    return vkCode == FancyZonesSettings::settings().monitorRotationHotkey.get_code();
}

namespace
{
    // Resolves a file that ships next to this module, since the installer puts both exes in the
    // same folder.
    std::wstring SiblingExecutable(const wchar_t* ownPath, const wchar_t* fileName)
    {
        std::wstring path{ ownPath };
        const size_t slash = path.find_last_of(L"\\/");
        if (slash == std::wstring::npos)
        {
            return std::wstring{ fileName };
        }

        path.resize(slash + 1);
        path += fileName;
        return path;
    }
}

void FancyZones::ToggleEditor() noexcept
{
    _TRACER_;

    if (m_terminateEditorEvent)
    {
        SetEvent(m_terminateEditorEvent.get());
        return;
    }

    m_terminateEditorEvent.reset(CreateEvent(nullptr, true, false, nullptr));

    if (!EditorParameters::Save(m_workAreaConfiguration, m_dpiUnawareThread))
    {
        Logger::error(L"Failed to save editor startup parameters");
        return;
    }

    wchar_t ownExePath[MAX_PATH] = L"";
    if (GetModuleFileNameW(NULL, ownExePath, ARRAYSIZE(ownExePath)) == 0)
    {
        Logger::error(L"Failed to resolve own executable path");
        return;
    }

    // The editor lives in its own process: a Flutter UI that ships next to this exe.
    const std::wstring uiPath = SiblingExecutable(ownExePath, L"FZonesUI.exe");
    if (GetFileAttributesW(uiPath.c_str()) == INVALID_FILE_ATTRIBUTES)
    {
        Logger::error(L"FZonesUI.exe is not next to this exe; cannot open the layout editor");
        return;
    }

    SHELLEXECUTEINFO sei{ sizeof(sei) };
    sei.fMask = { SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI };
    sei.lpFile = uiPath.c_str();
    sei.lpParameters = NonLocalizable::EditorCommandLine;
    sei.nShow = SW_SHOWDEFAULT;
    ShellExecuteEx(&sei);
    Trace::FancyZones::EditorLaunched(1);

    // Launch the editor on a background thread
    // Wait for the editor's process to exit
    // Post back to the main thread to update
    std::thread waitForEditorThread([window = m_window, processHandle = sei.hProcess, terminateEditorEvent = m_terminateEditorEvent.get()]() {
        HANDLE waitEvents[2] = { processHandle, terminateEditorEvent };
        auto result = WaitForMultipleObjects(2, waitEvents, false, INFINITE);
        if (result == WAIT_OBJECT_0 + 0)
        {
            // Editor exited
            // Update any changes it may have made
            PostMessage(window, WM_PRIV_EDITOR, 0, static_cast<LPARAM>(EditorExitKind::Exit));
        }
        else if (result == WAIT_OBJECT_0 + 1)
        {
            // User hit Win+~ while editor is already running
            // Shut it down
            TerminateProcess(processHandle, 2);
            PostMessage(window, WM_PRIV_EDITOR, 0, static_cast<LPARAM>(EditorExitKind::Terminate));
        }
        CloseHandle(processHandle);
    });

    waitForEditorThread.detach();
}

// The seam between two snapped windows, grabbed with Shift held.
//
// Why the click has to be taken away from the desktop: the border between two laid-out windows is
// inside both of them, so whatever is underneath would otherwise start its own resize the moment we
// start ours. The alternative - a topmost window sitting on the seam - is worse for clicks, focus
// and full-screen apps.

namespace
{
    // The windows a seam can trade space with: one zone each, visible, not zoomed or iconic. A side
    // with nothing that qualifies cannot give or take, which is also what turns the hint grey.
    bool SeamCandidates(WorkArea& area, const ZoneSplitter::Seam& seam, std::map<ZoneIndex, std::vector<HWND>>& windowsByZone) noexcept
    {
        windowsByZone.clear();
        for (const auto& [hwnd, indexSet] : area.GetLayoutWindows().SnappedWindows())
        {
            // WS_SIZEBOX is not decoration here: a window that cannot be resized would simply stay
            // where it is while its neighbour moves, which tears the seam open. AdjustRectForSizeWindowToRect
            // used to absorb that by quietly refusing to change the size - the border just broke.
            if (indexSet.size() != 1 || !IsWindowVisible(hwnd) || IsZoomed(hwnd) || IsIconic(hwnd)
                || (::GetWindowLong(hwnd, GWL_STYLE) & WS_SIZEBOX) == 0)
            {
                continue;
            }
            windowsByZone[indexSet.front()].push_back(hwnd);
        }

        const auto filled = [&windowsByZone](const std::vector<ZoneIndex>& side) {
            return std::any_of(side.begin(), side.end(), [&windowsByZone](ZoneIndex id) { return windowsByZone.contains(id); });
        };
        return filled(seam.nearSide) && filled(seam.farSide);
    }

    // Where each zone's window actually is, in the overlay's coordinates. The layout's own rects
    // would be easier, but they are a lie the moment a border has been dragged: they still describe
    // the proportions the layout was designed with, so the seam you grab and the seam you can see
    // stop being the same line. Zones nobody has snapped a window into keep the layout's rect,
    // which is all they can keep.
    ZoneSplitter::Geometry SeamGeometry(WorkArea& area, HWND overlay) noexcept
    {
        ZoneSplitter::Geometry geometry;
        const auto& layout = area.GetLayout();
        if (!layout || !overlay)
        {
            return geometry;
        }
        for (const auto& [id, zone] : layout->Zones())
        {
            geometry[id] = zone.GetZoneRect();
        }
        for (const auto& [hwnd, indexSet] : area.GetLayoutWindows().SnappedWindows())
        {
            if (indexSet.size() != 1 || !IsWindowVisible(hwnd) || IsZoomed(hwnd) || IsIconic(hwnd))
            {
                continue;
            }
            RECT frame{};
            if (FAILED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &frame, sizeof(frame))))
            {
                GetWindowRect(hwnd, &frame);
            }
            MapWindowRect(nullptr, overlay, &frame);
            geometry[indexSet.front()] = frame;
        }
        return geometry;
    }

    constexpr int HintThickness = 4;

    // The bar that marks a seam, in screen coordinates. Zone rectangles are relative to the overlay
    // window, so the mapping has to happen here rather than inside the hint.
    RECT SeamHintRect(const ZoneSplitter::Seam& seam, HWND workAreaWindow) noexcept
    {
        RECT rect{};
        if (seam.vertical)
        {
            rect.left = seam.at - HintThickness / 2;
            rect.right = rect.left + HintThickness;
            rect.top = seam.spanFrom;
            rect.bottom = seam.spanTo;
        }
        else
        {
            rect.top = seam.at - HintThickness / 2;
            rect.bottom = rect.top + HintThickness;
            rect.left = seam.spanFrom;
            rect.right = seam.spanTo;
        }
        MapWindowRect(workAreaWindow, nullptr, &rect);
        return rect;
    }
}

void FancyZones::UpdateSplitterHint(POINT pt) noexcept
{
    if ((GetAsyncKeyState(VK_SHIFT) & 0x8000) == 0)
    {
        m_splitterHint.Hide();
        return;
    }

    for (const auto& [monitor, area] : m_workAreaConfiguration.GetAllWorkAreas())
    {
        const auto& bounds = area->GetWorkAreaRect();
        if (pt.x < bounds.x() || pt.x >= bounds.x() + bounds.width() ||
            pt.y < bounds.y() || pt.y >= bounds.y() + bounds.height())
        {
            continue;
        }

        const HWND overlay = area->GetWorkAreaWindow();
        POINT local = pt;
        MapWindowPoints(nullptr, overlay, &local, 1);

        const auto seams = ZoneSplitter::CollectSeams(SeamGeometry(*area, overlay));
        const auto* seam = ZoneSplitter::FindSeam(seams, local);
        if (!seam)
        {
            continue;
        }

        std::map<ZoneIndex, std::vector<HWND>> candidates;
        m_splitterHint.Show(SeamHintRect(*seam, overlay), SeamCandidates(*area, *seam, candidates));
        return;
    }

    m_splitterHint.Hide();
}

bool FancyZones::OnSplitterMouseButton(UINT message, POINT pt) noexcept
{
    // Same modifier as the snap-drag, and switched off with it.
    if (!FancyZonesSettings::settings().shiftDrag)
    {
        return false;
    }

    if (m_splitter.active)
    {
        switch (message)
        {
        case WM_MOUSEMOVE:
            // Deliberately not taken from the desktop. A low-level hook runs on the thread that
            // installed it, so every event spent inside our own processing is a event the whole
            // session waits for - and the moment that thread blocks, Windows stops delivering mouse
            // input anywhere. The drag does not need the moves exclusively: the windows under the
            // cursor never saw the button go down, so a move is only a move to them.
            PostMessageW(m_window, WM_PRIV_SPLITTER_MOVE, 0, MAKELPARAM(pt.x, pt.y));
            return false;
        case WM_LBUTTONUP:
            PostMessageW(m_window, WM_PRIV_SPLITTER_END, 0, 0);
            return true;
        case WM_LBUTTONDOWN:
            // One drag at a time; a second press while captured means nothing.
            return true;
        default:
            return false;
        }
    }

    if (message == WM_MOUSEMOVE)
    {
        // The hint is the only thing that tells a person a border is under the pointer at all, and
        // it costs one key check when Shift is not held.
        UpdateSplitterHint(pt);
        return false;
    }

    if (message != WM_LBUTTONDOWN || (GetAsyncKeyState(VK_SHIFT) & 0x8000) == 0)
    {
        return false;
    }

    // Everything below is integer comparisons over one work area's zones plus a few window queries.
    // The resizing itself must NOT happen here: a low-level hook runs before the system dispatches
    // the event, and SetWindowPos talks to another process - doing it inline would stall the whole
    // mouse whenever an application is busy.
    for (const auto& [monitor, area] : m_workAreaConfiguration.GetAllWorkAreas())
    {
        const auto& bounds = area->GetWorkAreaRect();
        if (pt.x < bounds.x() || pt.x >= bounds.x() + bounds.width() ||
            pt.y < bounds.y() || pt.y >= bounds.y() + bounds.height())
        {
            continue;
        }

        // Zone rects are relative to the overlay window, not to the screen - the same mapping
        // WindowMouseSnap::MoveSizeUpdate does before matching a point against the layout.
        const HWND workAreaWindow = area->GetWorkAreaWindow();
        const auto zones = SeamGeometry(*area, workAreaWindow);
        POINT ptLocal = pt;
        MapWindowPoints(nullptr, workAreaWindow, &ptLocal, 1);

        const auto seams = ZoneSplitter::CollectSeams(zones);
        const auto* seam = ZoneSplitter::FindSeam(seams, ptLocal);
        if (!seam)
        {
            continue;
        }

        // Both sides need a window that belongs to exactly one zone. A window spanning several
        // zones, or nothing at all on one side, is not something this can trade space between.
        std::map<ZoneIndex, std::vector<HWND>> windowsByZone;
        if (!SeamCandidates(*area, *seam, windowsByZone))
        {
            continue;
        }

        const HWND sample = windowsByZone.begin()->second.front();
        const UINT dpi = GetDpiForWindow(sample);
        const long track = GetSystemMetricsForDpi(seam->vertical ? SM_CXMINTRACK : SM_CYMINTRACK, dpi);

        const ULONGLONG now = GetTickCount64();
        const bool sameSeam = m_splitter.lastPressTick != 0
            && now - m_splitter.lastPressTick <= GetDoubleClickTime()
            && seam->vertical == m_splitter.lastPressVertical
            && std::abs(seam->at - m_splitter.lastPressAt) <= ZoneSplitter::TouchTolerance
            && std::abs(pt.x - m_splitter.lastPress.x) <= 8
            && std::abs(pt.y - m_splitter.lastPress.y) <= 8;
        m_splitter.lastPressTick = static_cast<DWORD>(now);
        m_splitter.lastPress = pt;
        m_splitter.lastPressVertical = seam->vertical;
        m_splitter.lastPressAt = seam->at;

        m_splitter.zones = zones;
        m_splitter.windowsByZone = std::move(windowsByZone);
        m_splitter.windowRects.clear();
        for (const auto& [id, handles] : m_splitter.windowsByZone)
        {
            for (HWND hwnd : handles)
            {
                RECT rect{};
                if (GetWindowRect(hwnd, &rect))
                {
                    m_splitter.windowRects[hwnd] = rect;
                }
            }
        }
        m_splitter.seam = *seam;
        m_splitter.workAreaWindow = workAreaWindow;
        m_splitter.minSide = track > ZoneSplitter::MinZoneSide ? track : ZoneSplitter::MinZoneSide;
        m_splitter.lastTo = seam->at;
        m_splitter.appliedTo = seam->at;
        m_splitter.active = true;
        m_splitter.equalise = sameSeam;

        // Nothing is resized from here. This is the low-level hook, and placing a window talks to
        // another process - doing it inline is what the comment above this loop warns about, and it
        // is also what left the first frame applied while every later one was dropped.
        PostMessageW(m_window, WM_PRIV_SPLITTER_MOVE, 0, MAKELPARAM(pt.x, pt.y));
        return true;
    }

    return false;
}

void FancyZones::SplitterMove(LPARAM lparam) noexcept
{
    if (!m_splitter.active)
    {
        return;
    }
    if (!IsWindow(m_splitter.workAreaWindow))
    {
        m_splitter.active = false;
        return;
    }

    // Each frame costs a placement per window, which is slower than the mouse reports positions.
    // Anything still queued is a position this one supersedes, so drop it: the border should follow
    // the cursor rather than catch up with it.
    MSG queued{};
    while (PeekMessageW(&queued, m_window, WM_PRIV_SPLITTER_MOVE, WM_PRIV_SPLITTER_MOVE, PM_REMOVE))
    {
        lparam = queued.lParam;
    }

    POINT pt{ GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam) };
    MapWindowPoints(nullptr, m_splitter.workAreaWindow, &pt, 1);
    const long to = m_splitter.seam.vertical ? pt.x : pt.y;

    if (m_splitter.equalise)
    {
        // A second press on the same seam, close enough in time: hand both sides the same share and
        // stop listening. A one-shot move, so it can take the settled path straight away.
        m_splitter.equalise = false;
        m_splitter.active = false;
        SplitterApply(ZoneSplitter::EqualisedAt(m_splitter.zones, m_splitter.seam), true);
        return;
    }

    if (to == m_splitter.lastTo)
    {
        return;
    }
    m_splitter.lastTo = to;
    SplitterApply(to, false);
}

// The border is moved by adding one delta to both sides, never by asking "where is the invisible
// border now" per frame. That measurement is the difference between the window rect and the DWM
// frame, and while a request is still in flight the two disagree by exactly the distance of the last
// frame - which is what made windows overshoot, undershoot and finally come apart. Everything here
// is arithmetic on the rects taken when the grab began.
void FancyZones::SplitterApply(long to, bool settle) noexcept
{
    const auto moved = ZoneSplitter::ShiftedZones(m_splitter.zones, m_splitter.seam, to, m_splitter.minSide);
    if (moved.empty())
    {
        // Either nothing to do, or a minimum size has the border pinned. Both mean "leave the
        // windows alone"; the hint stays where it last actually landed.
        return;
    }

    for (ZoneIndex id : m_splitter.seam.nearSide)
    {
        const auto it = moved.find(id);
        if (it != moved.end())
        {
            m_splitter.appliedTo = m_splitter.seam.vertical ? it->second.right : it->second.bottom;
            break;
        }
    }

    const long delta = m_splitter.appliedTo - m_splitter.seam.at;
    if (delta == 0)
    {
        return;
    }

    // `near` and `far` are still function-like macros in windows.h when WIN32_LEAN_AND_MEAN has
    // not kept them out, so neither can be an identifier here.
    const auto side = [&](const std::vector<ZoneIndex>& zones, bool endingOnSeam) {
        for (ZoneIndex id : zones)
        {
            const auto windows = m_splitter.windowsByZone.find(id);
            if (windows == m_splitter.windowsByZone.end())
            {
                continue;
            }
            for (HWND hwnd : windows->second)
            {
                const auto frozen = m_splitter.windowRects.find(hwnd);
                if (!IsWindow(hwnd) || frozen == m_splitter.windowRects.end())
                {
                    continue;
                }
                RECT rect = frozen->second;
                if (m_splitter.seam.vertical)
                {
                    if (endingOnSeam) { rect.right += delta; } else { rect.left += delta; }
                }
                else
                {
                    if (endingOnSeam) { rect.bottom += delta; } else { rect.top += delta; }
                }

                if (settle)
                {
                    FancyZonesWindowUtils::SizeWindowToRect(hwnd, rect);
                }
                else
                {
                    // Async on purpose. The low-level hook and this code share one thread, and a
                    // synchronous placement waits for the other process to answer.
                    SetWindowPos(hwnd,
                                 nullptr,
                                 rect.left,
                                 rect.top,
                                 rect.right - rect.left,
                                 rect.bottom - rect.top,
                                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS);
                }
            }
        }
    };

    side(m_splitter.seam.nearSide, true);
    side(m_splitter.seam.farSide, false);

    // The bar follows the border, not the cursor, so a drag stopped by a minimum size stops
    // claiming otherwise.
    ZoneSplitter::Seam live = m_splitter.seam;
    live.at = m_splitter.appliedTo;
    m_splitterHint.Show(SeamHintRect(live, m_splitter.workAreaWindow), true);
}

void FancyZones::SplitterEnd() noexcept
{
    if (!m_splitter.active)
    {
        return;
    }
    m_splitter.active = false;

    // Let the frame the drag stopped on land the way a snap would, so the restore position and the
    // monitor scaling agree with where the border was left. Then get out of the way: the next mouse
    // move decides from scratch whether a seam is still under the pointer.
    SplitterApply(m_splitter.lastTo, true);
    m_splitterHint.Hide();
}

// A splitter grab has to be decided before the window under the cursor sees the press, which means
// the low-level mouse hook is up all the time rather than only during a drag - and every mouse event
// in the session then walks through it. So the hold is only taken while shiftDrag, the modifier the
// grab needs, is on; the handler itself checks it again because a settings change and a press can
// race.
void FancyZones::UpdateSplitterHook() noexcept
{
    if (FancyZonesSettings::settings().shiftDrag)
    {
        m_splitterHook.enable();
    }
    else
    {
        m_splitterHook.disable();
    }
}

LRESULT FancyZones::WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept
{
    switch (message)
    {
    case WM_QUERYENDSESSION:
        return TRUE;

    case WM_ENDSESSION:
        if (wparam)
        {
            // This window has no WM_DESTROY -> PostQuitMessage path, so it
            // cannot use handle_stateless_session_end_message.
            PostQuitMessage(0);
        }
        return 0;

    case WM_HOTKEY:
    {
        if (wparam == static_cast<WPARAM>(HotkeyId::Editor))
        {
            ToggleEditor();
        }
        else if (wparam == static_cast<WPARAM>(HotkeyId::NextTab) || wparam == static_cast<WPARAM>(HotkeyId::PrevTab))
        {
            bool reverse = wparam == static_cast<WPARAM>(HotkeyId::PrevTab);
            CycleWindows(reverse);
        }
    }
    break;

    case WM_INPUT:
    {
        OnKeyboardInput(wparam, reinterpret_cast<HRAWINPUT>(lparam));
    }
    break;

    case WM_SETTINGCHANGE:
    {
        if (wparam == SPI_SETWORKAREA)
        {
            // Changes in taskbar position resulted in different size of work area.
            // Invalidate cached work-areas so they can be recreated with latest information.
            OnDisplayChange(DisplayChangeType::WorkArea);
        }
    }
    break;

    case WM_DISPLAYCHANGE:
    {
        // Display resolution changed. Invalidate cached work-areas so they can be recreated with latest information.
        OnDisplayChange(DisplayChangeType::DisplayChange);
    }
    break;

    default:
    {
        POINT ptScreen;
        GetPhysicalCursorPos(&ptScreen);

        if (message == WM_PRIV_SNAP_HOTKEY)
        {
            // We already checked in ShouldProcessSnapHotkey whether the foreground window is a candidate for zoning
            auto foregroundWindow = GetForegroundWindow();

            HMONITOR monitor{ nullptr };
            if (!FancyZonesSettings::settings().spanZonesAcrossMonitors)
            {
                monitor = MonitorFromWindow(foregroundWindow, MONITOR_DEFAULTTONULL);
            }

            if (FancyZonesSettings::settings().moveWindowsBasedOnPosition)
            {
                auto monitors = FancyZonesUtils::GetAllMonitorRects<&MONITORINFOEX::rcWork>();
                RECT windowRect;
                if (GetWindowRect(foregroundWindow, &windowRect))
                {
                    // Check whether Alt is used in the shortcut key combination
                    if (GetAsyncKeyState(VK_MENU) & 0x8000)
                    {
                        m_windowKeyboardSnapper.Extend(foregroundWindow, windowRect, monitor, static_cast<DWORD>(lparam), m_workAreaConfiguration.GetAllWorkAreas());
                    }
                    else
                    {
                        m_windowKeyboardSnapper.Snap(foregroundWindow, windowRect, monitor, static_cast<DWORD>(lparam), m_workAreaConfiguration.GetAllWorkAreas(), monitors);
                    }
                }
                else
                {
                    Logger::error("Error snapping window by keyboard shortcut: failed to get window rect");
                }
            }
            else
            {
                m_windowKeyboardSnapper.Snap(foregroundWindow, monitor, static_cast<DWORD>(lparam), m_workAreaConfiguration.GetAllWorkAreas(), FancyZonesUtils::GetMonitorsOrdered());
            }
        }
        else if (message == WM_PRIV_INIT)
        {
            OnDisplayChange(DisplayChangeType::Initialization);
        }
        else if (message == WM_PRIV_VD_SWITCH)
        {
            OnDisplayChange(DisplayChangeType::VirtualDesktop);
        }
        else if (message == WM_PRIV_EDITOR)
        {
            // Clean up the event either way
            m_terminateEditorEvent.release();
        }
        else if (message == WM_PRIV_MOVESIZESTART)
        {
            auto hwnd = reinterpret_cast<HWND>(wparam);
            if (auto monitor = MonitorFromPoint(ptScreen, MONITOR_DEFAULTTONULL))
            {
                MoveSizeStart(hwnd, monitor);
                MoveSizeUpdate(monitor, ptScreen);
            }
        }
        else if (message == WM_PRIV_MOVESIZEEND)
        {
            MoveSizeEnd();
        }
        else if (message == WM_PRIV_SPLITTER_MOVE)
        {
            SplitterMove(lparam);
        }
        else if (message == WM_PRIV_SPLITTER_END)
        {
            SplitterEnd();
        }
        else if (message == WM_PRIV_LOCATIONCHANGE)
        {
            if (auto monitor = MonitorFromPoint(ptScreen, MONITOR_DEFAULTTONULL))
            {
                MoveSizeUpdate(monitor, ptScreen);
            }
        }
        else if (message == WM_PRIV_WINDOWCREATED)
        {
            auto hwnd = reinterpret_cast<HWND>(wparam);
            WindowCreated(hwnd);
        }
        else if (message == WM_PRIV_WINDOWDESTROYED)
        {
            auto hwnd = reinterpret_cast<HWND>(wparam);
            // If the destroyed window was being dragged, abort the drag without
            // snapping. Calling MoveSizeEnd() here would snap the now-destroyed
            // HWND into a zone and corrupt the layout state.
            if (m_windowMouseSnapper && m_windowMouseSnapper->GetDraggedWindow() == hwnd)
            {
                Logger::info(L"Window destroyed during drag - aborting drag");
                AbortMoveSize();
            }
        }
        else if (message == WM_PRIV_LAYOUT_HOTKEYS_FILE_UPDATE)
        {
            LayoutHotkeys::instance().LoadData();
        }
        else if (message == WM_PRIV_LAYOUT_TEMPLATES_FILE_UPDATE)
        {
            LayoutTemplates::instance().LoadData();
        }
        else if (message == WM_PRIV_CUSTOM_LAYOUTS_FILE_UPDATE)
        {
            CustomLayouts::instance().LoadData();
            RefreshLayouts();
        }
        else if (message == WM_PRIV_APPLIED_LAYOUTS_FILE_UPDATE)
        {
            AppliedLayouts::instance().LoadData();
            RefreshLayouts();
        }
        else if (message == WM_PRIV_DEFAULT_LAYOUTS_FILE_UPDATE)
        {
            DefaultLayouts::instance().LoadData();
        }
        else if (message == WM_PRIV_QUICK_LAYOUT_KEY)
        {
            ApplyQuickLayout(static_cast<int>(lparam));
        }
        else if (message == WM_PRIV_MONITOR_ROTATION_PREVIEW_SHOW)
        {
            ShowMonitorRotationPreview();
        }
        else if (message == WM_PRIV_MONITOR_ROTATION_PREVIEW_HIDE)
        {
            HideMonitorRotationPreview();
        }
        else if (message == WM_PRIV_MONITOR_ROTATION_PREVIEW_ROTATE)
        {
            const bool reverse = static_cast<bool>(wparam);
            m_pendingMonitorRotationReverse = reverse;
            ShowMonitorRotationPreview(reverse, true);
            if (SetTimer(m_window, MonitorRotationCommitTimerId, MonitorRotationCommitDelayMillis, nullptr) == 0)
            {
                m_pendingMonitorRotationReverse.reset();
                ShowMonitorRotationPreview();
            }
        }
        else if (message == WM_TIMER && wparam == MonitorRotationCommitTimerId)
        {
            KillTimer(m_window, MonitorRotationCommitTimerId);
            if (m_pendingMonitorRotationReverse.has_value())
            {
                const bool reverse = *m_pendingMonitorRotationReverse;
                const bool shouldShowCommitPreview = m_monitorRotationPreviewActive && IsMonitorRotationChordDown();
                m_pendingMonitorRotationReverse.reset();
                RotateWindowsAcrossMonitors(reverse);
                RotateMonitorRotationContentNumbers(reverse);
                if (shouldShowCommitPreview)
                {
                    ShowMonitorRotationPreview();
                }
            }
        }
        else if (message == WM_PRIV_SETTINGS_CHANGED)
        {
            FancyZonesSettings::instance().LoadSettings();
        }
        else if (message == WM_PRIV_SAVE_EDITOR_PARAMETERS)
        {
            if (!EditorParameters::Save(m_workAreaConfiguration, m_dpiUnawareThread))
            {
                Logger::warn(L"Failed to save editor-parameters.json");
            }
        }
        else
        {
            return DefWindowProc(window, message, wparam, lparam);
        }
    }
    break;
    }
    return 0;
}

void FancyZones::OnKeyboardInput(WPARAM /*flags*/, HRAWINPUT hInput) noexcept
{
    auto input = KeyboardInput::OnKeyboardInput(hInput);
    if (!input.has_value())
    {
        return;
    }

    switch (input.value().vkKey)
    {
    case VK_SHIFT:
        {
            m_draggingState.SetShiftState(input.value().pressed);
        }
        break;
    default:
        break;
    }
}

void FancyZones::OnDisplayChange(DisplayChangeType changeType) noexcept
{
    Logger::info(L"Display changed, type: {}", DisplayChangeTypeName(changeType));

    bool updateWindowsPositions = false;

    switch (changeType)
    {
    case DisplayChangeType::WorkArea: // WorkArea size changed
    case DisplayChangeType::DisplayChange: // Resolution changed or display added
        updateWindowsPositions = FancyZonesSettings::settings().displayOrWorkAreaChange_moveWindows;
        break;
    case DisplayChangeType::VirtualDesktop: // Switched virtual desktop
        SyncVirtualDesktops();
        break;
    case DisplayChangeType::Initialization: // Initialization
        updateWindowsPositions = FancyZonesSettings::settings().zoneSetChange_moveWindows;
        break;
    default:
        break;
    }

    UpdateWorkAreas(updateWindowsPositions);
}

bool FancyZones::AddWorkArea(HMONITOR monitor, const FancyZonesDataTypes::WorkAreaId& id, const FancyZonesUtils::Rect& rect) noexcept
{
    auto virtualDesktopIdStr = FancyZonesUtils::GuidToString(id.virtualDesktopId);
    if (virtualDesktopIdStr)
    {
        Logger::debug(L"Add new work area on virtual desktop {}", virtualDesktopIdStr.value());
    }

    auto parentWorkAreaId = id;
    parentWorkAreaId.virtualDesktopId = LastUsedVirtualDesktop::instance().GetId();

    auto workArea = WorkArea::Create(m_hinstance, id, parentWorkAreaId, rect);
    if (!workArea)
    {
        Logger::error(L"Failed to create work area {}", id.toString());
        return false;
    }
    
    m_workAreaConfiguration.AddWorkArea(monitor, std::move(workArea));
    return true;
}

LRESULT CALLBACK FancyZones::s_WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept
{
    auto thisRef = reinterpret_cast<FancyZones*>(GetWindowLongPtr(window, GWLP_USERDATA));
    if (!thisRef && (message == WM_CREATE))
    {
        const auto createStruct = reinterpret_cast<LPCREATESTRUCT>(lparam);
        thisRef = static_cast<FancyZones*>(createStruct->lpCreateParams);
        SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(thisRef));
    }

    return thisRef ? thisRef->WndProc(window, message, wparam, lparam) :
                     DefWindowProc(window, message, wparam, lparam);
}

void FancyZones::UpdateWorkAreas(bool updateWindowPositions) noexcept
{
    Logger::debug(L"Update work areas, update windows positions: {}", updateWindowPositions);

    auto currentVirtualDesktop = VirtualDesktop::instance().GetCurrentVirtualDesktopIdFromRegistry();

    if (FancyZonesSettings::settings().spanZonesAcrossMonitors)
    {
        std::vector<FancyZonesDataTypes::MonitorId> monitors = { FancyZonesDataTypes::MonitorId{ .monitor = nullptr, .deviceId = { .id = ZonedWindowProperties::MultiMonitorName, .instanceId = ZonedWindowProperties::MultiMonitorInstance } } };
        if (ShouldWorkAreasBeRecreated(monitors, currentVirtualDesktop, m_workAreaConfiguration.GetAllWorkAreas()))
        {
            // WindowMouseSnap caches a raw WorkArea* in m_currentWorkArea and the
            // WorkArea map by reference. WorkAreaConfiguration::Clear() destroys
            // every unique_ptr<WorkArea> (and hence the inner ZonesOverlay and
            // its std::mutex). If a drag is in flight, the next MoveSizeUpdate
            // would dereference that dangling WorkArea* and lock the freed
            // mutex. Abort the active drag first so subsequent drag messages
            // hit the snapper's `if (m_windowMouseSnapper)` guard and no-op.
            AbortMoveSize();
            m_workAreaConfiguration.Clear();

            FancyZonesDataTypes::WorkAreaId workAreaId;
            workAreaId.virtualDesktopId = currentVirtualDesktop;
            workAreaId.monitorId = { .deviceId = { .id = ZonedWindowProperties::MultiMonitorName, .instanceId = ZonedWindowProperties::MultiMonitorInstance } };

            AddWorkArea(nullptr, workAreaId, FancyZonesUtils::GetAllMonitorsCombinedRect<&MONITORINFO::rcWork>());
        }
    }
    else
    {
        auto monitors = MonitorUtils::IdentifyMonitors();
        const auto& workAreas = m_workAreaConfiguration.GetAllWorkAreas();
        
        if (ShouldWorkAreasBeRecreated(monitors, currentVirtualDesktop, workAreas))
        {
            // See comment above the matching Clear() in the span-zones branch.
            AbortMoveSize();
            m_workAreaConfiguration.Clear();
            for (const auto& monitor : monitors)
            {
                FancyZonesDataTypes::WorkAreaId workAreaId;
                workAreaId.virtualDesktopId = currentVirtualDesktop;
                workAreaId.monitorId = monitor;

                AddWorkArea(monitor.monitor, workAreaId, MonitorUtils::GetWorkAreaRect(monitor.monitor));
            }
        }
    }

    // init previously snapped windows
    std::unordered_map<HWND, ZoneIndexSet> windowsToSnap{};
    for (const auto& window : VirtualDesktop::instance().GetWindowsFromCurrentDesktop())
    {
        auto indexes = FancyZonesWindowProperties::RetrieveZoneIndexProperty(window);
        if (indexes.size() == 0)
        {
            continue;
        }

        windowsToSnap.insert({ window, indexes });
    }

    if (FancyZonesSettings::settings().spanZonesAcrossMonitors) // one work area across monitors
    {
        const auto workArea = m_workAreaConfiguration.GetWorkArea(nullptr);
        if (workArea)
        {
            for (const auto& [window, zones] : windowsToSnap)
            {
                workArea->Snap(window, zones, false);
            }
        }
    }
    else
    {
        // first, snap windows to the monitor where they're placed
        for (auto iter = windowsToSnap.begin(); iter != windowsToSnap.end();)
        {
            const auto window = iter->first;
            const auto zones = iter->second;
            const auto monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
            const auto workAreaForMonitor = m_workAreaConfiguration.GetWorkArea(monitor);
            if (workAreaForMonitor && AppZoneHistory::instance().GetAppLastZoneIndexSet(window, workAreaForMonitor->UniqueId(), workAreaForMonitor->GetLayoutId()) == zones)
            {
                workAreaForMonitor->Snap(window, zones, false);
                iter = windowsToSnap.erase(iter);
            }
            else
            {
                ++iter;
            }
        }

        // snap rest of the windows to other work areas (in case they were moved after the monitor unplug)
        for (const auto& [window, zones] : windowsToSnap)
        {
            for (const auto& [_, workArea] : m_workAreaConfiguration.GetAllWorkAreas())
            {
                const auto savedIndexes = AppZoneHistory::instance().GetAppLastZoneIndexSet(window, workArea->UniqueId(), workArea->GetLayoutId());
                if (savedIndexes == zones)
                {
                    workArea->Snap(window, zones, false);
                }
            }
        }
    }

    if (updateWindowPositions)
    {
        for (const auto& [_, workArea] : m_workAreaConfiguration.GetAllWorkAreas())
        {
            if (workArea)
            {
                workArea->UpdateWindowPositions();
            }
        }
    }
}

bool FancyZones::ShouldWorkAreasBeRecreated(const std::vector<FancyZonesDataTypes::MonitorId>& monitors, const GUID& virtualDesktop, const std::unordered_map<HMONITOR, std::unique_ptr<WorkArea>>& workAreas) noexcept
{
    if (monitors.size() != workAreas.size())
    {
        Logger::trace(L"Monitor was added or removed");
        return true;
    }

    for (const auto& monitor : monitors)
    {
        auto iter = workAreas.find(monitor.monitor);
        if (iter == workAreas.end())
        {
            Logger::trace(L"WorkArea not found");
            return true;
        }

        if (iter->second->UniqueId().monitorId.deviceId != monitor.deviceId)
        {
            Logger::trace(L"DeviceId changed");
            return true;
        }

        if (iter->second->UniqueId().monitorId.serialNumber != monitor.serialNumber)
        {
            Logger::trace(L"Serial number changed");
            return true;
        }

        if (iter->second->UniqueId().virtualDesktopId != virtualDesktop)
        {
            Logger::trace(L"Virtual desktop changed");
            return true;
        }

        const auto rect = monitor.monitor ? MonitorUtils::GetWorkAreaRect(monitor.monitor) : FancyZonesUtils::Rect(FancyZonesUtils::GetMonitorsCombinedRect<&MONITORINFOEX::rcWork>(FancyZonesUtils::GetAllMonitorRects<&MONITORINFOEX::rcWork>()));
        if (iter->second->GetWorkAreaRect() != rect)
        {
            Logger::trace(L"WorkArea size changed");
            return true;
        }
    }

    return false;
}

void FancyZones::CycleWindows(bool reverse) noexcept
{
    auto window = GetForegroundWindow();
    HMONITOR current = WorkAreaKeyFromWindow(window);

    auto workArea = m_workAreaConfiguration.GetWorkArea(current);
    if (workArea)
    {
        workArea->CycleWindows(window, reverse);
    }
}

void FancyZones::ShowMonitorRotationPreview(std::optional<bool> reverse, bool animateRotation) noexcept
{
    auto windows = CollectWindowRotationSnapshots();
    std::unordered_map<HMONITOR, std::vector<RECT>> windowRectsByMonitor;
    for (const auto& window : windows)
    {
        windowRectsByMonitor[window.sourceMonitor].push_back(window.sourceRect);
    }

    auto monitors = FancyZonesUtils::GetAllMonitorRects<&MONITORINFOEX::rcWork>();
    FancyZonesUtils::OrderMonitors(monitors);
    EnsureMonitorRotationContentNumbers(monitors);

    if (FancyZonesSettings::settings().spanZonesAcrossMonitors)
    {
        auto workArea = m_workAreaConfiguration.GetWorkArea(nullptr);
        if (workArea)
        {
            std::vector<RECT> allWindowRects;
            allWindowRects.reserve(windows.size());
            for (const auto& window : windows)
            {
                allWindowRects.push_back(window.sourceRect);
            }

            workArea->ShowMonitorRotationPreview(allWindowRects, 1, reverse, animateRotation);
        }

        m_monitorRotationPreviewActive = true;
        return;
    }

    for (const auto& [monitor, workArea] : m_workAreaConfiguration.GetAllWorkAreas())
    {
        if (!workArea)
        {
            continue;
        }

        const auto iter = windowRectsByMonitor.find(monitor);
        const std::vector<RECT> emptyRects;
        const auto monitorNumberIter = m_monitorRotationContentNumbers.find(monitor);
        const size_t monitorNumber = monitorNumberIter != m_monitorRotationContentNumbers.end() ? monitorNumberIter->second : GetMonitorDisplayNumber(monitor, 1);
        workArea->ShowMonitorRotationPreview(iter != windowRectsByMonitor.end() ? iter->second : emptyRects, monitorNumber, reverse, animateRotation);
    }

    m_monitorRotationPreviewActive = true;
}

void FancyZones::EnsureMonitorRotationContentNumbers(const std::vector<std::pair<HMONITOR, RECT>>& monitors) noexcept
{
    if (monitors.empty())
    {
        m_monitorRotationContentNumbers.clear();
        return;
    }

    bool shouldReinitialize = m_monitorRotationContentNumbers.size() != monitors.size();
    if (!shouldReinitialize)
    {
        for (const auto& [monitor, _] : monitors)
        {
            if (!m_monitorRotationContentNumbers.contains(monitor))
            {
                shouldReinitialize = true;
                break;
            }
        }
    }

    if (!shouldReinitialize)
    {
        return;
    }

    m_monitorRotationContentNumbers.clear();
    for (size_t monitorIndex = 0; monitorIndex < monitors.size(); monitorIndex++)
    {
        m_monitorRotationContentNumbers[monitors[monitorIndex].first] = GetMonitorDisplayNumber(monitors[monitorIndex].first, monitorIndex + 1);
    }
}

void FancyZones::RotateMonitorRotationContentNumbers(bool reverse) noexcept
{
    auto monitors = FancyZonesUtils::GetAllMonitorRects<&MONITORINFOEX::rcWork>();
    FancyZonesUtils::OrderMonitors(monitors);
    EnsureMonitorRotationContentNumbers(monitors);

    if (monitors.size() < 2)
    {
        return;
    }

    std::unordered_map<HMONITOR, size_t> rotatedContentNumbers;
    for (size_t sourceIndex = 0; sourceIndex < monitors.size(); sourceIndex++)
    {
        const size_t targetIndex = MonitorRotation::GetRotatedMonitorIndex(sourceIndex, monitors.size(), reverse);
        rotatedContentNumbers[monitors[targetIndex].first] = m_monitorRotationContentNumbers[monitors[sourceIndex].first];
    }

    m_monitorRotationContentNumbers = std::move(rotatedContentNumbers);
}

void FancyZones::HideMonitorRotationPreview() noexcept
{
    for (const auto& [_, workArea] : m_workAreaConfiguration.GetAllWorkAreas())
    {
        if (workArea)
        {
            workArea->HideZones();
        }
    }

    m_monitorRotationPreviewActive = false;
    if (!m_pendingMonitorRotationReverse.has_value())
    {
        KillTimer(m_window, MonitorRotationCommitTimerId);
    }
}

void FancyZones::RotateWindowsAcrossMonitors(bool reverse) noexcept
{
    auto monitors = FancyZonesUtils::GetAllMonitorRects<&MONITORINFOEX::rcWork>();
    FancyZonesUtils::OrderMonitors(monitors);
    if (monitors.size() < 2)
    {
        Logger::info(L"Monitor rotation skipped: fewer than two monitors are available");
        return;
    }

    auto windows = CollectWindowRotationSnapshots();
    if (windows.empty())
    {
        Logger::info(L"Monitor rotation skipped: no processable windows found");
        return;
    }

    size_t movedWindows = 0;
    for (const auto& window : windows)
    {
        const auto sourceIndex = FindMonitorIndex(window.sourceMonitor, monitors);
        if (!sourceIndex.has_value())
        {
            continue;
        }

        const size_t targetIndex = MonitorRotation::GetRotatedMonitorIndex(*sourceIndex, monitors.size(), reverse);
        const RECT targetRect = MonitorRotation::MapRectBetweenMonitorWorkAreas(
            window.sourceRect,
            monitors[*sourceIndex].second,
            monitors[targetIndex].second);
        if (!FancyZonesWindowProperties::RetrieveZoneIndexProperty(window.window).empty())
        {
            if (auto workArea = m_workAreaConfiguration.GetWorkAreaFromWindow(window.window))
            {
                workArea->Unsnap(window.window);
            }
        }

        FancyZonesWindowUtils::SizeWindowToRect(window.window, targetRect, false);
        movedWindows++;
    }

    Logger::info(L"Rotated {} windows across {} monitors", movedWindows, monitors.size());
}

void FancyZones::SyncVirtualDesktops() noexcept
{
    // Explorer persists current virtual desktop identifier to registry on a per session basis,
    // but only after first virtual desktop switch happens. If the user hasn't switched virtual
    // desktops in this session value in registry will be empty and we will use default GUID in
    // that case (00000000-0000-0000-0000-000000000000).

    auto lastUsed = LastUsedVirtualDesktop::instance().GetId();
    auto current = VirtualDesktop::instance().GetCurrentVirtualDesktopIdFromRegistry();
    auto guids = VirtualDesktop::instance().GetVirtualDesktopIdsFromRegistry();

    if (current != lastUsed)
    {
        LastUsedVirtualDesktop::instance().SetId(current);
        LastUsedVirtualDesktop::instance().SaveData();
    }

    AppliedLayouts::instance().SyncVirtualDesktops(current, lastUsed, guids);
    AppZoneHistory::instance().SyncVirtualDesktops(current, lastUsed, guids);
}

void FancyZones::UpdateHotkey(int hotkeyId, const PowerToysSettings::HotkeyObject& hotkeyObject, bool enable) noexcept
{
    if (!m_window)
    {
        return;
    }

    UnregisterHotKey(m_window, hotkeyId);

    if (!enable)
    {
        return;
    }

    auto modifiers = hotkeyObject.get_modifiers();
    auto code = hotkeyObject.get_code();
    auto result = RegisterHotKey(m_window, hotkeyId, modifiers, code);

    if (!result)
    {
        Logger::error(L"Failed to register hotkey: {}", get_last_error_or_default(GetLastError()));
    }
}

void FancyZones::SettingsUpdate(SettingId id)
{
    switch (id)
    {
    case SettingId::EditorHotkey:
    {
        UpdateHotkey(static_cast<int>(HotkeyId::Editor), FancyZonesSettings::settings().editorHotkey, true);
    }
    break;
    case SettingId::WindowSwitching:
    {
        UpdateHotkey(static_cast<int>(HotkeyId::PrevTab), FancyZonesSettings::settings().prevTabHotkey, FancyZonesSettings::settings().windowSwitching);
        UpdateHotkey(static_cast<int>(HotkeyId::NextTab), FancyZonesSettings::settings().nextTabHotkey, FancyZonesSettings::settings().windowSwitching);
    }
    break;
    case SettingId::PrevTabHotkey:
    {
        UpdateHotkey(static_cast<int>(HotkeyId::PrevTab), FancyZonesSettings::settings().prevTabHotkey, FancyZonesSettings::settings().windowSwitching);
    }
    break;
    case SettingId::NextTabHotkey:
    {
        UpdateHotkey(static_cast<int>(HotkeyId::NextTab), FancyZonesSettings::settings().nextTabHotkey, FancyZonesSettings::settings().windowSwitching);
    }
    break;
    case SettingId::MonitorRotation:
    case SettingId::MonitorRotationHotkey:
    {
        m_pendingMonitorRotationReverse.reset();
        KillTimer(m_window, MonitorRotationCommitTimerId);
        m_monitorRotationKeyState.Reset();
        if (m_monitorRotationPreviewActive && !IsMonitorRotationChordDown())
        {
            HideMonitorRotationPreview();
        }
    }
    break;
    case SettingId::SpanZonesAcrossMonitors:
    {
        // See UpdateWorkAreas() — same WindowMouseSnap dangling-WorkArea*
        // hazard if the user toggles this setting mid-drag.
        AbortMoveSize();
        m_workAreaConfiguration.Clear();
        PostMessageW(m_window, WM_PRIV_INIT, NULL, NULL);
    }
    break;
    case SettingId::ShiftDrag:
    {
        UpdateSplitterHook();
    }
    break;
    default:
        break;
    }
}

void FancyZones::RefreshLayouts() noexcept
{
    for (const auto& [_, workArea] : m_workAreaConfiguration.GetAllWorkAreas())
    {
        if (workArea)
        {
            workArea->InitLayout();

            if (FancyZonesSettings::settings().zoneSetChange_moveWindows)
            {
                workArea->UpdateWindowPositions();
            }
        }
    }
}

bool FancyZones::ShouldProcessSnapHotkey(DWORD vkCode) noexcept
{
    if (!FancyZonesSettings::settings().overrideSnapHotkeys)
    {
        return false;
    }

    auto window = GetForegroundWindow();
    if (!FancyZonesWindowProcessing::IsProcessableManually(window))
    {
        return false;
    }

    HMONITOR monitor = WorkAreaKeyFromWindow(window);

    auto workArea = m_workAreaConfiguration.GetWorkArea(monitor);
    if (!workArea)
    {
        Logger::error(L"No work area for processing snap hotkey");
        return false;
    }

    const auto& layout = workArea->GetLayout();
    if (!layout)
    {
        Logger::error(L"No layout for processing snap hotkey");
        return false;
    }

    if (layout->Zones().size() > 0)
    {
        if (vkCode == VK_UP || vkCode == VK_DOWN)
        {
            return FancyZonesSettings::settings().moveWindowsBasedOnPosition;
        }
        else
        {
            return true;
        }
    }

    return false;
}

void FancyZones::ApplyQuickLayout(int key) noexcept
{
    auto layoutId = LayoutHotkeys::instance().GetLayoutId(key);
    if (!layoutId)
    {
        return;
    }

    // Find a custom zone set with this uuid and apply it
    auto layout = CustomLayouts::instance().GetLayout(layoutId.value());
    if (!layout)
    {
        return;
    }

    auto workArea = m_workAreaConfiguration.GetWorkAreaFromCursor();
    if (workArea)
    {
        if (AppliedLayouts::instance().ApplyLayout(workArea->UniqueId(), layout.value()))
        {
            RefreshLayouts();
            FlashZones();
            AppliedLayouts::instance().SaveData();
        }
    }
}

void FancyZones::FlashZones() noexcept
{
    if (FancyZonesSettings::settings().flashZonesOnQuickSwitch && !m_draggingState.IsDragging())
    {
        for (const auto& [_, workArea] : m_workAreaConfiguration.GetAllWorkAreas())
        {
            if (workArea)
            {
                workArea->FlashZones();
            }
        }
    }
}

HMONITOR FancyZones::WorkAreaKeyFromWindow(HWND window) noexcept
{
    if (FancyZonesSettings::settings().spanZonesAcrossMonitors)
    {
        return NULL;
    }
    else
    {
        return MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
    }
}

winrt::com_ptr<IFancyZones> MakeFancyZones(HINSTANCE hinstance, std::function<void()> disableCallback) noexcept
{
    return winrt::make_self<FancyZones>(hinstance, disableCallback);
}
