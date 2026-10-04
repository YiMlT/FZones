#pragma once

#include <shellapi.h>

#include <functional>
#include <string>
#include <vector>

struct TrayMenuItem
{
    /// Resolved when the menu is opened, not when the tray icon is created - the app's language can
    /// change while the process runs.
    std::function<std::wstring()> label;
    std::function<void()> action;
};

// Hidden message window owning the shell notification icon. The icon is the only way to
// reach the process once it no longer runs under a runner that owns the tray.
class TrayIcon
{
public:
    TrayIcon(const std::wstring& tooltip, std::vector<TrayMenuItem> items, std::function<void()> onClick = {});
    ~TrayIcon();

    TrayIcon(const TrayIcon&) = delete;
    TrayIcon& operator=(const TrayIcon&) = delete;

    bool IconVisible() const noexcept
    {
        return m_iconAdded;
    }

private:
    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    void HandleTrayMessage(LPARAM lParam);
    void ShowContextMenu();

    HWND m_hwnd = nullptr;
    NOTIFYICONDATAW m_nid = {};
    std::vector<TrayMenuItem> m_items;
    std::function<void()> m_onClick;
    bool m_iconAdded = false;

    static constexpr UINT TRAY_CALLBACK_MSG = WM_APP + 1;
    static constexpr UINT_PTR TRAY_ICON_UID = 1;
    static constexpr UINT MENU_ID_BASE = 1;
};
