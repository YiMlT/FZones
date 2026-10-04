#include "flutter_window.h"

#include <dwmapi.h>

#include <cwctype>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

/// HKCU\...\Run, the same entry the installer writes. `FZones` has to stay identical to RUN_VALUE
/// in the engine's AppSettings.cpp and to !define RUN_VALUE in installer/fzones.nsi, or the
/// settings toggle and the installer end up managing different entries.
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"FZones";
/// The engine is what has to run at sign-in - it owns the hotkeys, the tray and the zoning - and it
/// sits next to this exe. Same sibling rule the engine uses to find us, in reverse.
constexpr wchar_t kEngineName[] = L"FZones.exe";

/// The engine next to this exe, or empty when this checkout has none: a build straight out of
/// `flutter build` runs on its own, and only the installer puts the two exes side by side.
std::wstring EnginePath() {
  wchar_t path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, path, MAX_PATH) == 0) {
    return std::wstring();
  }
  const std::wstring own{ path };
  const size_t slash = own.find_last_of(L"\\/");
  if (slash == std::wstring::npos) {
    return std::wstring();
  }
  const std::wstring sibling = own.substr(0, slash + 1) + kEngineName;
  if (GetFileAttributesW(sibling.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return std::wstring();
  }
  return sibling;
}

/// Whether sign-in will start the engine, and whether this build can arrange that at all. The
/// second answer is what lets the switch show itself as unavailable rather than silently refusing.
flutter::EncodableValue AutostartState() {
  DWORD size = 0;
  const bool enabled =
      RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ, nullptr,
                   nullptr, &size) == ERROR_SUCCESS;
  flutter::EncodableMap state;
  state[flutter::EncodableValue("enabled")] = flutter::EncodableValue(enabled);
  state[flutter::EncodableValue("managed")] =
      flutter::EncodableValue(!EnginePath().empty());
  return flutter::EncodableValue(state);
}

/// The write itself, in the shape AppSettings.cpp's SetAutostartEnabled uses: a quoted path, so a
/// program files location with a space in it still starts.
bool WriteAutostart(bool enabled) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) != ERROR_SUCCESS) {
    return false;
  }

  LSTATUS status = ERROR_SUCCESS;
  if (enabled) {
    const std::wstring engine = EnginePath();
    if (engine.empty()) {
      status = ERROR_FILE_NOT_FOUND;
    } else {
      const std::wstring quoted = L"\"" + engine + L"\"";
      status = RegSetValueExW(key, kRunValue, 0, REG_SZ,
                              reinterpret_cast<const BYTE*>(quoted.c_str()),
                              static_cast<DWORD>((quoted.size() + 1) * sizeof(wchar_t)));
    }
  } else {
    status = RegDeleteValueW(key, kRunValue);
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;  // already off is off
    }
  }

  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

bool ReadBoolArgument(const flutter::EncodableValue* arguments, const std::string& key) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return false;
  }
  const auto found = map->find(flutter::EncodableValue(key));
  if (found == map->end()) {
    return false;
  }
  const bool* value = std::get_if<bool>(&found->second);
  return value != nullptr && *value;
}

/// Window attribute that rounds the frame corners.
///
/// Redefined in case the build machine has a Windows SDK older than 10.0.22000.0.
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
constexpr DWORD kCornerPreferenceRound = 2;  // DWMWCP_ROUND

constexpr char kChannelName[] = "fzones/window";

// Logical -> physical for *this* window, which is the only dpi that matters when a
// second monitor has a different scale factor.
int ScaleLogical(HWND hwnd, int logical) {
  UINT dpi = GetDpiForWindow(hwnd);
  return MulDiv(logical, dpi == 0 ? 96 : dpi, 96);
}

