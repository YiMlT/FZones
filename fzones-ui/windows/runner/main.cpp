#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // One window per role, whichever way it was asked for - the engine's hotkey, the tray, the
  // gear in the other window, or a double click. A second launch either raises the window that is
  // already open or, when the engine sent it, closes that window - the toggle the user expects
  // from the hotkey even when the editor was started by hand. This happens before anything is
  // built, because that is the cheapest place to find out.
  const single_instance::Role role = single_instance::RoleFromCommandLine();
  const bool toggle = single_instance::ToggleRequested();
  if (!single_instance::Claim(role, toggle)) {
    printf("FZones: the %s window was already open - %s it instead.\n",
           role == single_instance::Role::editor ? "editor" : "settings",
           toggle ? "closed" : "raised");
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(command_line_arguments);

  FlutterWindow window(project);
  // The same logical sizes as the native windows (700 for settings, 880 for the editor), so the
  // two implementations can be compared side by side without rescaling. Where the window ends up is
  // not decided here: the role's remembered position, or a centred default, is applied in
  // FlutterWindow::OnCreate once the handle exists.
  const bool editor = role == single_instance::Role::editor;
  Win32Window::Point origin(10, 10);
  Win32Window::Size size = editor ? Win32Window::Size(880, 620) : Win32Window::Size(700, 560);
  window.SetRole(role);
  if (!window.Create(single_instance::TitleFor(role), origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
