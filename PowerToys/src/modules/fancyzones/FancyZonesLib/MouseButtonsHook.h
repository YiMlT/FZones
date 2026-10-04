#pragma once

#include <functional>

class MouseButtonsHook
{
public:
    // Returning true takes the event away from the desktop. That is how a splitter drag can begin
    // on the border between two windows without those windows starting a resize of their own a
    // moment later - the alternative is a topmost window under the cursor, which is worse for
    // clicks, focus and full-screen apps.
    using LeftButtonHandler = std::function<bool(UINT message, POINT pt)>;

    // Leaves the mouse-switch callbacks alone: an owner that only cares about the left button has
    // no say over what a right or middle click does.
    MouseButtonsHook() = default;
    MouseButtonsHook(std::function<void()>, std::function<void()>);

    // Reference counted, because the two owners want very different lifetimes: mouse switching only
    // needs the hook while a window is being dragged, the splitter needs it whenever a press could
    // land on a border - which is before any drag exists. The hook goes away when the last owner
    // lets go.
    void enable();
    void disable();

    static void setLeftButtonHandler(LeftButtonHandler handler);

private:
    static HHOOK hHook;
    static int m_owners;
    bool m_acquired{};

    static std::function<void()> middleClickCallback;
    static std::function<void()> secondaryClickCallback;
    static LeftButtonHandler leftButtonHandler;
    static LRESULT CALLBACK MouseButtonsProc(int, WPARAM, LPARAM);
};
