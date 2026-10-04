#include "pch.h"
#include "TrayIcon.h"

#include <shellapi.h>

#include <common/utils/winapi_error.h>

namespace
{
    constexpr wchar_t WINDOW_CLASS[] = L"FZonesTrayWindowClass";
    constexpr wchar_t WINDOW_TITLE[] = L"FZonesTrayWindow";

    // The shell's own tray takes the small variant, so Explorer, Alt-Tab and the notification
    // area all agree with the exe's icon group.
    HICON LoadOwnIcon(bool preferSmall)
    {
        wchar_t path[MAX_PATH] = L"";
        if (GetModuleFileNameW(NULL, path, ARRAYSIZE(path)) == 0)
        {
            return nullptr;
        }

        // "small" is a macro in rpcndr.h, hence the names.
        HICON largeIcon = nullptr;
        HICON smallIcon = nullptr;
        ExtractIconExW(path, 0, &largeIcon, &smallIcon, 1);
        return preferSmall ? smallIcon : largeIcon;
    }
}

TrayIcon::TrayIcon(const std::wstring& tooltip, std::vector<TrayMenuItem> items, std::function<void()> onClick) :
    m_items{ std::move(items) },
    m_onClick{ std::move(onClick) }
{
    WNDCLASSW windowClass{};
    windowClass.lpfnWndProc = WndProc;
    windowClass.hInstance = GetModuleHandle(NULL);
    windowClass.lpszClassName = WINDOW_CLASS;
    if (!RegisterClassW(&windowClass) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        Logger::error(L"TrayIcon: RegisterClassW failed. {}", get_last_error_or_default(GetLastError()));
        return;
    }

    m_hwnd = CreateWindowExW(0,
                             WINDOW_CLASS,
                             WINDOW_TITLE,
                             WS_POPUP,
                             CW_USEDEFAULT,
                             CW_USEDEFAULT,
                             0,
                             0,
                             NULL,
                             NULL,
                             windowClass.hInstance,
                             this);
    if (!m_hwnd)
    {
        Logger::error(L"TrayIcon: CreateWindowExW failed. {}", get_last_error_or_default(GetLastError()));
        return;
    }

    m_nid.cbSize = sizeof(NOTIFYICONDATAW);
    m_nid.hWnd = m_hwnd;
    m_nid.uID = TRAY_ICON_UID;
    m_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    m_nid.uCallbackMessage = TRAY_CALLBACK_MSG;
    m_nid.hIcon = LoadOwnIcon(true);
    if (!m_nid.hIcon)
    {
        m_nid.hIcon = LoadIconW(NULL, IDI_APPLICATION);
    }
    wcsncpy_s(m_nid.szTip, tooltip.c_str(), _TRUNCATE);

    m_iconAdded = Shell_NotifyIconW(NIM_ADD, &m_nid) != FALSE;
    if (!m_iconAdded)
    {
        Logger::error(L"TrayIcon: Shell_NotifyIcon NIM_ADD failed");
    }
}

TrayIcon::~TrayIcon()
{
    if (m_iconAdded)
    {
        Shell_NotifyIconW(NIM_DELETE, &m_nid);
        m_iconAdded = false;
    }

    if (m_hwnd)
    {
        DestroyWindow(m_hwnd);
        m_hwnd = nullptr;
    }
}

LRESULT CALLBACK TrayIcon::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    TrayIcon* self = nullptr;
    if (msg == WM_NCCREATE)
    {
        self = static_cast<TrayIcon*>(reinterpret_cast<CREATESTRUCTW*>(lParam)->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<TrayIcon*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }

    if (self && msg == TRAY_CALLBACK_MSG)
    {
        self->HandleTrayMessage(lParam);
        return 0;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

void TrayIcon::HandleTrayMessage(LPARAM lParam)
{
    switch (LOWORD(lParam))
    {
    case WM_LBUTTONUP:
        // A single click is the fastest way back to the layouts; the menu stays on the right button.
        if (m_onClick)
        {
            m_onClick();
        }
        break;
    case WM_RBUTTONUP:
    case WM_CONTEXTMENU:
        ShowContextMenu();
        break;
    default:
        break;
    }
}

void TrayIcon::ShowContextMenu()
{
    POINT clickPos{};
    GetCursorPos(&clickPos);

    HMENU menu = CreatePopupMenu();
    if (!menu)
    {
        return;
    }

    for (size_t i = 0; i < m_items.size(); ++i)
    {
        AppendMenuW(menu, MF_STRING, static_cast<UINT>(MENU_ID_BASE + i), m_items[i].label ? m_items[i].label().c_str() : L"");
        if (i + 1 < m_items.size())
        {
            AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        }
    }

    // Without the foreground hand-off the popup refuses to dismiss on the outside click.
    SetForegroundWindow(m_hwnd);
    const UINT chosen = TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, clickPos.x, clickPos.y, m_hwnd, NULL);
    DestroyMenu(menu);

    const int index = static_cast<int>(chosen) - MENU_ID_BASE;
    if (index >= 0 && index < static_cast<int>(m_items.size()) && m_items[static_cast<size_t>(index)].action)
    {
        m_items[static_cast<size_t>(index)].action();
    }

    PostMessageW(m_hwnd, WM_NULL, 0, 0);
}
