import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/design.dart';
import 'package:fzones_ui/main.dart';
import 'package:fzones_ui/settings_model.dart';
import 'package:fzones_ui/settings_writer.dart';
import 'package:fzones_ui/ui_settings.dart';

/// The two windows are separate processes, so `ui-settings.json` plus a watcher is the whole
/// protocol between them. Both halves of that are pinned here.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fzuisettings');
    FzPaths.overrideDir = dir.path;
  });

  tearDown(() {
    FzPaths.overrideDir = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String uiJsonPath() => [dir.path, 'ui-settings.json'].join(Platform.pathSeparator);

  test('save then load round-trips, and the pair compares by value', () {
    expect(FzUiSettings.load(), const FzUiSettings());
    const FzUiSettings written = FzUiSettings(
      theme: FzThemeMode.dark,
      language: FzLangMode.zh,
    );
    written.save();
    final FzUiSettings back = FzUiSettings.load();
    expect(back, written);
    expect(back, isNot(const FzUiSettings()));
  });

  test('the first write reaches a watcher, not only the ones after it', () async {
    // The write is a temp file plus a rename, and Dart's Windows watcher reports that rename under
    // the old name - so a filter on `ui-settings.json` alone saw nothing the first time, and only
    // from the second write on did the replaced file produce a delete event.
    final List<String> seen = <String>[];
    final StreamSubscription<FileSystemEvent> sub =
        dir.watch(events: FileSystemEvent.all).listen((FileSystemEvent e) {
          if (fzEventTouches(e.path, 'ui-settings.json')) {
            seen.add(FzUiSettings.load().theme.name);
          }
        });

    const FzUiSettings(theme: FzThemeMode.dark).save();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await sub.cancel();

    expect(seen, contains('dark'),
        reason: 'the very first theme switch must not be lost');
  });

  test('the settings file is the one an outside writer touches', () {
    SettingsWriter.writeAtomic(uiJsonPath(), <String, Object?>{
      'theme': 'light',
      'language': 'en',
    });
    expect(FzUiSettings.load(), const FzUiSettings(
      theme: FzThemeMode.light,
      language: FzLangMode.en,
    ));
  });

  testWidgets('a window follows an external theme change', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(880, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Brightness brightness() =>
        Theme.of(tester.element(find.byType(SettingsPage))).brightness;

    await tester.pumpWidget(const FzApp());
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);

    File(uiJsonPath()).writeAsStringSync('{"theme":"dark","language":"system"}');
    // The watcher is real asynchronous I/O, which a test binding only lets run inside runAsync.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();

    expect(brightness(), Brightness.dark,
        reason: 'the other window wrote the file, this one followed');
  });
}