/// The resize handles the Dart side puts over the window's own edges.
WPARAM HitTestForEdge(const std::string& edge) {
  if (edge == "left") return HTLEFT;
  if (edge == "right") return HTRIGHT;
  if (edge == "top") return HTTOP;
  if (edge == "bottom") return HTBOTTOM;
  if (edge == "topLeft") return HTTOPLEFT;
  if (edge == "topRight") return HTTOPRIGHT;
  if (edge == "bottomLeft") return HTBOTTOMLEFT;
  if (edge == "bottomRight") return HTBOTTOMRIGHT;
  return HTCLIENT;
}

std::string ReadEdge(
    const flutter::EncodableValue* arguments) {
  const auto* args = std::get_if<flutter::EncodableMap>(arguments);
  if (args == nullptr) {
    return std::string();
  }
  const auto found = args->find(flutter::EncodableValue("edge"));
  if (found == args->end()) {
    return std::string();
  }
  const auto* text = std::get_if<std::string>(&found->second);
  return text == nullptr ? std::string() : *text;
}

/// The two objects that make this process the one owner of its window role: the mutex that holds
/// the role open for as long as the process lives, and the registered messages that tell the
/// window holding it to come forward or to close. All of them are named after the executable's own
/// path, so an installed release and a debug build off the same source are different programs and
/// never hold each other off, while two launches of the *same* exe are exactly what is prevented.
HANDLE g_instance_mutex = nullptr;
UINT g_activate_message = 0;
UINT g_close_message = 0;

/// Lower-cased with every punctuation flattened, so a path fits in an object name.
std::wstring PathKey() {
  wchar_t path[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring key;
  for (DWORD i = 0; i < length; ++i) {
    const wchar_t c = path[i];
    const bool alnum = (c >= L'a' && c <= L'z') || (c >= L'A' && c <= L'Z') ||
                       (c >= L'0' && c <= L'9');
    key += alnum ? static_cast<wchar_t>(towlower(c)) : L'_';
  }
  return key;
}

const wchar_t* RoleKey(single_instance::Role role) {
  return role == single_instance::Role::editor ? L"editor" : L"settings";
}

std::wstring MutexName(single_instance::Role role) {
  return L"Local\\FZonesUI_" + PathKey() + L"_" + RoleKey(role) + L"_Mutex";
}

/// `verb` is L"Activate" or L"Close". Both processes derive it from the same inputs, which is why
/// the window titles never have to become a contract between two executables.
UINT RequestMessage(single_instance::Role role, const wchar_t* verb) {
  return RegisterWindowMessageW(
      (L"FZonesUI_" + PathKey() + L"_" + RoleKey(role) + L"_" + verb).c_str());
}

/// Launches this same exe with no arguments, which is the settings window: the runner picks
/// the window from the command line, and `--editor` is what makes it the layout editor.
void LaunchSettingsWindow() {
  // Already open is the common case once the gear has been used once, and raising it beats
  // starting a process whose only job would be to raise it.
  if (single_instance::NotifyExisting(single_instance::Role::settings, false)) {
    return;
  }

  wchar_t path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, path, MAX_PATH) == 0) {
    return;
  }
  std::wstring command_line = std::wstring(1, L'"') + path + L'"';

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  if (CreateProcessW(path, command_line.data(), nullptr, nullptr, FALSE, 0, nullptr,
                     nullptr, &startup, &process)) {
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }
}

/// Where each window was when it last closed. The registry rather than a file because that is what
/// window placement is for on Windows, it is per-user with no path for two processes to disagree
/// about, and a stale entry costs nothing.
constexpr wchar_t kPlacementKey[] = L"Software\\FZones\\Windows";

bool ReadSavedPlacement(const wchar_t* name, RECT& out) {
  wchar_t buffer[64] = {};
  DWORD size = sizeof(buffer);
  if (RegGetValueW(HKEY_CURRENT_USER, kPlacementKey, name, RRF_RT_REG_SZ, nullptr,
                   buffer, &size) != ERROR_SUCCESS) {
    return false;
  }
  if (swscanf_s(buffer, L"%d,%d,%d,%d", &out.left, &out.top, &out.right,
                &out.bottom) != 4) {
    return false;
  }
  return out.right > out.left && out.bottom > out.top;
}

