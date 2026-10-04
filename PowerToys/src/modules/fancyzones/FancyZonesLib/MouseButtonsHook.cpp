#include "pch.h"
#include "MouseButtonsHook.h"
#include <common/debug_control.h>

#pragma region public

HHOOK MouseButtonsHook::hHook = {};
int MouseButtonsHook::m_owners = 0;
std::function<void()> MouseButtonsHook::secondaryClickCallback = {};
std::function<void()> MouseButtonsHook::middleClickCallback = {};
MouseButtonsHook::LeftButtonHandler MouseButtonsHook::leftButtonHandler = {};

void MouseButtonsHook::setLeftButtonHandler(LeftButtonHandler handler)
{
    leftButtonHandler = std::move(handler);
}

MouseButtonsHook::MouseButtonsHook(std::function<void()> extRightClickCallback, std::function<void()> extMiddleClickCallback)
{
    secondaryClickCallback = std::move(extRightClickCallback);
    middleClickCallback = std::move(extMiddleClickCallback);
}

void MouseButtonsHook::enable()
{
    if (m_acquired)
    {
        return;
    }
#if defined(DISABLE_LOWLEVEL_HOOKS_WHEN_DEBUGGED)
    if (IsDebuggerPresent())
    {
        return;
    }
#endif
    m_acquired = true;
    ++m_owners;
    if (!hHook)
    {
        hHook = SetWindowsHookEx(WH_MOUSE_LL, MouseButtonsProc, GetModuleHandle(NULL), 0);
    }
}

void MouseButtonsHook::disable()
{
    if (!m_acquired)
    {
        return;
    }
    m_acquired = false;
    --m_owners;
    if (m_owners <= 0)
    {
        m_owners = 0;
        if (hHook)
        {
            UnhookWindowsHookEx(hHook);
            hHook = NULL;
        }
    }
}

#pragma endregion

#pragma region private

LRESULT CALLBACK MouseButtonsHook::MouseButtonsProc(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode == HC_ACTION)
    {
        if (wParam == WM_LBUTTONDOWN || wParam == WM_LBUTTONUP || wParam == WM_MOUSEMOVE)
        {
            if (leftButtonHandler)
            {
                const MSLLHOOKSTRUCT* info = reinterpret_cast<const MSLLHOOKSTRUCT*>(lParam);
                if (leftButtonHandler(static_cast<UINT>(wParam), info->pt))
                {
                    // Ours. The matching button-up has to come to us as well, or whatever is under
                    // the cursor believes it is still being clicked.
                    return 1;
                }
            }
        }

        if (wParam == WM_RBUTTONDOWN || wParam == WM_XBUTTONDOWN)
        {
            if (secondaryClickCallback)
            {
                secondaryClickCallback();
            }
        }
        else if (wParam == WM_MBUTTONDOWN && middleClickCallback)
        {
            middleClickCallback();
        }
    }
    return CallNextHookEx(hHook, nCode, wParam, lParam);
}

#pragma endregion
