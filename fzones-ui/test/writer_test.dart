import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/main.dart';
import 'package:fzones_ui/settings_model.dart';
import 'package:fzones_ui/widgets.dart';
import 'package:fzones_ui/settings_writer.dart';

/// Guards §5 of documents/designs/fzones_ipc_contract.md: read-modify-write, atomic replace,
/// compact UTF-8, and never a half-written file for the engine to trip over.
void main() {
  late Directory dir;
  late String path;

  String sample() => jsonEncode(<String, Object?>{
        'name': 'FancyZones',
        'version': '1.0',
        'properties': <String, Object?>{
          'fancyzones_shiftDrag': <String, Object?>{'value': true},
          'fancyzones_mouseSwitch': <String, Object?>{'value': false},
          'fancyzones_highlight_opacity': <String, Object?>{'value': 50},
          'something_we_do_not_know': <String, Object?>{'value': 'keep me'},
        },
      });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fzui');
    path = [dir.path, 'settings.json'].join(Platform.pathSeparator);
    File(path).writeAsStringSync(sample());
    FzPaths.overrideDir = dir.path;
  });

  tearDown(() {
    FzPaths.overrideDir = null;
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('changes one key and leaves everything else exactly where the engine put it', () {
    SettingsWriter.writeValue(path, 'fancyzones_shiftDrag', false);

    final Map<String, dynamic> root =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> props = root['properties'] as Map<String, dynamic>;

    expect(props['fancyzones_shiftDrag']['value'], false);
    expect(props['fancyzones_mouseSwitch']['value'], false, reason: 'untouched');
    expect(props['fancyzones_highlight_opacity']['value'], 50, reason: 'untouched');
    expect(props['something_we_do_not_know']['value'], 'keep me',
        reason: 'a key this UI knows nothing about must survive');
    expect(root['name'], 'FancyZones');
    expect(root['version'], '1.0');
    expect(props.keys.first, 'fancyzones_shiftDrag',
        reason: 'insertion order is preserved, so the diff stays one line');
  });

  test('writes are atomic: the temp file never survives and the target is always valid', () {
    for (int i = 0; i < 5; i++) {
      SettingsWriter.writeValue(path, 'fancyzones_highlight_opacity', i);
      expect(File('$path.tmp').existsSync(), isFalse);
      final Map<String, dynamic> root =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect((root['properties'] as Map<String, dynamic>)['fancyzones_highlight_opacity']
          ['value'], i);
    }
  });

  test('a missing file is created with the shape the engine expects', () {
    final String fresh = [dir.path, 'brand-new.json'].join(Platform.pathSeparator);
    SettingsWriter.writeValue(fresh, 'fancyzones_shiftDrag', true);

    final Map<String, dynamic> root =
        jsonDecode(File(fresh).readAsStringSync()) as Map<String, dynamic>;
    expect(root['name'], 'FancyZones');
    expect(root['version'], '1.0');
    expect((root['properties'] as Map<String, dynamic>)['fancyzones_shiftDrag']['value'],
        true);
  });

  testWidgets('tapping a switch in the real widget tree writes the file', (WidgetTester tester) async {
    // A desktop-sized surface: the default 800x600 test window is narrower than the real one.
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FzApp());
    await tester.pumpAndSettle();

    // The first switch in the table is shift_drag (SettingsWindow.cpp's ROWS[] order).
    await tester.tap(find.byType(FzToggle).first);
    await tester.pumpAndSettle();

    final Map<String, dynamic> root =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> props = root['properties'] as Map<String, dynamic>;

    expect(props['fancyzones_shiftDrag']['value'], false,
        reason: 'true in the fixture, so the tap must have flipped it');
    expect(props['something_we_do_not_know']['value'], 'keep me');
    expect(File('$path.tmp').existsSync(), isFalse);
  });
}