void WriteSavedPlacement(const wchar_t* name, const RECT& rect) {
  wchar_t buffer[64] = {};
  swprintf(buffer, 64, L"%d,%d,%d,%d", rect.left, rect.top, rect.right,
           rect.bottom);
  HKEY key = nullptr;
  // Nine arguments: this SDK declares lpdwDisposition on RegCreateKeyExW, and unlike the
  // documentation the header will not accept a call without it.
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kPlacementKey, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(buffer),
                 static_cast<DWORD>((wcslen(buffer) + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
}

RECT WorkAreaOfPoint(POINT pt) {
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  GetMonitorInfoW(MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST), &info);
  return info.rcWork;
}

RECT CenteredIn(const RECT& area, int width, int height) {
  RECT rect = {};
  rect.left = area.left + ((area.right - area.left) - width) / 2;
  rect.top = area.top + ((area.bottom - area.top) - height) / 2;
  rect.right = rect.left + width;
  rect.bottom = rect.top + height;
  return rect;
}

/// Keeps a rect on a monitor that still exists. A remembered position is only worth restoring while
/// some screen covers it - and a window restored onto a monitor that has since been unplugged
/// cannot be dragged back, so this pulls it in instead of trusting the entry.
RECT ClampToWorkArea(const RECT& rect) {
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  GetMonitorInfoW(MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST), &info);
  const RECT work = info.rcWork;

  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  const bool reachable = rect.left < work.right && rect.right > work.left &&
                         rect.top < work.bottom && rect.bottom > work.top;
  if (!reachable) {
    return CenteredIn(work, width, height);
  }
  int left = rect.left;
  int top = rect.top;
  if (left + width > work.right) left = work.right - width;
  if (left < work.left) left = work.left;
  if (top + height > work.bottom) top = work.bottom - height;
  if (top < work.top) top = work.top;

  RECT out = {};
  out.left = left;
  out.top = top;
  out.right = left + width;
  out.bottom = top + height;
  return out;
}

/// The engine's own instance mutex, named exactly as FZones/main.cpp creates it.
constexpr wchar_t kEngineMutexName[] = L"Local\\FZones_InstanceMutex";

/// Follows the engine's lifetime. The hotkeys, the tray and the zoning all live in that process, so
/// a window of this one has nothing left to talk to once it is gone - and asking the engine to close
/// us on the way out would only cover a clean exit. Waiting on the mutex is abandoned the moment its
/// last handle closes, which hears about a crash and a taskkill the same way.
void WatchEngineLifetime(single_instance::Role role) {
  std::thread([role] {
    HANDLE mutex = OpenMutexW(SYNCHRONIZE, FALSE, kEngineMutexName);
    if (mutex == nullptr) {
      return;  // no engine to follow: a UI started on its own keeps its window
    }
    WaitForSingleObject(mutex, INFINITE);
    CloseHandle(mutex);
    // Ask by role rather than posting to a saved handle: this window may already be gone, and a
    // handle recycled by some other process must not be closed by us.
    single_instance::NotifyExisting(role, true);
  }).detach();
}

}  // namespace

