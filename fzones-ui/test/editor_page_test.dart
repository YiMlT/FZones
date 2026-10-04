import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/design.dart';
import 'package:fzones_ui/editor_page.dart';
import 'package:fzones_ui/layout_store.dart';
import 'package:fzones_ui/settings_model.dart';
import 'package:fzones_ui/strings.dart';
import 'package:fzones_ui/widgets.dart';

/// The editor's write path, driven through the real widget tree against a temp data folder.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fzeditor');
    FzPaths.overrideDir = dir.path;
    String p(String n) => [dir.path, n].join(Platform.pathSeparator);
    File(p('editor-parameters.json')).writeAsStringSync(jsonEncode(<String, dynamic>{
      'process-id': 1,
      'span-zones-across-monitors': false,
      'monitors': <dynamic>[
        <String, dynamic>{
          'monitor': 'M1',
          'monitor-instance-id': 'i1',
          'monitor-serial-number': 's1',
          'monitor-number': 1,
          'virtual-desktop': 'vd',
          'dpi': 96,
          'top-coordinate': 0,
          'left-coordinate': 0,
          'work-area-width': 1920,
          'work-area-height': 1080,
          'monitor-width': 1920,
          'monitor-height': 1080,
          'is-selected': true,
        },
      ],
    }));
  });

  tearDown(() {
    FzPaths.overrideDir = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget host(Widget child) => MaterialApp(
        theme: buildFzTheme(FzColors.light, false),
        home: child,
      );

  testWidgets('the editor renders the monitor tabs and applies a layout', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(
      lang: FzLang.en,
    )));
    await tester.pumpAndSettle();

    // The monitor tab carries the engine's device name and its full area.
    expect(find.textContaining('M1'), findsOneWidget);
    expect(find.text(fzT('templates', FzLang.en)), findsOneWidget);

    await tester.tap(find.text(fzT('apply', FzLang.en)));
    await tester.pumpAndSettle();

    final File applied =
        File([dir.path, 'applied-layouts.json'].join(Platform.pathSeparator));
    expect(applied.existsSync(), isTrue, reason: 'Apply wrote the file');

    final Map<String, dynamic> root =
        jsonDecode(applied.readAsStringSync()) as Map<String, dynamic>;
    final List<dynamic> entries = root['applied-layouts'] as List<dynamic>;
    expect(entries, hasLength(1));

    final Map<String, dynamic> entry = entries.first as Map<String, dynamic>;
    expect((entry['device'] as Map<String, dynamic>)['monitor'], 'M1');
    final Map<String, dynamic> layout = entry['applied-layout'] as Map<String, dynamic>;
    expect(layout['type'], 'grid', reason: 'the default template is the grid');
    expect(layout['spacing'], 16);
    expect(layout['show-spacing'], true);
  });

  testWidgets('switching template changes what Apply writes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(
      lang: FzLang.zh,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text(fzT('t_rows', FzLang.zh)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(fzT('apply', FzLang.zh)));
    await tester.pumpAndSettle();

    final Map<String, dynamic> root =
        jsonDecode(File([dir.path, 'applied-layouts.json'].join(Platform.pathSeparator))
                .readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> layout =
        ((root['applied-layouts'] as List<dynamic>).first as Map<String, dynamic>)['applied-layout']
            as Map<String, dynamic>;
    expect(layout['type'], 'rows');
  });

  testWidgets('applying a template keeps the template selected', (WidgetTester tester) async {
    File([dir.path, 'custom-layouts.json'].join(Platform.pathSeparator))
        .writeAsStringSync(jsonEncode(<String, dynamic>{
      'custom-layouts': <dynamic>[
        <String, dynamic>{
          'uuid': '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}',
          'name': 'Mine',
          'type': 'grid',
          'info': <String, dynamic>{
            'sensitivity-radius': 20,
            'ref-width': 1920,
            'ref-height': 1080,
            'rows': 2,
            'columns': 2,
            'show-spacing': true,
            'spacing': 0,
            'rows-percentage': <int>[5000, 5000],
            'columns-percentage': <int>[5000, 5000],
            'cell-child-map': <dynamic>[<int>[0, 1], <int>[2, 3]],
          },
        },
      ],
    }));

    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(lang: FzLang.en)));
    await tester.pumpAndSettle();

    // The load preselects the only custom layout, which is what shows the quick-switch row.
    expect(find.text(fzT('quick_switch', FzLang.en)), findsOneWidget);

    await tester.tap(find.text(fzT('t_rows', FzLang.en)));
    await tester.pumpAndSettle();
    expect(find.text(fzT('quick_switch', FzLang.en)), findsNothing);

    await tester.tap(find.text(fzT('apply', FzLang.en)));
    await tester.pumpAndSettle();

    // The reload after the write used to read the deliberate -1 as "nothing selected" and jump
    // back onto the custom layout, so applying a template looked like it had done nothing.
    expect(find.text(fzT('quick_switch', FzLang.en)), findsNothing);

    final Map<String, dynamic> root =
        jsonDecode(File([dir.path, 'applied-layouts.json'].join(Platform.pathSeparator))
                .readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> layout =
        ((root['applied-layouts'] as List<dynamic>).first as Map<String, dynamic>)['applied-layout']
            as Map<String, dynamic>;
    expect(layout['type'], 'rows');
    expect(layout['uuid'], isNot('{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'));
  });

  testWidgets('the two bottom rows survive the window at its minimum width',
      (WidgetTester tester) async {
    Map<String, dynamic> monitor(String name, int number) => <String, dynamic>{
      'monitor': name,
      'monitor-instance-id': 'i$number',
      'monitor-serial-number': 's$number',
      'monitor-number': number,
      'virtual-desktop': 'vd',
      'dpi': 96,
      'top-coordinate': 0,
      'left-coordinate': 0,
      'work-area-width': 2560,
      'work-area-height': 1440,
      'monitor-width': 2560,
      'monitor-height': 1440,
      'is-selected': number == 1,
    };
    File([dir.path, 'editor-parameters.json'].join(Platform.pathSeparator))
        .writeAsStringSync(jsonEncode(<String, dynamic>{
      'process-id': 1,
      'span-zones-across-monitors': false,
      'monitors': <dynamic>[monitor('XMIA005', 1), monitor('AOC2702', 2)],
    }));
    File([dir.path, 'custom-layouts.json'].join(Platform.pathSeparator))
        .writeAsStringSync(jsonEncode(<String, dynamic>{
      'custom-layouts': <dynamic>[
        <String, dynamic>{
          'uuid': '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}',
          'name': 'Custom',
          'type': 'grid',
          'info': <String, dynamic>{
            'sensitivity-radius': 20,
            'ref-width': 1920,
            'ref-height': 1080,
            'rows': 2,
            'columns': 2,
            'show-spacing': true,
            'spacing': 0,
            'rows-percentage': <int>[5000, 5000],
            'columns-percentage': <int>[5000, 5000],
            'cell-child-map': <dynamic>[<int>[0, 1], <int>[2, 3]],
          },
        },
      ],
    }));

    for (final double width in <double>[620, 880]) {
      for (final FzLang lang in <FzLang>[FzLang.zh, FzLang.en]) {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildFzTheme(FzColors.light, lang == FzLang.zh),
            home: EditorPage(lang: lang),
          ),
        );
        await tester.pumpAndSettle();

        // Both rows sit below the fold, and the viewport has not built what it has not scrolled.
        await tester.scrollUntilVisible(
          find.text(fzT('apply', lang)),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: '${width.toInt()} ${lang.name}: nothing may overflow');
        Rect box(String key) => tester.getRect(find.ancestor(
              of: find.text(fzT(key, lang)).first,
              matching: find.byType(FzButton),
            ));
        // Right aligned either way: on one line, or with the defaults dropped underneath.
        expect(box('apply').right, closeTo(width - 32, 0.6));
        expect(box('set_default_vertical').right, closeTo(width - 32, 0.6));
        expect(box('new_layout').left, closeTo(32, 0.6));
        // The three create/edit buttons stay a row of their own rather than a one-per-line stack.
        expect(box('new_layout').top, box('edit_grid').top);
        // The delete sits immediately right of the edit button, same width, same line - it is the
        // fourth of the group, not a badge on the tile any more.
        expect(box('delete_layout').top, box('edit_grid').top);
        expect(box('delete_layout').left, closeTo(box('edit_grid').right + 8, 0.6));
        expect(box('delete_layout').width, box('edit_grid').width);
        addTearDown(tester.view.reset);
      }
    }
  });

  testWidgets('the selected custom tile can be deleted, and the confirm decides',
      (WidgetTester tester) async {
    Map<String, dynamic> grid(String uuid, String name) => <String, dynamic>{
      'uuid': uuid,
      'name': name,
      'type': 'grid',
      'info': <String, dynamic>{
        'sensitivity-radius': 20,
        'ref-width': 1920,
        'ref-height': 1080,
        'rows': 2,
        'columns': 2,
        'show-spacing': true,
        'spacing': 0,
        'rows-percentage': <int>[5000, 5000],
        'columns-percentage': <int>[5000, 5000],
        'cell-child-map': <dynamic>[<int>[0, 1], <int>[2, 3]],
      },
    };
    const String first = '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}';
    const String second = '{11111111-2222-3333-4444-555555555555}';
    File([dir.path, 'custom-layouts.json'].join(Platform.pathSeparator))
        .writeAsStringSync(jsonEncode(<String, dynamic>{
      'custom-layouts': <dynamic>[grid(first, 'Alpha'), grid(second, 'Beta')],
    }));
    FzStore.writeLayoutHotkeys(<String, int>{first: 3});

    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(lang: FzLang.en)));
    await tester.pumpAndSettle();

    final Finder del = find.ancestor(
      of: find.text(fzT('delete_layout', FzLang.en)),
      matching: find.byType(FzButton),
    );
    // The action row carries exactly one, and it is the delete of whatever is selected.
    expect(del, findsOneWidget);
    expect(tester.widget<FzButton>(del).enabled, isTrue);

    await tester.tap(del);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'deleting must ask first');
    expect(find.text('Alpha'), findsWidgets);

    await tester.tap(find.text(fzT('cancel', FzLang.en)).last);
    await tester.pumpAndSettle();
    expect(
      File([dir.path, 'custom-layouts.json'].join(Platform.pathSeparator))
          .readAsStringSync(),
      contains('Beta'),
      reason: 'cancel must not touch the file',
    );

    await tester.tap(del);
    await tester.pumpAndSettle();
    await tester.tap(find.text(fzT('ok', FzLang.en)).last);
    // The panel animates itself out first (150ms), and only then does the delete run; the status
    // line it leaves behind collapses on its own after 2.6s, so read it in between.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining(fzT('deleted', FzLang.en)), findsOneWidget);
    await tester.pumpAndSettle();

    final String left = File([dir.path, 'custom-layouts.json']
            .join(Platform.pathSeparator))
        .readAsStringSync();
    expect(left, isNot(contains('Alpha')));
    expect(left, contains('Beta'));
    // The digit that pointed at the deleted layout goes with it, so no key is left dead.
    expect(
      File([dir.path, 'layout-hotkeys.json'].join(Platform.pathSeparator))
          .readAsStringSync(),
      isNot(contains(first)),
    );
    // Beta moved into the selected slot, so the same button is still pointing at a layout.
    expect(del, findsOneWidget);
    expect(tester.widget<FzButton>(del).enabled, isTrue);

    // A template selection has nothing to delete, and the button says so rather than vanishing.
    await tester.tap(find.text(fzT('t_focus', FzLang.en)).first);
    await tester.pumpAndSettle();
    expect(del, findsOneWidget);
    expect(tester.widget<FzButton>(del).enabled, isFalse);
  });

  testWidgets('only the delete button takes the danger colour under the pointer',
      (WidgetTester tester) async {
    File([dir.path, 'custom-layouts.json'].join(Platform.pathSeparator))
        .writeAsStringSync(jsonEncode(<String, dynamic>{
      'custom-layouts': <dynamic>[
        <String, dynamic>{
          'uuid': '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}',
          'name': 'Alpha',
          'type': 'grid',
          'info': <String, dynamic>{
            'sensitivity-radius': 20,
            'ref-width': 1920,
            'ref-height': 1080,
            'rows': 2,
            'columns': 2,
            'show-spacing': true,
            'spacing': 0,
            'rows-percentage': <int>[5000, 5000],
            'columns-percentage': <int>[5000, 5000],
            'cell-child-map': <dynamic>[<int>[0, 1], <int>[2, 3]],
          },
        },
      ],
    }));

    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(lang: FzLang.en)));
    await tester.pumpAndSettle();

    final FzColors colors = Theme.of(tester.element(find.byType(EditorPage)))
        .extension<FzTheme>()!
        .colors;
    Finder button(String key) => find.ancestor(
          of: find.text(fzT(key, FzLang.en)),
          matching: find.byType(FzButton),
        );
    expect(tester.widget<FzButton>(button('edit_grid')).dangerOnHover, isFalse,
        reason: 'the destructive one is the only one that may go red');
    final Finder del = button('delete_layout');
    expect(tester.widget<FzButton>(del).dangerOnHover, isTrue);

    // The lerped decoration lives on the Container the AnimatedContainer builds.
    final Finder skin = find
        .descendant(of: del, matching: find.byType(Container))
        .first;
    BoxDecoration skinStyle() =>
        tester.widget<Container>(skin).decoration as BoxDecoration;
    Color skinLabel() => tester
        .widget<Text>(
            find.descendant(of: del, matching: find.byType(Text)))
        .style!
        .color!;

    expect(skinStyle().border!.top.color, colors.fieldBorder);
    expect(skinStyle().boxShadow!.single.color.a, 0, reason: 'idle has no ring');
    expect(skinLabel(), colors.ink);

    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(del));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();

    expect(skinStyle().border!.top.color, colors.danger);
    expect(skinLabel(), colors.danger);
    expect(skinStyle().boxShadow!.single.color,
        colors.danger.withValues(alpha: 0.35));
    expect(skinStyle().boxShadow!.single.spreadRadius, 1);
    // The fill is the ordinary hover band: only the hairline, the label and the ring turn.
    expect(skinStyle().color, colors.hover);
  });

  testWidgets('a fixed template opens its own page, where only the two numbers move',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(lang: FzLang.en)));
    await tester.pumpAndSettle();

    // The knobs left the browse page, and the button now says which page it opens - a template has
    // no zones to edit, so it is not 编辑网格.
    expect(find.text(fzT('zone_count', FzLang.en)), findsNothing);
    final Finder editBtn = find.text(fzT('edit_template', FzLang.en));
    await tester.scrollUntilVisible(editBtn, 240,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('template')), findsOneWidget);

    int zoneCount() => tester.widgetList(find.byType(AnimatedPositioned)).length;
    final int before = zoneCount();
    expect(find.text(fzT('spacing', FzLang.en)), findsOneWidget);
    expect(find.text(fzT('show_spacing', FzLang.en)), findsOneWidget);
    expect(find.text(fzT('split_lr', FzLang.en)), findsNothing,
        reason: 'a fixed template cannot be split or dragged');

    await tester.enterText(find.byType(EditableText).first, '5');
    await tester.pumpAndSettle();
    expect(zoneCount(), greaterThan(before),
        reason: 'the preview follows the zone count at once');

    await tester.tap(find.text(fzT('apply_only', FzLang.en)));
    await tester.pumpAndSettle();
    final Map<String, dynamic> applied = jsonDecode(
      File([dir.path, 'applied-layouts.json'].join(Platform.pathSeparator))
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final Map<String, dynamic> written =
        ((applied['applied-layouts'] as List<dynamic>).first
                as Map<String, dynamic>)['applied-layout']
            as Map<String, dynamic>;
    expect(written['type'], 'grid');
    expect(written['zone-count'], 5);

    // 另存为自定义 hands the tuned shape to the real editor, which is where zones come apart.
    await tester.tap(find.text(fzT('save_as_custom', FzLang.en)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('grid')), findsOneWidget);
    await tester.tap(find.text(fzT('save_layout', FzLang.en)));
    await tester.pumpAndSettle();

    final List<FzCustomLayout> saved = FzStore.readCustomLayouts();
    expect(saved, hasLength(1));
    expect(saved.first.name, fzT('t_grid', FzLang.en),
        reason: 'the copy is named after what it came from');
    expect(saved.first.zoneCount, 5);
    expect(saved.first.isCanvas, isFalse);
  });

  testWidgets('each fixed template keeps its own gap', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(lang: FzLang.en)));
    await tester.pumpAndSettle();

    Future<void> tune(String tile, String value) async {
      await tester.tap(find.text(fzT(tile, FzLang.en)).first);
      await tester.pumpAndSettle();
      final Finder editBtn = find.text(fzT('edit_template', FzLang.en));
      await tester.scrollUntilVisible(editBtn, 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(editBtn);
      await tester.pumpAndSettle();
      // The zone count is first; the gap is the other number field on the page.
      await tester.enterText(find.byType(EditableText).last, value);
      await tester.pumpAndSettle();
      await tester.tap(find.text(fzT('cancel', FzLang.en)));
      await tester.pumpAndSettle();
    }

    await tune('t_grid', '40');
    await tune('t_priority', '4');

    // Tuning one template left the other alone - which is the whole reason these are stored per
    // type rather than as one slider on the browse page.
    final Map<String, int> gaps = <String, int>{
      for (final FzLayout l in FzStore.readTemplates())
        kLayoutTypeNames[l.type]!: l.spacing,
    };
    expect(gaps['grid'], 40);
    expect(gaps['priority-grid'], 4);

    // Reopening each page shows its own number, not the last one typed.
    Future<String> gapOf(String tile) async {
      await tester.tap(find.text(fzT(tile, FzLang.en)).first);
      await tester.pumpAndSettle();
      final Finder editBtn = find.text(fzT('edit_template', FzLang.en));
      await tester.scrollUntilVisible(editBtn, 240,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(editBtn);
      await tester.pumpAndSettle();
      final String shown = tester
          .widget<EditableText>(find.byType(EditableText).last)
          .controller
          .text;
      await tester.tap(find.text(fzT('cancel', FzLang.en)));
      await tester.pumpAndSettle();
      return shown;
    }

    expect(await gapOf('t_grid'), '40');
    expect(await gapOf('t_priority'), '4');
  });

  testWidgets('focus zones go to the canvas editor, because a grid cannot overlap',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(lang: FzLang.en)));
    await tester.pumpAndSettle();

    await tester.tap(find.text(fzT('t_focus', FzLang.en)).first);
    await tester.pumpAndSettle();
    final Finder editBtn = find.text(fzT('edit_template', FzLang.en));
    await tester.scrollUntilVisible(editBtn, 240,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(editBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text(fzT('save_as_custom', FzLang.en)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('canvas')), findsOneWidget,
        reason: 'cascading zones are not something a grid can say');

    await tester.tap(find.text(fzT('save_layout', FzLang.en)));
    await tester.pumpAndSettle();
    final List<FzCustomLayout> saved = FzStore.readCustomLayouts();
    expect(saved, hasLength(1));
    expect(saved.first.isCanvas, isTrue);
    expect(saved.first.canvasZones.length, 3,
        reason: 'the default zone count is three cascading focus rects');
    expect(saved.first.referenceWidth, greaterThan(0),
        reason: 'the canvas is sized to the monitor it was opened from');
  });

  testWidgets('the tab strip, the sections and the spacing toggle keep their geometry',
      (WidgetTester tester) async {
    File([dir.path, 'custom-layouts.json'].join(Platform.pathSeparator))
        .writeAsStringSync(jsonEncode(<String, dynamic>{
      'custom-layouts': <dynamic>[
        <String, dynamic>{
          'uuid': '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}',
          'name': 'Custom',
          'type': 'grid',
          'info': <String, dynamic>{
            'sensitivity-radius': 20,
            'ref-width': 1920,
            'ref-height': 1080,
            'rows': 2,
            'columns': 2,
            'show-spacing': true,
            'spacing': 0,
            'rows-percentage': <int>[5000, 5000],
            'columns-percentage': <int>[5000, 5000],
            'cell-child-map': <dynamic>[<int>[0, 1], <int>[2, 3]],
          },
        },
      ],
    }));

    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(EditorPage(lang: FzLang.en)));
    await tester.pumpAndSettle();

    // The specimen's `.tabs` carries `margin-bottom: var(--section)`; the tab strip used to sit on
    // `header`, twice that, which left it floating above the first section. Measured from the tab
    // box rather than its label, which is centred inside a 36px strip.
    final Rect tabs = tester.getRect(find.ancestor(
      of: find.textContaining('M1'),
      matching: find.byType(AnimatedContainer),
    ).first);
    final Rect templates = tester.getRect(find.text(fzT('templates', FzLang.en)));
    expect(
      templates.top - tabs.bottom,
      closeTo(FzMetrics.section, 0.6),
      reason: 'the gap is the section token, not the header one',
    );

    // The 20px switch used to ride at the top of the 32px line the fields define. The three fields
    // now live on the template page, so that is where the row gets measured - which means taking
    // the selection off the saved layout this test seeded first.
    await tester.tap(find.text(fzT('t_grid', FzLang.en)).first);
    await tester.pumpAndSettle();
    final Finder editBtn = find.text(fzT('edit_template', FzLang.en));
    await tester.scrollUntilVisible(editBtn, 240,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(editBtn);
    await tester.pumpAndSettle();
    final Rect toggle = tester.getRect(find.byType(FzToggle).first);
    final Rect zones = tester.getRect(
      find.text(fzT('zone_count', FzLang.en)),
    );
    expect(toggle.center.dy, closeTo(zones.center.dy, 0.6),
        reason: 'the spacing switch is centred in the row like everything else');
  });

  testWidgets('hovering a tab fades the band in without passing through black',
      (WidgetTester tester) async {
    Map<String, dynamic> monitor(String name, int number) => <String, dynamic>{
      'monitor': name,
      'monitor-instance-id': 'i$number',
      'monitor-serial-number': 's$number',
      'monitor-number': number,
      'virtual-desktop': 'vd',
      'dpi': 96,
      'top-coordinate': 0,
      'left-coordinate': 0,
      'work-area-width': 1920,
      'work-area-height': 1080,
      'monitor-width': 1920,
      'monitor-height': 1080,
      'is-selected': number == 1,
    };
    File([dir.path, 'editor-parameters.json'].join(Platform.pathSeparator))
        .writeAsStringSync(jsonEncode(<String, dynamic>{
      'process-id': 1,
      'span-zones-across-monitors': false,
      'monitors': <dynamic>[monitor('M1', 1), monitor('M2', 2)],
    }));

    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EditorPage(lang: FzLang.en)));
    await tester.pumpAndSettle();

    final FzColors colors = Theme.of(tester.element(find.byType(EditorPage)))
        .extension<FzTheme>()!
        .colors;
    final Finder tab = find
        .ancestor(of: find.textContaining('M2'), matching: find.byType(AnimatedContainer))
        .first;
    // The lerped value lives on the `Container` an `AnimatedContainer` builds, not on the
    // AnimatedContainer itself - reading the latter only ever shows the target.
    final Finder bandCell = find
        .descendant(of: tab, matching: find.byType(Container))
        .first;

    Color band() =>
        (tester.widget<Container>(bandCell).decoration as BoxDecoration).color!;

    // An idle tab is invisible, but its hue is already the hover hue. Reading it as
    // Colors.transparent made the fade-in pass through transparent *black*, which is the dark
    // flash the tab used to show before settling pale.
    expect(band().a, 0);
    expect(band().r, closeTo(colors.hover.r, 0.001));

    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(tab));
    addTearDown(mouse.removePointer);

    final List<Color> frames = <Color>[];
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 15));
      frames.add(band());
    }
    for (final Color f in frames) {
      expect(f.r, closeTo(colors.hover.r, 0.001),
          reason: 'a fade may only change alpha, never the hue');
      expect(f.a, inInclusiveRange(0.0, colors.hover.a));
    }
    expect(frames.any((Color f) => f.a > 0 && f.a < colors.hover.a), isTrue,
        reason: 'it really is a fade, not a swap');

    await tester.pumpAndSettle();
    expect(band(), colors.hover);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(band().a, 0);
    expect(band().r, closeTo(colors.hover.r, 0.001));
  });
}
