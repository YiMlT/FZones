import 'dart:convert';
import 'dart:io';

/// Mirrors Kind in SettingsWindow.cpp.
enum RowKind { header, boolean, integer, color, choice, multiline, readonly }

class RowDef {
  const RowDef(
    this.kind,
    this.label, {
    this.key = '',
    this.choices = const [],
    this.gateKey,
    this.gateInverted = false,
    this.hideWhenGatedOff = false,
    this.segmented = false,
    this.choiceIsFlag = false,
    this.minValue = 0,
    this.maxValue = 100,
    this.defaultValue,
    this.defaultText = '',
  });

  final RowKind kind;
  final String label;
  final String key;
  final List<String> choices;
  final String? gateKey;
  final bool gateInverted;
  final bool hideWhenGatedOff;
  final bool segmented;

  /// A choice row backed by a bool stores its selection as flag ? 1 : 0.
  final bool choiceIsFlag;
  final int minValue;
  final int maxValue;
  final Object? defaultValue;
  final String defaultText;
}

/// The 37-row settings table, in the same order and with the same gates as the ROWS[]
/// array in SettingsWindow.cpp. Keys are the settings.json property names, byte-identical.
const List<RowDef> kRows = [
  RowDef(RowKind.header, 'group_editor'),
  RowDef(RowKind.readonly, 'activation_shortcut',
      key: 'fancyzones_editor_hotkey', defaultText: 'shift+win+\u0060'),
  RowDef(RowKind.choice, 'launch_editor_display',
      key: 'use_cursorpos_editor_startupscreen',
      choices: ['opt_active_focus', 'opt_mouse_pointer'],
      segmented: true,
      choiceIsFlag: true,
      defaultValue: true),

  RowDef(RowKind.header, 'group_zone_behavior'),
  RowDef(RowKind.boolean, 'shift_drag', key: 'fancyzones_shiftDrag', defaultValue: true),
  RowDef(RowKind.boolean, 'mouse_switch', key: 'fancyzones_mouseSwitch', defaultValue: false),
  RowDef(RowKind.boolean, 'middle_click',
      key: 'fancyzones_mouseMiddleClickSpanningMultipleZones', defaultValue: false),
  RowDef(RowKind.boolean, 'show_all',
      key: 'fancyzones_show_on_all_monitors', defaultValue: false),
  RowDef(RowKind.boolean, 'span',
      key: 'fancyzones_span_zones_across_monitors', defaultValue: false),
  RowDef(RowKind.choice, 'overlap',
      key: 'fancyzones_overlappingZonesAlgorithm',
      choices: ['ov_smallest', 'ov_largest', 'ov_positional', 'ov_closest'],
      defaultValue: 0),

  RowDef(RowKind.header, 'group_zone_appearance'),
  RowDef(RowKind.choice, 'colors',
      key: 'fancyzones_systemTheme',
      choices: ['colors_custom', 'colors_system'],
      segmented: true,
      choiceIsFlag: true,
      defaultValue: true),
  RowDef(RowKind.boolean, 'show_zone_number',
      key: 'fancyzones_showZoneNumber', defaultValue: true),
  RowDef(RowKind.integer, 'opacity',
      key: 'fancyzones_highlight_opacity', minValue: 0, maxValue: 100, defaultValue: 50),
  RowDef(RowKind.color, 'highlight_color',
      key: 'fancyzones_zoneHighlightColor',
      gateKey: 'fancyzones_systemTheme',
      gateInverted: true,
      hideWhenGatedOff: true,
      defaultText: '#008CFF'),
  RowDef(RowKind.color, 'inactive_color',
      key: 'fancyzones_zoneColor',
      gateKey: 'fancyzones_systemTheme',
      gateInverted: true,
      hideWhenGatedOff: true,
      defaultText: '#AACDFF'),
  RowDef(RowKind.color, 'border_color',
      key: 'fancyzones_zoneBorderColor',
      gateKey: 'fancyzones_systemTheme',
      gateInverted: true,
      hideWhenGatedOff: true,
      defaultText: '#FFFFFF'),
  RowDef(RowKind.color, 'number_color',
      key: 'fancyzones_zoneNumberColor',
      gateKey: 'fancyzones_systemTheme',
      gateInverted: true,
      hideWhenGatedOff: true,
      defaultText: '#000000'),

  RowDef(RowKind.header, 'group_window_behavior'),
  RowDef(RowKind.boolean, 'keep_resolution',
      key: 'fancyzones_displayOrWorkAreaChange_moveWindows', defaultValue: true),
  RowDef(RowKind.boolean, 'match_layout',
      key: 'fancyzones_zoneSetChange_moveWindows', defaultValue: false),
  RowDef(RowKind.boolean, 'last_zone',
      key: 'fancyzones_appLastZone_moveWindows', defaultValue: false),
  RowDef(RowKind.boolean, 'active_monitor',
      key: 'fancyzones_openWindowOnActiveMonitor', defaultValue: false),
  RowDef(RowKind.boolean, 'restore_size',
      key: 'fancyzones_restoreSize', defaultValue: false),
  RowDef(RowKind.boolean, 'transparent',
      key: 'fancyzones_makeDraggedWindowTransparent', defaultValue: true),
  RowDef(RowKind.boolean, 'child_snap',
      key: 'fancyzones_allowChildWindowSnap', defaultValue: false),
  RowDef(RowKind.boolean, 'disable_round',
      key: 'fancyzones_disableRoundCornersOnSnap', defaultValue: false),

  RowDef(RowKind.header, 'group_switching'),
  RowDef(RowKind.boolean, 'enable_switching',
      key: 'fancyzones_windowSwitching', defaultValue: true),
  RowDef(RowKind.readonly, 'next_window',
      key: 'fancyzones_nextTab_hotkey',
      gateKey: 'fancyzones_windowSwitching',
      defaultText: 'win+Page Down'),
  RowDef(RowKind.readonly, 'prev_window',
      key: 'fancyzones_prevTab_hotkey',
      gateKey: 'fancyzones_windowSwitching',
      defaultText: 'win+Page Up'),

  RowDef(RowKind.header, 'group_rotation'),
  RowDef(RowKind.boolean, 'enable_rotation',
      key: 'fancyzones_monitorRotation', defaultValue: false),
  RowDef(RowKind.readonly, 'rotation_shortcut',
      key: 'fancyzones_monitorRotation_hotkey',
      gateKey: 'fancyzones_monitorRotation',
      defaultText: 'alt+X'),

  RowDef(RowKind.header, 'group_snap'),
  RowDef(RowKind.boolean, 'override_snap',
      key: 'fancyzones_overrideSnapHotkeys', defaultValue: false),
  RowDef(RowKind.choice, 'move_based',
      key: 'fancyzones_moveWindowsBasedOnPosition',
      choices: ['opt_zone_index', 'opt_relative'],
      segmented: true,
      choiceIsFlag: true,
      gateKey: 'fancyzones_overrideSnapHotkeys',
      defaultValue: false),
  RowDef(RowKind.boolean, 'move_across',
      key: 'fancyzones_moveWindowAcrossMonitors',
      gateKey: 'fancyzones_overrideSnapHotkeys',
      defaultValue: false),

  RowDef(RowKind.header, 'group_quick'),
  RowDef(RowKind.boolean, 'enable_quick',
      key: 'fancyzones_quickLayoutSwitch', defaultValue: true),
  RowDef(RowKind.boolean, 'flash',
      key: 'fancyzones_flashZonesOnQuickSwitch',
      gateKey: 'fancyzones_quickLayoutSwitch',
      defaultValue: true),

  RowDef(RowKind.header, 'group_excluded'),
  RowDef(RowKind.multiline, 'excluded_desc', key: 'fancyzones_excluded_apps'),
];

