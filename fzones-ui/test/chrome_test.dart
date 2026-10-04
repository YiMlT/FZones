import 'dart:io';

import 'package:flutter/gestures.dart';
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

/// The chrome the native windows used to own: a custom app bar whose buttons sit flush right, a
/// rounded frame on the same 8px radius as the cards, and a drag band that hands the gesture to
/// Win32.

FzLang get systemLang => fzResolveLang(Platform.localeName);

String t(String key) => fzT(key, systemLang);

Future<void> pump(WidgetTester tester, {bool editor = false}) async {
  // The real window sizes, not the 800x600 default: the rows are measured against the shipping
  // width, and the native side refuses anything under 620 logical anyway.
  tester.view.physicalSize = Size(editor ? 880 : 700, editor ? 620 : 560);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FzApp(
    startInEditor: editor,
    startEditorPage: 'browse',
    // Light, so the theme assertions do not depend on the machine's own setting.
    ui: const FzUiSettings(theme: FzThemeMode.light),
  ));
  await tester.pumpAndSettle();
}

/// The settings list is viewport-cached, so anything below the fold has no element until it is
/// scrolled in.
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 240,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

FzColors colors(WidgetTester tester) =>
    Theme.of(find.byType(FzAppBar).evaluate().single).extension<FzTheme>()!.colors;

double frameRight(WidgetTester tester) =>
    tester.getRect(find.byType(FzWindowFrame)).right;

