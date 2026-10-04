#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

namespace frame {

// Chrome metrics in logical pixels, mirroring FzMetrics in lib/design.dart.
constexpr int kRadiusLogical = 8;
constexpr int kMinWidthLogical = 620;
constexpr int kMinHeightLogical = 420;

}  // namespace frame

using WindowResult =
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;

namespace single_instance {

// Which of the two windows this process was started for. Both live in the same exe, so each one
// is its own instance: one editor and one settings page can be open at the same time, but a
// second launch of either raises the window that is already there.
enum class Role { editor, settings };

Role RoleFromCommandLine();

// Whether this launch came from the engine's toggle (the hotkey or the tray) rather than from a
// click. The engine cannot tell which window is already open, so it always asks for a toggle and
// leaves the decision to the process that holds the role: raise that window, or close it.
bool ToggleRequested();

// The window title, which is also how another process of the same role finds it.
const wchar_t* TitleFor(Role role);

// Takes the single-instance lock for this role. Returns false when a window of this role already
// holds it - having asked it to come forward, or to close, so the caller must exit without
// creating anything.
bool Claim(Role role, bool close_existing);

// Asks an already-open window of this role to come forward (`false`) or to close (`true`). True
// when one was there to ask.
bool NotifyExisting(Role role, bool close);

// Handles what NotifyExisting posted. True when this is one of those two messages. A process
// other than the foreground one cannot raise a window, and cannot close someone else's either, so
// both answers have to come from inside the target.
bool HandleRequest(HWND window, UINT message);

}  // namespace single_instance

// A window that does nothing but host a Flutter view.
//
// The Flutter side draws its own app bar and frame, so this window has no native caption:
// WM_NCCALCSIZE reports the whole window as client area and the 8px corner radius comes from DWM
// (or a region cut where DWM ignores the attribute). The Flutter view is a child window covering
// every pixel, so Windows never asks *this* window what is under the cursor - dragging and
// resizing therefore come in through the fzones/window channel, which re-enters the system's own
// non-client loops on our behalf.
class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Which of the two windows this is. Set before Create, because the placement of the window is
  // remembered per role and the editor and the settings page must not trade places.
  void SetRole(single_instance::Role role) { role_ = role; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Where this window belongs: the last place it was closed at, or - the first time - centred on
  // the monitor the cursor is on, with the settings page centred on the editor instead.
  void ApplyPlacement();
  void SavePlacement();

  // Applies (or removes) the rounded window region. No-op unless DWM ignored the corner
  // preference, which is the Windows 10 case.
  void ApplyRoundedRegion();

  // Tells the Dart side the maximized state, which decides the radius it paints.
  void ReportWindowState();

  // Runs one of the system's non-client mouse loops: HTCAPTION drags the window, the HT* resize
  // codes resize it. Blocks for the duration of the gesture, pumping messages while it does.
  void BeginNcMouse(WPARAM hit_test);

  // The window controls the custom app bar needs, and the geometry-free version of a system
  // caption: drag and resize arrive as verbs because Windows never hit-tests this window while
  // the Flutter view covers it.
  void HandleWindowCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      WindowResult result);

  LRESULT OnNcCalcSize(HWND hwnd, NCCALCSIZE_PARAMS* params);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // True when DWM ignored DWMWA_WINDOW_CORNER_PREFERENCE and the region cut is doing the work.
  bool region_rounding_ = false;

  bool was_maximized_ = false;

  single_instance::Role role_ = single_instance::Role::settings;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