namespace single_instance {

Role RoleFromCommandLine() {
  const std::vector<std::string> arguments = GetCommandLineArguments();
  for (const std::string& argument : arguments) {
    if (argument == "--editor") {
      return Role::editor;
    }
  }
  return Role::settings;
}

bool ToggleRequested() {
  const std::vector<std::string> arguments = GetCommandLineArguments();
  for (const std::string& argument : arguments) {
    if (argument == "--toggle") {
      return true;
    }
  }
  return false;
}

const wchar_t* TitleFor(Role role) {
  // The same two titles the Dart side draws into its own app bar.
  return role == Role::editor ? L"FZones \u5e03\u5c40\u7f16\u8f91\u5668"
                              : L"FZones \u8bbe\u7f6e";
}

bool NotifyExisting(Role role, bool close) {
  HWND existing = FindWindowW(Win32Window::GetWindowClass(), TitleFor(role));
  if (existing == nullptr) {
    return false;
  }
  if (!close) {
    // Only the foreground process may hand over the right to come forward, and the caller is the
    // one the user just acted on. The window does the raising itself, see HandleRequest.
    DWORD owner_process = 0;
    GetWindowThreadProcessId(existing, &owner_process);
    if (owner_process != 0) {
      AllowSetForegroundWindow(owner_process);
    }
  }
  PostMessageW(existing, RequestMessage(role, close ? L"Close" : L"Activate"), 0, 0);
  return true;
}

bool Claim(Role role, bool close_existing) {
  g_activate_message = RequestMessage(role, L"Activate");
  g_close_message = RequestMessage(role, L"Close");
  if (g_activate_message == 0 || g_close_message == 0) {
    return true;  // cannot name the messages; two windows beat no window
  }
  HANDLE mutex = CreateMutexW(nullptr, TRUE, MutexName(role).c_str());
  if (mutex == nullptr) {
    return true;  // same reasoning
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(mutex);
    // Somebody else holds the role. Stand down after telling that window what to do - but if
    // there is no window to tell, it is on its way out, and opening one here beats opening none.
    return !NotifyExisting(role, close_existing);
  }
  // Held for the lifetime of the process; the OS releases it when this exits.
  g_instance_mutex = mutex;
  return true;
}

bool HandleRequest(HWND window, UINT message) {
  if (g_close_message != 0 && message == g_close_message) {
    // Not DestroyWindow from inside one of this window's own messages: this is the same exit a
    // click on the close button takes, so the view and the Dart side shut down as usual.
    PostMessageW(window, WM_CLOSE, 0, 0);
    return true;
  }
  if (g_activate_message == 0 || message != g_activate_message) {
    return false;
  }
  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  }
  SetForegroundWindow(window);
  return true;
}

}  // namespace single_instance

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Before the view exists: the surface is created at the client size measured just below, so a
  // window that moves after that pays for it with a resize during startup.
  ApplyPlacement();
  WatchEngineLifetime(role_);

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             WindowResult result) { HandleWindowCall(call, std::move(result)); });

  // Win11 rounds the frame for us and antialiases it; Win10 fails the attribute call, and the
  // region cut in ApplyRoundedRegion takes over. Deliberately *not* setting
  // DWMWA_BORDER_COLOR: that would stack a second, system-drawn line outside ours.
  const DWORD corner_preference = kCornerPreferenceRound;
  region_rounding_ =
      FAILED(DwmSetWindowAttribute(GetHandle(), DWMWA_WINDOW_CORNER_PREFERENCE,
                                   &corner_preference, sizeof(corner_preference)));

  // WS_CAPTION stays set: clearing it makes GetWindowText fall back to the class name, which
  // costs the taskbar label and every tool that finds the window by title. The caption that
  // would otherwise be painted is suppressed by the WM_NCPAINT / WM_NCACTIVATE answers below.
  //
  // The caption is gone, so the non-client frame has to be recomputed from scratch.
  SetWindowPos(GetHandle(), nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);

  // Before the window is ever shown, not only from WM_SIZE. On Windows 10 the corner preference
  // above fails, so the rounded region is the only thing clipping the frame - and between
  // ShowWindow and the first WM_SIZE the system still had a full caption to paint, which is the
  // flash that came and went depending on how fast the first frame landed.
  ApplyRoundedRegion();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ApplyPlacement() {
  HWND hwnd = GetHandle();
  RECT current = {};
  GetWindowRect(hwnd, &current);
  const int width = current.right - current.left;
  const int height = current.bottom - current.top;

  RECT rect = {};
  bool placed = false;
  if (ReadSavedPlacement(RoleKey(role_), rect)) {
    rect = ClampToWorkArea(rect);
    placed = true;
  } else if (role_ == single_instance::Role::settings) {
    // The settings page belongs to the window that opened it, so the first time it comes up it
    // lands on top of that one instead of somewhere the user then has to go looking for.
    HWND main = FindWindowW(Win32Window::GetWindowClass(),
                            single_instance::TitleFor(single_instance::Role::editor));
    RECT anchor = {};
    if (main != nullptr && GetWindowRect(main, &anchor)) {
      rect = ClampToWorkArea(CenteredIn(anchor, width, height));
      placed = true;
    }
  }
  if (!placed) {
    POINT cursor = {};
    GetCursorPos(&cursor);
    rect = CenteredIn(WorkAreaOfPoint(cursor), width, height);
  }

  SetWindowPos(hwnd, nullptr, rect.left, rect.top, rect.right - rect.left,
               rect.bottom - rect.top,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void FlutterWindow::SavePlacement() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr || IsZoomed(hwnd) != FALSE || IsIconic(hwnd)) {
    // A maximized rect is half off its monitor and a minimized one is parked at -32000; neither is
    // a position worth remembering, so the last honest one stays in the registry.
    return;
  }
  RECT rect = {};
  if (GetWindowRect(hwnd, &rect)) {
    WriteSavedPlacement(RoleKey(role_), rect);
  }
}

