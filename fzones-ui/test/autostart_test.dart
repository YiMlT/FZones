import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/app_bar.dart';
import 'package:fzones_ui/design.dart';
import 'package:fzones_ui/main.dart';
import 'package:fzones_ui/settings_model.dart';
import 'package:fzones_ui/strings.dart';
import 'package:fzones_ui/ui_settings.dart';
import 'package:fzones_ui/widgets.dart';
import 'package:fzones_ui/window_bridge.dart';

/// The autostart row, against a fake of the window channel's two registry verbs. Nothing here
/// touches HKCU: the handler below is the only thing answering, so the developer's own sign-in
/// entry cannot be edited by a test run.
void main() {
  const MethodChannel channel = MethodChannel('fzones/window');
  late Directory scratch;
  late List<MethodCall> calls;
  late Map<String, Object?> registry;

  FzLang lang = fzResolveLang(Platform.localeName);
  String t(String key) => fzT(key, lang);

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FzApp(
      ui: const FzUiSettings(theme: FzThemeMode.light),
    ));
    await tester.pumpAndSettle();
    // FzWindow attaches once per process, so a later test in this file would otherwise keep the
    // previous fake's answer.
    FzWindow.refreshAutostart();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(t('autostart')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// The switch inside the autostart row: label and control are siblings in one `Row`.
  Finder autostartSwitch() => find.descendant(
    of: find
        .ancestor(
          of: find.text(t('autostart')),
          matching: find.byType(Row),
        )
        .first,
    matching: find.byType(FzToggle),
  );

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('fzautostart');
    FzPaths.overrideDir = scratch.path;
    calls = <MethodCall>[];
    registry = <String, Object?>{'enabled': false, 'managed': true};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'isMaximized':
          return false;
        case 'getAutostart':
          return registry;
        case 'setAutostart':
          registry = <String, Object?>{
            'enabled': (call.arguments as Map<Object?, Object?>)['enabled'],
            'managed': true,
          };
          return registry;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    FzPaths.overrideDir = null;
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  });

  testWidgets('--app lands on the App group with no gesture', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const FzApp(revealApp: true));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text(t('autostart')), findsOneWidget);
    final Rect switchRect = tester.getRect(autostartSwitch());
    final Rect windowRect = tester.getRect(find.byType(FzWindowFrame));
    debugPrint('AUTOSTART center=${switchRect.center.dx.toStringAsFixed(1)},'
        '${switchRect.center.dy.toStringAsFixed(1)} '
        'window=${windowRect.width.toStringAsFixed(0)}x${windowRect.height.toStringAsFixed(0)}');
    expect(switchRect.bottom, lessThanOrEqualTo(windowRect.bottom),
        reason: 'the deep link has to put the row inside the window, not just build it');
    expect(switchRect.top, greaterThanOrEqualTo(windowRect.top + 48),
        reason: 'below the caption');
  });

  testWidgets('the App group offers the switch and asks the runner for its state', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text(t('autostart')), findsOneWidget);
    expect(autostartSwitch(), findsOneWidget);
    expect(
      calls.map((MethodCall c) => c.method),
      contains('getAutostart'),
      reason: 'the row shows the registry, so it has to read it',
    );
    expect(tester.widget<FzToggle>(autostartSwitch()).value, isFalse);
  });

  testWidgets('a tap writes the entry and the switch follows the reply', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);
    calls.clear();

    await tester.tap(autostartSwitch());
    await tester.pumpAndSettle();

    final MethodCall write = calls.lastWhere((MethodCall c) => c.method == 'setAutostart');
    expect((write.arguments as Map<Object?, Object?>)['enabled'], isTrue);
    expect(tester.widget<FzToggle>(autostartSwitch()).value, isTrue,
        reason: 'the answer after the write, not the wish');

    await tester.tap(autostartSwitch());
    await tester.pumpAndSettle();
    expect(tester.widget<FzToggle>(autostartSwitch()).value, isFalse);
  });

  testWidgets('with no engine beside it the row is off limits, not silently refusing', (
    WidgetTester tester,
  ) async {
    registry = <String, Object?>{'enabled': false, 'managed': false};
    await pumpSettings(tester);
    calls.clear();

    // Several ancestors can be ignoring pointers; what matters is that the row's own guard is.
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.ancestor(
              of: autostartSwitch(),
              matching: find.byType(IgnorePointer),
            ),
          )
          .any((IgnorePointer g) => g.ignoring),
      isTrue,
    );

    await tester.tap(autostartSwitch(), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      calls.where((MethodCall c) => c.method == 'setAutostart'),
      isEmpty,
      reason: 'a disabled row must not write',
    );
  });

  test('the runner, the installer and the engine name one registry entry', () {
    // Three writers of one value: HKCU\...\Run\FZones. If the strings drift, the settings toggle
    // and the installer end up managing different entries and neither one reports it.
    const String sep = '/';
    final List<List<String>> places = <List<String>>[
      <String>[
        '..${sep}PowerToys${sep}src${sep}modules${sep}fancyzones${sep}FZones${sep}AppSettings.cpp',
        r'RUN_VALUE\[\]\s*=\s*L"([^"]+)"',
      ],
      <String>[
        // `flutter test` runs from the package root, so this one has no `..` on it.
        'windows${sep}runner${sep}flutter_window.cpp',
        r'kRunValue\[\]\s*=\s*L"([^"]+)"',
      ],
      <String>[
        '..${sep}installer${sep}fzones.nsi',
        r'!define\s+RUN_VALUE\s+"([^"]+)"',
      ],
    ];

    final Map<String, String> found = <String, String>{};
    for (final List<String> place in places) {
      final File file = File(place[0]);
      if (!file.existsSync()) {
        markTestSkipped('${place[0]} is not in this checkout');
        return;
      }
      final RegExpMatch? match = RegExp(place[1]).firstMatch(file.readAsStringSync());
      expect(match, isNotNull, reason: 'no run-key value name in ${place[0]}');
      found[place[0].split('/').last] = match!.group(1)!;
    }
    expect(found.values.toSet(), <String>{'FZones'}, reason: '$found');
  });
}