void main() {
  // These tests tap real controls, which write real files. Point the whole data directory at a
  // temp folder first - once, this suite wrote a captured Ctrl+Q into the engine's own
  // settings.json and the editor hotkey stopped working for the user.
  late Directory scratch;
  setUp(() {
    scratch = Directory.systemTemp.createTempSync('fzones-chrome-test');
    FzPaths.overrideDir = scratch.path;
  });
  tearDown(() {
    FzPaths.overrideDir = null;
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  });

  testWidgets('the caption buttons clear the right edge by the page gutter',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text(t('app_title')), findsOneWidget);
    expect(find.byType(FzCaptionButton), findsNWidgets(2),
        reason: 'minimize and close; the gear belongs to the editor');
    // The same 16 the page content leaves on its right, so the close button's edge lines up with
    // the cards under it instead of riding the frame.
    final double right = frameRight(tester) - FzMetrics.pagePadX;
    expect(tester.getRect(find.byType(FzCaptionButton).last).right, right);
    expect(tester.getRect(find.byType(FzCaptionButton).first).left,
        closeTo(right - 2 * FzMetrics.captionButton, 0.5));
    expect(find.byType(Scaffold), findsNothing,
        reason: 'the frame replaces the page scaffold, or a page transition would slide '
            'under the rounded corner');
  });

  testWidgets('the editor orders the buttons minimize, settings, close',
      (WidgetTester tester) async {
    await pump(tester, editor: true);

    final List<FzCaptionGlyph> glyphs = tester
        .widgetList<FzCaptionButton>(find.byType(FzCaptionButton))
        .map((FzCaptionButton b) => b.glyph)
        .toList();
    expect(glyphs, <FzCaptionGlyph>[
      FzCaptionGlyph.minimize,
      FzCaptionGlyph.settings,
      FzCaptionGlyph.close,
    ]);
    expect(tester.getRect(find.byType(FzCaptionButton).last).right,
        frameRight(tester) - FzMetrics.pagePadX);
  });

  testWidgets('the title band is the drag surface and stops at the buttons',
      (WidgetTester tester) async {
    await pump(tester);

    final Rect band =
        tester.getRect(find.byKey(const ValueKey<String>('fz-drag-band')));
    expect(band.left, FzMetrics.pagePadX);
    // The band ends exactly where the buttons begin: it is an Expanded, not a gap.
    expect(band.right,
        lessThanOrEqualTo(tester.getRect(find.byType(FzCaptionButton).first).left));
    expect(band.height, FzMetrics.bar);
  });

  testWidgets('every caption button has a string in the active language',
      (WidgetTester tester) async {
    await pump(tester, editor: true);

    for (final FzCaptionButton button in tester
        .widgetList<FzCaptionButton>(find.byType(FzCaptionButton))) {
      expect(button.tooltip, isNotEmpty);
    }
  });

  testWidgets('the window controls degrade quietly with no runner',
      (WidgetTester tester) async {
    await pump(tester);

    // flutter test never implements fzones/window; a click must not surface an exception.
    await tester.tap(find.byType(FzCaptionButton).last);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the frame carries the palette hairline on the base radius',
      (WidgetTester tester) async {
    await pump(tester);

    final DecoratedBox box = tester.widget<DecoratedBox>(find
        .descendant(
            of: find.byType(FzWindowFrame), matching: find.byType(DecoratedBox))
        .first);
    final BoxDecoration decoration = box.decoration as BoxDecoration;
    expect(decoration.border!.top.color, colors(tester).frame);
    expect(decoration.border!.top.width, FzMetrics.frameStroke);
    expect(decoration.borderRadius, BorderRadius.circular(FzRadius.base));

    final ClipRRect clip = tester.widget<ClipRRect>(find
        .descendant(
            of: find.byType(FzWindowFrame), matching: find.byType(ClipRRect))
        .first);
    expect(clip.borderRadius, BorderRadius.circular(FzRadius.base));
  });

  testWidgets('the App group switches the theme without a native round trip',
      (WidgetTester tester) async {
    await pump(tester);
    await reveal(tester, find.text(t('group_app')));

    expect(find.text(t('theme')), findsOneWidget);
    expect(find.text(t('language')), findsOneWidget);
    expect(Theme.of(find.byType(FzAppBar).evaluate().single).brightness,
        Brightness.light);

    await tester.tap(find.text(t('theme_dark')));
    await tester.pumpAndSettle();

    expect(Theme.of(find.byType(FzAppBar).evaluate().single).brightness,
        Brightness.dark);
    expect(FzWindow.maximized.value, isFalse);
    expect(
        File([scratch.path, 'ui-settings.json'].join(Platform.pathSeparator))
            .readAsStringSync(),
        contains('"theme":"dark"'),
        reason: 'the other window follows that file, so it has to be written');
  });

  testWidgets('rows carry no default hint', (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('default'), findsNothing);
    expect(find.byType(FzChip), findsNothing);
  });

  testWidgets('the row highlight is an inset band, and only on pointer hover',
      (WidgetTester tester) async {
    await pump(tester);

    final Color hover = colors(tester).hover;
    Finder band() => find.byWidgetPredicate((Widget w) =>
        w is AnimatedContainer &&
        (w.decoration! as BoxDecoration).color == hover);

    expect(band(), findsNothing, reason: 'idle: no row is highlighted');

    // A MouseRegion only answers to a mouse, so a touch-style gesture proves nothing here.
    final TestGesture pointer =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer();
    await pointer
        .moveTo(tester.getCenter(find.text(t('shift_drag')).first));
    await tester.pumpAndSettle();

    expect(band(), findsOneWidget);
    final Rect row = tester.getRect(find
        .ancestor(of: find.text(t('shift_drag')).first, matching: find.byType(MouseRegion))
        .first);
    final Rect painted = tester.getRect(band());
    expect(painted.left - row.left, closeTo(FzMetrics.rowInset.left, 0.5));
    expect(row.right - painted.right, closeTo(FzMetrics.rowInset.right, 0.5));
    // EdgeInsets.vertical is already top + bottom.
    expect(row.height - painted.height, closeTo(FzMetrics.rowInset.vertical, 0.5));
    await pointer.removePointer();
  });

  testWidgets('the segmented thumb slides to the chosen cell',
      (WidgetTester tester) async {
    await pump(tester);
    await reveal(tester, find.text(t('group_app')));

    // The row's label is a sibling of the control, so reach the segmented by its own choices.
    final Finder theme = find.byWidgetPredicate((Widget w) =>
        w is FzSegmented && w.labels.contains(t('theme_dark')));
    AnimatedPositioned thumb() => tester
        .widgetList<AnimatedPositioned>(
            find.descendant(of: theme, matching: find.byType(AnimatedPositioned)))
        .first;

    // The container's own box is (width - 2) once its hairline is accounted for; the thumb sits
    // 3px inside that, and the cells are 2px apart.
    final double cell = (FzMetrics.fieldWidth - 2 - 6 - 4) / 3;
    // The pump starts on 浅色, which is cell 1.
    expect(thumb().left, closeTo(3 + 1 * (cell + 2), 0.5));

    await tester.tap(find.text(t('theme_dark')));
    await tester.pumpAndSettle();

    expect(thumb().left, closeTo(3 + 2 * (cell + 2), 0.5));
    expect(thumb().duration, FzMotion.seg);
    expect(thumb().top, 3,
        reason: 'the thumb sits 3px inside the hairline, the same band the labels centre in');
  });

  testWidgets('a focused field grows a one-pixel ring, not a heavy one',
      (WidgetTester tester) async {
    await pump(tester);

    List<BoxShadow> ring() {
      final BoxDecoration box = tester
          .widgetList<AnimatedContainer>(find.descendant(
              of: find.byType(FzFieldFrame),
              matching: find.byType(AnimatedContainer)))
          .first
          .decoration! as BoxDecoration;
      return box.boxShadow!;
    }

    // Not .first: dragUntilVisible needs an empty-check that a first-finder turns into a throw.
    await reveal(tester, find.byType(FzNumberField));
    expect(ring().single.color, fade(colors(tester).focusA),
        reason: 'idle: the ring is off, but not via transparent black');

    await tester.tap(find.byType(FzNumberField).first);
    await tester.pumpAndSettle();

    final BoxShadow ink = ring().single;
    expect(ink.spreadRadius, 1, reason: 'one pixel of ink, no gap stroke');
    expect(ink.color, colors(tester).focusA);
  });

  testWidgets('the dropdown popup is exactly as wide as its field',
      (WidgetTester tester) async {
    await pump(tester);
    await reveal(tester, find.text(t('overlap')));

    final Finder value = find.text(t('ov_smallest'));
    final Rect field = tester.getRect(find
        .ancestor(of: value, matching: find.byType(AnimatedContainer))
        .first);
    expect(field.width, FzMetrics.fieldWidth);

    await tester.tap(value);
    await tester.pumpAndSettle();

    // The panel's own box, not the item row: it has to be the field's width, and the items
    // then sit inside its 4px padding.
    final Iterable<SizedBox> boxes = tester.widgetList<SizedBox>(find.ancestor(
        of: find.text(t('ov_positional')),
        matching: find.byType(SizedBox)));
    expect(
        boxes.map((SizedBox b) => b.width),
        contains(FzMetrics.fieldWidth),
        reason: 'the popup is exactly as wide as the field it belongs to');
    final Rect panel = tester.getRect(find
        .ancestor(of: find.text(t('ov_positional')), matching: find.byType(SizedBox))
        .last);
    expect(panel.width, FzMetrics.fieldWidth);
    expect(panel.left, closeTo(field.left, 0.5),
        reason: 'it opens flush with the left edge of the field');
  });

  testWidgets('a popup item carries no leading tick gutter',
      (WidgetTester tester) async {
    await pump(tester);
    await reveal(tester, find.text(t('overlap')));
    await tester.tap(find.text(t('ov_smallest')));
    await tester.pumpAndSettle();

    final Rect panel = tester.getRect(find
        .ancestor(of: find.text(t('ov_positional')), matching: find.byType(SizedBox))
        .last);
    // The selected row is the field's own value, which appears twice once the popup is open.
    final Rect item = tester.getRect(find.text(t('ov_smallest')).last);
    expect(
      item.left,
      closeTo(panel.left + FzMetrics.menuPad + 8, 0.5),
      reason: 'the band padding is the only gutter - the tick slot is gone',
    );
  });

  testWidgets('every popup band is the same width and its label sits in the middle',
      (WidgetTester tester) async {
    await pump(tester);
    await reveal(tester, find.text(t('overlap')));
    await tester.tap(find.text(t('ov_smallest')));
    await tester.pumpAndSettle();

    const List<String> options = <String>[
      'ov_smallest',
      'ov_largest',
      'ov_positional',
      'ov_closest',
    ];
    final List<double> widths = <double>[];
    for (final String key in options) {
      final Rect label = tester.getRect(find.text(t(key)).last);
      final Rect band = tester.getRect(find.ancestor(
        of: find.text(t(key)).last,
        matching: find.byType(AnimatedContainer),
      ).first);
      widths.add(band.width);
      // A Column defaults to centring its children, which made each band hug its own label and
      // pushed the text to the middle of the row instead of the left.
      expect(label.center.dy, closeTo(band.center.dy, 0.6),
          reason: '${t(key)}: the label has to sit in the middle of its 32px band');
      expect(label.left, lessThan(band.center.dx),
          reason: '${t(key)}: the label reads from the left, not the centre');
    }
    expect(widths.toSet().length, 1, reason: 'all four bands: $widths');
    expect(widths.first, closeTo(FzMetrics.fieldWidth - FzMetrics.menuPad * 2, 0.6));
  });

  testWidgets('the wheel steps a focused number field and leaves the rest alone',
      (WidgetTester tester) async {
    await pump(tester);
    await reveal(tester, find.text(t('opacity')));

    final Finder label = find.text(t('opacity'));
    expect(find.ancestor(of: label, matching: find.byType(Row)), findsOneWidget);
    final Finder field = find.descendant(
      of: find.ancestor(of: label, matching: find.byType(Row)),
      matching: find.byType(FzNumberField),
    );
    // reveal() stops as soon as the row is on screen, which can leave it under the 48px caption
    // where a tap hits the bar instead. Pull it a little further down.
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, 140),
    );
    await tester.pumpAndSettle();
    int shown() => int.parse(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
    );

    // No wheel helper on this Flutter version; a TestPointer scroll is what the real device
    // produces, and `Listener.onPointerSignal` is what receives it.
    Future<void> wheel(Offset at, double dy) async {
      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(at);
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pump();
    }

    // A real mouse cursor: the field only takes the wheel when it has both the caret and the
    // pointer over it, and `MouseRegion.onEnter` needs an actual hover event to fire.
    final TestGesture cursor = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await cursor.addPointer(location: Offset.zero);
    addTearDown(cursor.removePointer);
    await tester.pump();

    final Offset at = tester.getCenter(field);
    await cursor.moveTo(at);
    await tester.pump();
    await cursor.down(at);
    await cursor.up();
    await tester.pumpAndSettle();
    final Offset parked = tester.getCenter(field);

    await wheel(parked, -20);
    await tester.pumpAndSettle();
    expect(shown(), 51, reason: 'one notch up over a focused field is one higher');

    await wheel(parked, 20);
    await tester.pumpAndSettle();
    expect(shown(), 50);

    // The page must not slide out from under a wheel the field owns: before this was true, the
    // list moved 20px per notch and the field eventually left the pointer behind.
    expect(tester.getCenter(field), parked);

    // The bounds the row declares, now clamped by the field instead of being written out for the
    // engine to reject.
    for (int i = 0; i < 60; i++) {
      await wheel(parked, -20);
    }
    await tester.pumpAndSettle();
    expect(shown(), 100, reason: 'opacity tops out at 100');

    // Let go of the caret and the list has its scroll back.
    final Offset elsewhere = tester.getRect(find.text(t('opacity'))).centerRight +
        const Offset(-8, 24);
    await cursor.moveTo(elsewhere);
    await tester.pump();
    await cursor.down(elsewhere);
    await cursor.up();
    await tester.pumpAndSettle();
    final Offset scrolled = tester.getCenter(field);
    final int settled = shown();
    await wheel(scrolled, 20);
    await wheel(scrolled, 20);
    await tester.pumpAndSettle();
    expect(tester.getCenter(field), isNot(scrolled),
        reason: 'with no caret in the box the wheel belongs to the list');
    expect(shown(), settled, reason: 'and it must not move the number');
  });

  testWidgets('clicking the keycaps captures a new shortcut',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('shift').first);
    await tester.pumpAndSettle();
    expect(find.text(t('hotkey_capture')), findsOneWidget,
        reason: 'the chips swap for the capture box');

    // A bare modifier only arms the box; it does not commit.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text(t('hotkey_capture')), findsNothing);
    expect(find.text('ctrl'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text(t('hotkey_capture')), findsNothing,
        reason: 'a chord commits and the box closes');
    expect(find.text('Q'), findsOneWidget);
  });

  testWidgets('the colour picker opens with its own chrome and cancels quietly',
      (WidgetTester tester) async {
    await pump(tester);
    // The four colour rows are gated off until 自定义颜色 is chosen, and a collapsed row has no
    // element to scroll to.
    await reveal(tester, find.text(t('colors')));
    await tester.tap(find.text(t('colors_custom')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text(t('highlight_color')));

    await tester.tap(find.text('...').first);
    await tester.pumpAndSettle();

    expect(find.text(t('pick_color')), findsOneWidget);
    expect(find.text(t('ok')), findsOneWidget);

    await tester.tap(find.text(t('cancel')));
    await tester.pumpAndSettle();
    expect(find.text(t('pick_color')), findsNothing);
  });

  testWidgets('the keycap group and the "..." buttons share one right edge',
      (WidgetTester tester) async {
    // A wide window is where a max-size Row used to hang 50px short of the gutter.
    await pump(tester);

    final Rect topSegmented = tester.getRect(find
        .ancestor(of: find.text(t('opt_mouse_pointer')),
            matching: find.byType(FzSegmented))
        .first);
    // The group, not the first chip: the chips after it extend to the real right edge.
    final Rect keycaps = tester.getRect(find
        .ancestor(of: find.text('`').first, matching: find.byType(Row))
        .first);
    expect(keycaps.right, closeTo(topSegmented.right, 1.0));

    await reveal(tester, find.text(t('colors')));
    final Rect colorSegmented = tester.getRect(find
        .ancestor(of: find.text(t('colors_custom')),
            matching: find.byType(FzSegmented))
        .first);
    // The colour rows themselves only exist once custom colours are on.
    await tester.tap(find.text(t('colors_custom')));
    await tester.pumpAndSettle();
    final Rect dotsRow = tester.getRect(find
        .ancestor(of: find.text('...').first, matching: find.byType(Row))
        .first);
    expect(dotsRow.right, closeTo(colorSegmented.right, 1.0));
  });
}