void FlutterWindow::OnDestroy() {
  channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleWindowCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    WindowResult result) {
  const std::string& method = call.method_name();
  HWND hwnd = GetHandle();

  if (method == "minimize") {
    ShowWindow(hwnd, SW_MINIMIZE);
  } else if (method == "close") {
    DestroyWindow(hwnd);
  } else if (method == "toggleMaximize") {
    ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
  } else if (method == "openSettings") {
    LaunchSettingsWindow();
  } else if (method == "startDrag") {
    BeginNcMouse(HTCAPTION);
  } else if (method == "startResize") {
    const WPARAM hit_test = HitTestForEdge(ReadEdge(call.arguments()));
    if (hit_test == HTCLIENT) {
      result->Error("bad_edge", "startResize needs a known edge");
      return;
    }
    BeginNcMouse(hit_test);
  } else if (method == "isMaximized") {
    result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
    return;
  } else if (method == "getAutostart") {
    result->Success(AutostartState());
    return;
  } else if (method == "setAutostart") {
    // The reply is the state after the write, not whether it worked: the switch then always shows
    // what the registry says, even when the engine was missing or the key refused us.
    WriteAutostart(ReadBoolArgument(call.arguments(), "enabled"));
    result->Success(AutostartState());
    return;
  } else {
    result->NotImplemented();
    return;
  }
  result->Success();
}

void FlutterWindow::BeginNcMouse(WPARAM hit_test) {
  // The pointer is already down and captured by the Flutter view. Releasing it and posting the
  // non-client button message hands the gesture to DefWindowProc, which runs its own modal loop:
  // that is what gives us the system drag, the system resize feedback, Snap Assist on the caption
  // and the double-click that maximizes - none of which reimplement here.
  ReleaseCapture();
  SendMessageW(GetHandle(), WM_NCLBUTTONDOWN, hit_test, 0);
}

void FlutterWindow::ReportWindowState() {
  const bool maximized = IsZoomed(GetHandle()) != FALSE;
  if (maximized == was_maximized_) {
    return;
  }
  was_maximized_ = maximized;
  if (channel_ == nullptr) {
    return;
  }
  flutter::EncodableMap state{
      {flutter::EncodableValue("maximized"), flutter::EncodableValue(maximized)}};
  channel_->InvokeMethod("onStateChanged",
                         std::make_unique<flutter::EncodableValue>(state));
}

