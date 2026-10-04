import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The eight grab zones along the window's own edges. The names are the contract with
/// `HitTestForEdge` in windows/runner/flutter_window.cpp.
enum FzWindowEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// The bridge to the frameless Win32 window in `windows/runner/flutter_window.cpp`.
///
/// Flutter draws the app bar and the 1px frame, but the caption's drag behaviour, the resize
/// borders and the corner radius are Win32's, so the two sides exchange geometry over one
/// small channel. Off Windows - and under `flutter test`, where no runner implements the
/// channel - every call degrades to a no-op instead of throwing.
class FzWindow {
  FzWindow._();

  static const MethodChannel _channel = MethodChannel('fzones/window');

  static final ValueNotifier<bool> maximized = ValueNotifier<bool>(false);

  /// Whether sign-in will start the engine, and whether this build can arrange that. The registry
  /// entry is the engine's own (`RUN_VALUE` in AppSettings.cpp), and the installer writes the same
  /// one - so this side only reads it and asks for it to change.
  static final ValueNotifier<bool> autostart = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> autostartManaged = ValueNotifier<bool>(false);

  static bool _live = !kIsWeb && Platform.isWindows;
  static bool _attached = false;

  /// Called from the frame once per process. Also pulls the initial maximized state, which
  /// the native side only reports on change.
  static void attach() {
    if (_attached || !_live) {
      return;
    }
    _attached = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onStateChanged') {
        final Object? args = call.arguments;
        if (args is Map) {
          maximized.value = args['maximized'] == true;
        }
      }
    });
    _invoke<bool>(() => _channel.invokeMethod<bool>('isMaximized'), (bool? value) {
      maximized.value = value ?? false;
    });
    refreshAutostart();
  }

  static void refreshAutostart() => _invoke<Map<Object?, Object?>?>(
      () => _channel.invokeMethod<Map<Object?, Object?>?>('getAutostart'),
      _readAutostart);

  /// Turn registering the engine at sign-in on or off. The native side answers with the state
  /// after the write, so the switch ends up showing the registry rather than the wish.
  static void setAutostart(bool enabled) =>
      _invoke<Map<Object?, Object?>?>(
          () => _channel.invokeMethod<Map<Object?, Object?>?>(
              'setAutostart', <String, bool>{'enabled': enabled}),
          _readAutostart);

  static void _readAutostart(Map<Object?, Object?>? state) {
    if (state == null) {
      return;
    }
    autostart.value = state['enabled'] == true;
    autostartManaged.value = state['managed'] == true;
  }

  /// Hands a pointer that is already down to the system's caption loop. Windows then drags the
  /// window, offers Snap Assist, and treats a second click as the double-click that maximizes.
  static void startDrag() =>
      _invoke<void>(() => _channel.invokeMethod<void>('startDrag'));

  static void startResize(FzWindowEdge edge) =>
      _invoke<void>(() => _channel.invokeMethod<void>(
          'startResize', <String, String>{'edge': edge.name}));

  static void toggleMaximize() =>
      _invoke<void>(() => _channel.invokeMethod<void>('toggleMaximize'));

  static void minimize() => _invoke<void>(() => _channel.invokeMethod<void>('minimize'));

  static void close() => _invoke<void>(() => _channel.invokeMethod<void>('close'));

  static void openSettings() =>
      _invoke<void>(() => _channel.invokeMethod<void>('openSettings'));

  static void _invoke<T>(Future<T?> Function() call, [void Function(T?)? then]) {
    if (!_live) {
      return;
    }
    call().then((T? value) {
      then?.call(value);
    }).catchError((Object _) {
      // MissingPluginException (no runner) or a disposed window: chrome that cannot talk to
      // Win32 still has to paint, it just stops moving.
      _live = false;
    });
  }
}
