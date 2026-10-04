#pragma once

#include <common/hooks/LowlevelKeyboardEvent.h>
#include <common/utils/EventWaiter.h>

#include <FancyZonesLib/FancyZones.h>

namespace FZones
{
    // Own stop channel, so a PowerToys install toggling its own FancyZones cannot signal this process.
    inline constexpr const wchar_t EXIT_EVENT[] = L"Local\\FZones-ExitEvent-6c1f0b9d-3f2a-4a1e-9b7c-8d5e2f4a1c63";
}

class FancyZonesApp
{
public:
    FancyZonesApp(const std::wstring& appName, const std::wstring& appKey);
    ~FancyZonesApp();

    void Run();

private:
    static inline FancyZonesApp* s_instance = nullptr;
    static inline HHOOK s_llKeyboardHook = nullptr;

    winrt::com_ptr<IFancyZones> m_app;
    HWINEVENTHOOK m_objectLocationWinEventHook = nullptr;
    std::vector<HWINEVENTHOOK> m_staticWinEventHooks;

    EventWaiter m_exitEventWaiter;
    DWORD m_mainThreadId;

    void DisableModule() noexcept;

    void InitHooks();

    void HandleWinHookEvent(WinHookEvent* data) noexcept;
    intptr_t HandleKeyboardHookEvent(LowlevelKeyboardEvent* data) noexcept;

    static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam)
    {
        LowlevelKeyboardEvent event;
        if (nCode == HC_ACTION && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN || wParam == WM_KEYUP || wParam == WM_SYSKEYUP))
        {
            event.lParam = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
            event.wParam = wParam;
            if (s_instance)
            {
                if (s_instance->HandleKeyboardHookEvent(&event) == 1)
                {
                    return 1;
                }
            }
        }
        return CallNextHookEx(NULL, nCode, wParam, lParam);
    }

    static void CALLBACK WinHookProc(HWINEVENTHOOK winEventHook,
                                     DWORD event,
                                     HWND window,
                                     LONG object,
                                     LONG child,
                                     DWORD eventThread,
                                     DWORD eventTime)
    {
        WinHookEvent data{ event, window, object, child, eventThread, eventTime };
        if (s_instance)
        {
            s_instance->HandleWinHookEvent(&data);
        }
    }
};