void FlutterWindow::ApplyRoundedRegion() {
  if (!region_rounding_) {
    return;
  }
  HWND hwnd = GetHandle();
  RECT client = {};
  GetClientRect(hwnd, &client);
  if (IsZoomed(hwnd) || client.right <= 0 || client.bottom <= 0) {
    SetWindowRgn(hwnd, nullptr, TRUE);
    return;
  }
  const int diameter = 2 * ScaleLogical(hwnd, frame::kRadiusLogical);
  HRGN region = CreateRoundRectRgn(0, 0, client.right + 1, client.bottom + 1,
                                   diameter, diameter);
  if (region == nullptr) {
    return;
  }
  // A successful SetWindowRgn hands ownership of the region to the system.
  if (!SetWindowRgn(hwnd, region, TRUE)) {
    DeleteObject(region);
  }
}

LRESULT FlutterWindow::OnNcCalcSize(HWND hwnd, NCCALCSIZE_PARAMS* params) {
  if (IsZoomed(hwnd) == FALSE) {
    // Client area is the whole window: that is what lets the app draw the bar and the frame.
    return 0;
  }
  // A maximized window is positioned half outside the monitor by its (now invisible) resize
  // frame. Keeping that inset is what stops the app bar from ending up above the screen edge.
  const UINT dpi = GetDpiForWindow(hwnd);
  const int extra = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int inset_x = GetSystemMetricsForDpi(SM_CXFRAME, dpi) + extra;
  const int inset_y = GetSystemMetricsForDpi(SM_CYFRAME, dpi) + extra;
  params->rgrc[0].left += inset_x;
  params->rgrc[0].top += inset_y;
  params->rgrc[0].right -= inset_x;
  params->rgrc[0].bottom -= inset_y;
  return 0;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // A second launch of this exe found the window already open and told it to come forward, or to
  // close when that launch came from the engine's toggle.
  if (single_instance::HandleRequest(hwnd, message)) {
    return 0;
  }

  // Window structure is settled here, before the embedder sees it: everything the Flutter view
  // is sized against depends on these answers.
  switch (message) {
    case WM_NCCALCSIZE:
      if (wparam == TRUE) {
        return OnNcCalcSize(hwnd, reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam));
      }
      break;
    case WM_NCPAINT:
      // There is no non-client area left to paint. Answering here is what keeps Windows from
      // brushing a caption-coloured line across the top of the app bar.
      return 0;
    case WM_NCACTIVATE:
      // The other half of the same trap: DefWindowProc repaints the non-client strip whenever
      // activation changes, and clicking the bar changes it. Answering TRUE keeps the activation
      // itself; on the way out DefWindowProc still has to run, or the window never deactivates.
      if (wparam != FALSE || lparam != 0) {
        return TRUE;
      }
      return DefWindowProc(hwnd, WM_NCACTIVATE, FALSE, 0);
    case WM_GETMINMAXINFO: {
      LRESULT result = DefWindowProc(hwnd, message, wparam, lparam);
      MINMAXINFO* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      limits->ptMinTrackSize.x = ScaleLogical(hwnd, frame::kMinWidthLogical);
      limits->ptMinTrackSize.y = ScaleLogical(hwnd, frame::kMinHeightLogical);
      return result;
    }
    case WM_DESTROY:
      // Win32Window::MessageHandler clears its own handle before calling OnDestroy, so this is the
      // last moment there is still a window here to measure. Saving from OnDestroy quietly saved
      // nothing at all.
      SavePlacement();
      break;
    case WM_EXITSIZEMOVE:
      // The system's own drag or resize loop has ended, which is the first moment the new position
      // is final. Writing on every WM_MOVE would be a registry write per pixel.
      SavePlacement();
      break;
    case WM_SIZE: {
      LRESULT result =
          Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      ApplyRoundedRegion();
      ReportWindowState();
      return result;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