class FzPaths {
  /// Mirrors PTSettingsHelper::get_root_save_folder_location() + get_module_save_folder_location()
  /// as this extraction builds them: %LOCALAPPDATA%\FZones\FancyZones.
  ///
  /// Note the difference from a stock PowerToys install, which uses
  /// %LOCALAPPDATA%\Microsoft\PowerToys\FancyZones. Pointing at the wrong one is silent:
  /// the engine keeps reading its own file and the UI edits a stranger's.
  static const String _root = r'\FZones';
  static const String _module = r'\FancyZones';

  /// Tests point this at a temp directory so the writer can be exercised end to end
  /// without touching the engine's real state.
  static String? overrideDir;

  static String get fancyZonesDir =>
      overrideDir ??
      [Platform.environment['LOCALAPPDATA'] ?? '', _root, _module].join();

  static String get settingsJson => [fancyZonesDir, r'\settings.json'].join();

  static String get uiSettingsJson => [fancyZonesDir, r'\ui-settings.json'].join();
}

/// One read of settings.json. Absent keys are tracked so the UI can say "engine default"
/// instead of pretending the file said so.
class SettingsSnapshot {
  SettingsSnapshot(this.values, this.present, this.rawLength, this.loadedAt);

  final Map<String, Object?> values;
  final Set<String> present;
  final int rawLength;
  final DateTime loadedAt;

  static SettingsSnapshot empty() => SettingsSnapshot({}, {}, 0, DateTime.now());

  static SettingsSnapshot load(String path) {
    final Map<String, Object?> values = {};
    final Set<String> present = {};
    int length = 0;
    try {
      final File file = File(path);
      if (file.existsSync()) {
        final String raw = file.readAsStringSync();
        length = raw.length;
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) {
          final Object? props = decoded['properties'];
          if (props is Map) {
            props.forEach((Object? k, Object? v) {
              if (v is Map && v.containsKey('value')) {
                values[k.toString()] = v['value'];
                present.add(k.toString());
              }
            });
          }
        }
      }
    } catch (_) {
      // A half-written file simply reads as "nothing present"; the banner says so.
    }
    return SettingsSnapshot(values, present, length, DateTime.now());
  }

  bool has(String key) => present.contains(key);

  Object? value(String key, [Object? fallback]) =>
      present.contains(key) ? values[key] : fallback;

  bool flag(String key, bool fallback) {
    final Object? v = value(key);
    return v is bool ? v : fallback;
  }

  int number(String key, int fallback) {
    final Object? v = value(key);
    if (v is int) return v;
    if (v is double) return v.round();
    return fallback;
  }

  String text(String key, String fallback) {
    final Object? v = value(key);
    return v is String ? v : fallback;
  }

  List<String> hotkey(String key, String fallback) {
    final Object? v = value(key);
    if (v is Map) {
      final List<String> parts = <String>[];
      if (v['shift'] == true) parts.add('shift');
      if (v['ctrl'] == true) parts.add('ctrl');
      if (v['win'] == true) parts.add('win');
      if (v['alt'] == true) parts.add('alt');
      final Object? k = v['key'];
      if (k is String && k.isNotEmpty) parts.add(k);
      if (parts.isNotEmpty) return parts;
    }
    if (v is String && v.isNotEmpty) return <String>[v];
    return fallback.isEmpty ? <String>[] : fallback.split('+');
  }
}

/// The engine's own gate rule: enabled = inverted ? !gate : gate.
bool rowEnabled(SettingsSnapshot s, RowDef row) {
  final String? gateKey = row.gateKey;
  if (gateKey == null) {
    return true;
  }
  final bool gate = s.flag(gateKey, true);
  return row.gateInverted ? !gate : gate;
}
