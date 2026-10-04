import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/settings_model.dart';

/// Guards the cross-process contract described in documents/designs/fzones_ipc_contract.md.
void main() {
  test('the row table stays in step with SettingsWindow.cpp ROWS[]', () {
    // The C++ table has 37 settings rows + 10 group headers. This POC carries the 34 rows
    // that live in settings.json plus their 9 headers; the App group (theme / language /
    // autostart) is app-level state - ui-settings.json and HKCU - and the toolbar owns it
    // here, so it is deliberately out of scope for stage 0.
    expect(kRows.length, 43, reason: '34 settings rows + 9 group headers');
    expect(kRows.where((RowDef r) => r.kind == RowKind.header).length, 9);

    final List<String> keys = kRows
        .where((RowDef r) => r.key.isNotEmpty)
        .map((RowDef r) => r.key)
        .toList();
    expect(keys.length, 34, reason: '34 settings.json-backed rows');
    expect(keys.toSet().length, keys.length, reason: 'no duplicate property names');

    // Every key the UI writes must be namespaced the way the engine reads it.
    for (final String key in keys) {
      expect(
        key.startsWith('fancyzones_') || key == 'use_cursorpos_editor_startupscreen',
        isTrue,
        reason: 'unexpected key shape: $key',
      );
    }
  });

  test('gates follow the engine rule: enabled = inverted ? !gate : gate', () {
    final SettingsSnapshot custom = SettingsSnapshot(
        <String, Object?>{'fancyzones_systemTheme': false}, <String>{'fancyzones_systemTheme'}, 0, DateTime.now());
    final SettingsSnapshot system = SettingsSnapshot(
        <String, Object?>{'fancyzones_systemTheme': true}, <String>{'fancyzones_systemTheme'}, 0, DateTime.now());

    final RowDef colors =
        kRows.firstWhere((RowDef r) => r.key == 'fancyzones_zoneHighlightColor');
    expect(rowEnabled(custom, colors), isTrue, reason: 'custom colours show their rows');
    expect(rowEnabled(system, colors), isFalse, reason: 'Windows default hides them');
  });

  test('a real settings.json from the engine parses into the same value types', () {
    final File file = File(FzPaths.settingsJson);
    if (!file.existsSync()) {
      return; // Nothing to compare against on a machine that never ran the app.
    }

    final SettingsSnapshot snapshot = SettingsSnapshot.load(FzPaths.settingsJson);
    expect(snapshot.present, isNotEmpty);

    // Round-trip: what the engine writes must survive a Dart read unchanged.
    final Object? decoded = jsonDecode(file.readAsStringSync());
    expect(decoded, isA<Map<String, dynamic>>());
    final Map<String, dynamic> props =
        (decoded! as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
    for (final String key in snapshot.present) {
      expect(props[key]['value'], snapshot.values[key], reason: key);
    }
  });
}
