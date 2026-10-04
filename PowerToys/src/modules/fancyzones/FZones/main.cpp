#include "pch.h"

#include <shellapi.h>
#include <wil/resource.h>

#include <common/interop/shared_constants.h>
#include <common/utils/logger_helper.h>
#include <common/utils/resources.h>
#include <common/utils/UnhandledExceptionHandler.h>
#include <common/utils/winapi_error.h>
#include <common/utils/window.h>

#include <FancyZonesLib/Generated Files/resource.h>
#include <FancyZonesLib/ModuleConstants.h>
#include <FancyZonesLib/trace.h>

#include <vector>

#include "AppSettings.h"
#include "FancyZonesApp.h"
#include "FZonesStrings.h"
#include "TrayIcon.h"

namespace
{
    const std::wstring appName = L"FZones";
    const std::wstring instanceMutexName = L"Local\\FZones_InstanceMutex";
    // This exe is the engine and the tray only; both windows live in the Flutter UI next to it.
    constexpr wchar_t UI_EXE_NAME[] = L"FZonesUI.exe";

    void LaunchUi(const wchar_t* arguments)
    {
        wchar_t path[MAX_PATH] = L"";
        if (GetModuleFileNameW(NULL, path, ARRAYSIZE(path)) == 0)
        {
            return;
        }

        std::wstring uiPath{ path };
        const size_t slash = uiPath.find_last_of(L"\\/");
        uiPath = (slash == std::wstring::npos) ? std::wstring{ UI_EXE_NAME }
                                              : uiPath.substr(0, slash + 1) + UI_EXE_NAME;

        if (GetFileAttributesW(uiPath.c_str()) == INVALID_FILE_ATTRIBUTES)
        {
            Logger::error(L"FZonesUI.exe is not next to this exe; cannot open a window");
            return;
        }

        ShellExecuteW(NULL, L"open", uiPath.c_str(), arguments, NULL, SW_SHOWNORMAL);
    }

    // The engine already listens for this event and opens the editor itself, which also refreshes
    // editor-parameters.json - so the tray asks rather than launching with stale monitor data.
    void RequestEditorFromEngine()
    {
        wil::unique_handle event{ OpenEventW(EVENT_MODIFY_STATE, FALSE, CommonSharedConstants::FANCY_ZONES_EDITOR_TOGGLE_EVENT) };
        if (!event)
        {
            event.reset(CreateEventW(nullptr, FALSE, FALSE, CommonSharedConstants::FANCY_ZONES_EDITOR_TOGGLE_EVENT));
        }

        if (event)
        {
            SetEvent(event.get());
        }
    }
}

int WINAPI wWinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance, _In_ PWSTR lpCmdLine, _In_ int nCmdShow)
{
    (void)hPrevInstance;
    (void)nCmdShow;

    winrt::init_apartment();
    LoggerHelpers::init_logger(appName, L"", LogSettings::fancyZonesLoggerName);

    InitUnhandledExceptionHandler();
    AppSettings::Load();
    // The settings page is another process; this is how a language change it makes reaches the
    // tray menu of an engine that is already running.
    AppSettings::Watch();

    const wil::unique_handle mutex{ CreateMutexW(nullptr, TRUE, instanceMutexName.c_str()) };
    if (!mutex)
    {
        Logger::error(L"Failed to create instance mutex. {}", get_last_error_or_default(GetLastError()));
    }

    if (GetLastError() == ERROR_ALREADY_EXISTS)
    {
        Logger::warn(L"FZones is already running");
        return 0;
    }

    Trace::RegisterProvider();

    FancyZonesApp app(GET_RESOURCE_STRING(IDS_FANCYZONES), NonLocalizable::ModuleKey);
    const DWORD mainThreadId = GetCurrentThreadId();

    std::vector<TrayMenuItem> menu;
    // Each label is a lookup rather than a string, so the menu is in the language the settings page
    // last chose instead of the one that happened to be current when the engine started.
    menu.push_back({ [] { return Loc::T(STR_TRAY_EDIT_LAYOUTS); }, RequestEditorFromEngine });
    menu.push_back({ [] { return Loc::T(STR_TRAY_SETTINGS); }, [] { LaunchUi(L"--settings"); } });
    menu.push_back({ [mainThreadId] {
                       return Loc::T(STR_TRAY_EXIT);
                   },
                     [mainThreadId] {
                       PostThreadMessageW(mainThreadId, WM_QUIT, 0, 0);
                   } });
    TrayIcon tray(appName, std::move(menu), RequestEditorFromEngine);

    app.Run();
    run_message_loop();

    Trace::UnregisterProvider();

    return 0;
}
