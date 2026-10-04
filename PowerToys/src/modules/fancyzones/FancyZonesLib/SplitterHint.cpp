#include "pch.h"
#include "SplitterHint.h"

namespace
{
    const wchar_t ClassName[] = L"FZonesSplitterHint";

    // Green for "this border will move", grey for "there is a border here, but it will not". Neither
    // of them is one of the zone colours on purpose: the zone overlay means "let go here and the
    // window lands in this zone", which is a different offer.
    const COLORREF DraggableColor = RGB(60, 203, 127);
    const COLORREF BlockedColor = RGB(150, 150, 150);

    constexpr BYTE Alpha = 210;
}

SplitterHint::~SplitterHint()
{
    if (m_window)
    {
        DestroyWindow(m_window);
        m_window = nullptr;
    }
}

bool SplitterHint::EnsureWindow()
{
    if (m_window)
    {
        return true;
    }

    HINSTANCE instance = GetModuleHandle(nullptr);
    static bool registered = false;
    if (!registered)
    {
        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(wc);
        wc.lpfnWndProc = WndProc;
        wc.hInstance = instance;
        wc.lpszClassName = ClassName;
        if (!RegisterClassExW(&wc))
        {
            return false;
        }
        registered = true;
    }

    // WS_EX_TRANSPARENT is what makes this invisible to the mouse; WS_EX_LAYERED lets it fade
    // slightly, which keeps a 4px bar from looking like part of an application's own frame.
    m_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_LAYERED,
                               ClassName,
                               L"",
                               WS_POPUP | WS_DISABLED,
                               0,
                               0,
                               0,
                               0,
                               nullptr,
                               nullptr,
                               instance,
                               nullptr);
    if (!m_window)
    {
        return false;
    }

    SetLayeredWindowAttributes(m_window, 0, Alpha, LWA_ALPHA);
    return true;
}

void SplitterHint::Show(const RECT& rect, bool draggable)
{
    const bool same = m_visible && m_draggable == draggable && EqualRect(&m_rect, &rect);
    if (same)
    {
        return;
    }
    if (!EnsureWindow())
    {
        return;
    }

    m_rect = rect;
    m_draggable = draggable;
    m_visible = true;

    SetWindowLongPtrW(m_window, GWLP_USERDATA, static_cast<LONG_PTR>(draggable ? DraggableColor : BlockedColor));
    SetWindowPos(m_window,
                 HWND_TOPMOST,
                 rect.left,
                 rect.top,
                 rect.right - rect.left,
                 rect.bottom - rect.top,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(m_window, nullptr, FALSE);
}

void SplitterHint::Hide()
{
    if (!m_visible)
    {
        return;
    }
    m_visible = false;
    if (m_window)
    {
        ShowWindow(m_window, SW_HIDE);
    }
}

LRESULT CALLBACK SplitterHint::WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    switch (message)
    {
    case WM_ERASEBKGND:
        // WM_PAINT below covers every pixel; erasing first would flash the class background.
        return 1;

    case WM_PAINT:
    {
        PAINTSTRUCT ps{};
        HDC dc = BeginPaint(window, &ps);
        const COLORREF color = static_cast<COLORREF>(GetWindowLongPtrW(window, GWLP_USERDATA));
        HBRUSH brush = CreateSolidBrush(color);
        FillRect(dc, &ps.rcPaint, brush);
        DeleteObject(brush);
        EndPaint(window, &ps);
        return 0;
    }

    case WM_NCHITTEST:
        // Belt to WS_EX_TRANSPARENT's braces: never a target, not even for the frame.
        return HTTRANSPARENT;
    }

    return DefWindowProcW(window, message, wparam, lparam);
}
