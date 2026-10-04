#pragma once

#include <Windows.h>

// The one thing a seam looks like before it is grabbed: a thin bar lying on the border, one colour
// when the drag would actually start and another when it would not. It is disabled, click-through
// and never activated, so everything underneath still receives the mouse exactly as it did before
// this window existed - which is the whole reason a hint can be drawn at all.
class SplitterHint
{
public:
    SplitterHint() = default;
    ~SplitterHint();

    SplitterHint(const SplitterHint&) = delete;
    SplitterHint(SplitterHint&&) = delete;
    SplitterHint& operator=(const SplitterHint&) = delete;

    // rect is in screen coordinates. Re-showing the same bar with the same state does nothing, so
    // this is safe to call from a mouse-move handler.
    void Show(const RECT& rect, bool draggable);
    void Hide();

private:
    static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);

    bool EnsureWindow();

    HWND m_window{};
    RECT m_rect{};
    bool m_draggable{};
    bool m_visible{};
};
