import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/canvas_editor.dart';
import 'package:fzones_ui/design.dart';
import 'package:fzones_ui/editor_page.dart';
import 'package:fzones_ui/layout_store.dart';
import 'package:fzones_ui/settings_model.dart';
import 'package:fzones_ui/strings.dart';
import 'package:fzones_ui/widgets.dart';

/// The grid and canvas sub-editors, driven through the real widget tree against a temp folder.
void main() {
  group('canvas geometry', () {
    test('a move snaps to the 32px grid and stays inside the reference area', () {
      const FzRect original = FzRect(100, 100, 500, 400);
      final FzRect moved = fzDragZone(
        original: original,
        dx: 37,
        dy: -63,
        edges: <FzEdge>{},
        refW: 1000,
        refH: 800,
      );
      expect(moved.left % 32, 0);
      expect(moved.top % 32, 0);
      expect(moved.width, original.width, reason: 'a move keeps the size');
      expect(moved.height, original.height);
      expect(moved.left, 128, reason: '100 + 37 snapped to 128');
      expect(moved.top, 32, reason: '100 - 63 snapped to 32');
    });

    test('a move cannot leave the reference area', () {
      const FzRect original = FzRect(0, 0, 400, 300);
      final FzRect moved = fzDragZone(
        original: original,
        dx: -500,
        dy: -500,
        edges: <FzEdge>{},
        refW: 1000,
        refH: 800,
      );
      expect(moved.left, 0);
      expect(moved.top, 0);
    });

    test('a resize respects the 64px minimum side', () {
      const FzRect original = FzRect(100, 100, 400, 400);
      // Dragging the left edge right is what runs into the minimum width.
      final FzRect squashed = fzDragZone(
        original: original,
        dx: 300,
        dy: 0,
        edges: <FzEdge>{FzEdge.left},
        refW: 1000,
        refH: 800,
      );
      expect(squashed.width, 64, reason: 'clamped to kCanvasMinSide');
      expect(squashed.right, 400, reason: 'the opposite edge does not move');
      expect(squashed.left, 336, reason: '400 - 64');

      // Dragging it left instead stops at the edge of the reference area.
      final FzRect flattened = fzDragZone(
        original: original,
        dx: -900,
        dy: 0,
        edges: <FzEdge>{FzEdge.left},
        refW: 1000,
        refH: 800,
      );
      expect(flattened.left, 0);
      expect(flattened.right, 400);

      final FzRect stretched = fzDragZone(
        original: original,
        dx: 900,
        dy: 0,
        edges: <FzEdge>{FzEdge.right},
        refW: 1000,
        refH: 800,
      );
      expect(stretched.right, 1000, reason: 'clamped to the reference width');
    });

    test('a border other zones sit on moves them with it', () {
      // The layout from the report: one zone down the left, two stacked on the right touching it.
      final List<FzRect> zones = <FzRect>[
        const FzRect(0, 0, 384, 768),
        const FzRect(384, 0, 1024, 384),
        const FzRect(384, 384, 1024, 768),
      ];
      final List<FzRect> out = fzDragZoneLinked(
        zones: zones,
        index: 0,
        edges: <FzEdge>{FzEdge.right},
        dx: -128,
        dy: 0,
        refW: 1024,
        refH: 768,
      );
      expect(out[0].right, 256);
      expect(out[1].left, 256, reason: 'both right-hand zones follow the seam');
      expect(out[2].left, 256);
      expect(out[1].right, 1024, reason: 'their far edges do not move');
      expect(out[2].right, 1024);
      expect(out[1].top, 0, reason: 'a horizontal seam leaves the vertical split alone');
      expect(out[2].top, 384);

      // The same seam from the other side: two zones ending on a border move together.
      final List<FzRect> stacked = <FzRect>[
        const FzRect(0, 0, 384, 384),
        const FzRect(0, 384, 384, 768),
        const FzRect(384, 0, 1024, 768),
      ];
      final List<FzRect> both = fzDragZoneLinked(
        zones: stacked,
        index: 2,
        edges: <FzEdge>{FzEdge.left},
        dx: -128,
        dy: 0,
        refW: 1024,
        refH: 768,
      );
      expect(both[2].left, 256);
      expect(both[0].right, 256);
      expect(both[1].right, 256);
    });

    test('a zone that merely shares a coordinate is not linked', () {
      final List<FzRect> zones = <FzRect>[
        const FzRect(0, 0, 384, 384),
        const FzRect(384, 0, 1024, 384),
        // Its left edge is on the same seam, but nowhere near the dragged zone's span.
        const FzRect(384, 512, 1024, 768),
      ];
      final List<FzRect> out = fzDragZoneLinked(
        zones: zones,
        index: 0,
        edges: <FzEdge>{FzEdge.right},
        dx: -128,
        dy: 0,
        refW: 1024,
        refH: 768,
      );
      expect(out[0].right, 256);
      expect(out[1].left, 256);
      expect(out[2].left, 384, reason: 'touching means sharing a run, not an x');
    });

    test('the seam stops where the tightest neighbour does', () {
      final List<FzRect> zones = <FzRect>[
        const FzRect(0, 0, 384, 768),
        // Already at the 64px minimum, so the border cannot travel right at all.
        const FzRect(384, 0, 448, 768),
      ];
      final List<FzRect> out = fzDragZoneLinked(
        zones: zones,
        index: 0,
        edges: <FzEdge>{FzEdge.right},
        dx: 128,
        dy: 0,
        refW: 1024,
        refH: 768,
      );
      expect(out[0].right, 384);
      expect(out[1].left, 384);
      expect(out[1].width, 64);

      // Left instead, where nothing is in the way but the reference area's own edge.
      final List<FzRect> free = fzDragZoneLinked(
        zones: zones,
        index: 0,
        edges: <FzEdge>{FzEdge.right},
        dx: -320,
        dy: 0,
        refW: 1024,
        refH: 768,
      );
      expect(free[0].right, 64, reason: 'the dragged zone keeps its own minimum');
      expect(free[1].left, 64);
      expect(free[1].width, 384);
    });

    test('a move drags nothing with it', () {
      final List<FzRect> zones = <FzRect>[
        const FzRect(0, 0, 384, 384),
        const FzRect(384, 0, 1024, 384),
      ];
      final List<FzRect> out = fzDragZoneLinked(
        zones: zones,
        index: 0,
        edges: <FzEdge>{},
        dx: 32,
        dy: 32,
        refW: 1024,
        refH: 768,
      );
      expect(out[0], const FzRect(32, 32, 416, 416));
      expect(out[1], zones[1], reason: 'a move is not a seam');
    });

    test('double-clicking a seam gives each side the same share', () {
      // One zone down the left, two stacked on the right - the seam runs the full height.
      final List<FzRect> zones = <FzRect>[
        const FzRect(0, 0, 704, 768),
        const FzRect(704, 0, 1024, 384),
        const FzRect(704, 384, 1024, 768),
      ];
      final List<FzRect> fromLeft = fzEqualiseBorder(
        zones: zones,
        index: 0,
        edge: FzEdge.right,
        refW: 1024,
        refH: 768,
      );
      expect(fromLeft[0].right, 512);
      expect(fromLeft[1].left, 512);
      expect(fromLeft[2].left, 512);

      // The same click on the other side of the seam. The zone under the pointer is only half as
      // tall as the seam, so the seam has to be worked out before the members are.
      final List<FzRect> fromRight = fzEqualiseBorder(
        zones: zones,
        index: 1,
        edge: FzEdge.left,
        refW: 1024,
        refH: 768,
      );
      expect(fromRight[0].right, 512, reason: 'the far zone comes with it - same seam');
      expect(fromRight[1].left, 512);
      expect(fromRight[2].left, 512, reason: 'and the one that does not touch the pointer too');
      expect(fromRight[2].top, 384, reason: 'the horizontal split is not this seam to even out');

      // One to one.
      final List<FzRect> pair = fzEqualiseBorder(
        zones: <FzRect>[
          const FzRect(0, 0, 320, 768),
          const FzRect(320, 0, 1024, 768),
        ],
        index: 0,
        edge: FzEdge.right,
        refW: 1024,
        refH: 768,
      );
      expect(pair[0].right, 512);
      expect(pair[1].left, 512);
    });

    test('an even split that would starve a neighbour does not happen', () {
      final List<FzRect> zones = <FzRect>[
        const FzRect(0, 0, 320, 768),
        // Two zones on the far side of the seam, and the upper one is already at the 64px minimum,
        // so the middle of the group is out of reach: the seam stays where it is.
        const FzRect(320, 0, 384, 384),
        const FzRect(320, 384, 1024, 768),
      ];
      final List<FzRect> out = fzEqualiseBorder(
        zones: zones,
        index: 0,
        edge: FzEdge.right,
        refW: 1024,
        refH: 768,
      );
      expect(out[0].right, 320);
      expect(out[1].left, 320);
      expect(out[2].left, 320);
      expect(out[1].width, 64);
    });

    test('a corner grab reports both edges', () {
      const Rect box = Rect.fromLTWH(100, 100, 200, 150);
      expect(fzEdgesAt(box, const Offset(101, 101)),
          <FzEdge>{FzEdge.left, FzEdge.top});
      expect(fzEdgesAt(box, const Offset(299, 249)),
          <FzEdge>{FzEdge.right, FzEdge.bottom});
      expect(fzEdgesAt(box, const Offset(200, 175)), isEmpty,
          reason: 'the middle is a move, not a resize');
    });

    test('adding a zone never lands on top of an existing one', () {
      const int w = 2560;
      const int h = 1440;
      final List<FzRect> existing = <FzRect>[fzNewCanvasZone(w, h, <FzRect>[])];
      final FzRect added = fzNewCanvasZone(w, h, existing);
      expect(added.width, greaterThan(0));
      expect(added.height, greaterThan(0));
      final FzRect first = existing.first;
      final bool overlaps = added.left < first.right &&
          first.left < added.right &&
          added.top < first.bottom &&
          first.top < added.bottom;
      expect(overlaps, isFalse);
    });
  });

  group('sub-editors', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fzeditors');
      FzPaths.overrideDir = dir.path;
      File([dir.path, 'editor-parameters.json'].join(Platform.pathSeparator))
          .writeAsStringSync(jsonEncode(<String, dynamic>{
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

    Widget host() => MaterialApp(
          theme: buildFzTheme(FzColors.light, false),
          home: EditorPage(
            lang: FzLang.en,
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
    }

    List<FzCustomLayout> readCustom() => FzStore.readCustomLayouts();

    testWidgets('the template tiles stagger in on --d-enter',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.pump();

      double opacity(int tile) => tester
          .widget<Opacity>(find
              .descendant(
                  of: find.byType(FzEnter).at(tile),
                  matching: find.byType(Opacity))
              .first)
          .opacity;

      expect(find.byType(FzEnter), findsNWidgets(6),
          reason: 'one wrapper per template tile, and no custom layouts in the fixture');
      expect(opacity(0), 0, reason: 'nothing has started yet');

      // The delay fires on a timer, so the first frame after it only starts the tween; the
      // 40 + 60ms pair puts tile 0 mid-flight while tile 5 (130ms) has not been released yet.
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(0), greaterThan(0));
      expect(opacity(0), lessThan(1));
      expect(opacity(5), 0, reason: 'its step has not elapsed');

      await tester.pumpAndSettle();
      for (int tile = 0; tile < 6; tile++) {
        expect(opacity(tile), 1, reason: 'tile $tile settles at full');
      }
    });

    testWidgets('the grid editor splits a zone and saves a new custom layout',
        (WidgetTester tester) async {
      await settle(tester);

      await tester.tap(find.text(fzT('new_layout', FzLang.en)));
      await tester.pumpAndSettle();
      expect(find.text(fzT('grid_hint', FzLang.en)), findsOneWidget,
          reason: 'the grid page is showing');

      // The selected zone of a fresh 2x2 is one band wide, so splitting it inserts a band for
      // the whole grid: 4 zones become 5 (the split pair plus the other three).
      await tester.tap(find.text(fzT('split_lr', FzLang.en)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(fzT('save_layout', FzLang.en)));
      await tester.pumpAndSettle();

      final List<FzCustomLayout> saved = readCustom();
      expect(saved, hasLength(1));
      expect(saved.first.isCanvas, isFalse);
      expect(saved.first.columns, 3, reason: 'the split added a band');
      expect(saved.first.zoneCount, 5);
      expect(saved.first.cellChildMap, isNotEmpty);
      expect(saved.first.rowsPercentage.reduce((int a, int b) => a + b), 10000);
    });

    testWidgets('a split repaints on its own, without a click to wake it',
        (WidgetTester tester) async {
      await settle(tester);

      await tester.tap(find.text(fzT('new_layout', FzLang.en)));
      await tester.pumpAndSettle();

      int zones() => tester.widgetList(find.byType(AnimatedPositioned)).length;
      expect(zones(), 4, reason: 'a fresh 2x2');

      await tester.tap(find.text(fzT('merge_right', FzLang.en)));
      await tester.pumpAndSettle();
      expect(zones(), 3, reason: 'the merge joined two zones');

      // The split buttons used to mutate the model without asking for a rebuild, so the grid only
      // caught up on whatever click came next - which is exactly what "you have to click the zone
      // again before it splits" looked like from the outside.
      await tester.tap(find.text(fzT('split_lr', FzLang.en)));
      await tester.pumpAndSettle();
      expect(zones(), 4, reason: 'the merged zone splits at once');

      await tester.tap(find.text(fzT('split_tb', FzLang.en)));
      await tester.pumpAndSettle();
      expect(zones(), 5);
    });

    testWidgets('the grid editor saves the gap of the layout it is editing',
        (WidgetTester tester) async {
      await settle(tester);

      await tester.tap(find.text(fzT('new_layout', FzLang.en)));
      await tester.pumpAndSettle();
      // rows, columns, name in the bar, then the gap below the tools.
      final Finder spacing = find.byType(EditableText).last;
      await tester.enterText(spacing, '32');
      await tester.pumpAndSettle();
      await tester.tap(find.text(fzT('save_layout', FzLang.en)));
      await tester.pumpAndSettle();

      final List<FzCustomLayout> saved = readCustom();
      expect(saved.single.spacing, 32);
      expect(saved.single.showSpacing, isTrue);

      // Reopening it shows the number back, and turning the switch off is what gets saved.
      await tester.tap(find.text(fzT('edit_grid', FzLang.en)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText).last).controller.text,
        '32');
      await tester.tap(find.byType(FzToggle).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(fzT('save_layout', FzLang.en)));
      await tester.pumpAndSettle();

      final List<FzCustomLayout> again = readCustom();
      expect(again, hasLength(1), reason: 'the same layout was replaced, not appended');
      expect(again.single.spacing, 32);
      expect(again.single.showSpacing, isFalse);
    });

    testWidgets('the --grid and --canvas deep links open those pages directly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<void> pumpWith(String page) async {
        await tester.pumpWidget(MaterialApp(
          theme: buildFzTheme(FzColors.light, false),
          home: EditorPage(
            // A distinct key per page, or Flutter reuses the State and initState never runs.
            key: ValueKey<String>(page),
            lang: FzLang.en,
            startPage: page,
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pumpWith('grid');
      expect(find.text(fzT('grid_hint', FzLang.en)), findsOneWidget);

      await pumpWith('canvas');
      expect(find.text(fzT('canvas_hint', FzLang.en)), findsOneWidget);

      await pumpWith('browse');
      expect(find.text(fzT('templates', FzLang.en)), findsOneWidget);
    });

    testWidgets('the canvas editor adds a zone and saves it', (WidgetTester tester) async {
      await settle(tester);

      await tester.tap(find.text(fzT('new_canvas', FzLang.en)));
      await tester.pumpAndSettle();
      expect(find.text(fzT('canvas_hint', FzLang.en)), findsOneWidget,
          reason: 'the canvas page is showing');

      await tester.tap(find.text(fzT('add_zone', FzLang.en)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(fzT('save_layout', FzLang.en)));
      await tester.pumpAndSettle();

      final List<FzCustomLayout> saved = readCustom();
      expect(saved, hasLength(1));
      expect(saved.first.isCanvas, isTrue);
      expect(saved.first.zoneCount, 2, reason: 'the starting zone plus the added one');
      expect(saved.first.referenceWidth, 1920, reason: 'the monitor work area');
      expect(saved.first.referenceHeight, 1080);
    });

    testWidgets('editing an existing layout replaces it instead of appending',
        (WidgetTester tester) async {
      final FzCustomLayout existing = FzCustomLayout(
        name: 'Two columns',
        rows: 1,
        columns: 2,
        rowsPercentage: <int>[10000],
        columnsPercentage: <int>[5000, 5000],
        cellChildMap: <List<int>>[
          <int>[0, 1]
        ],
      );
      FzStore.writeCustomLayouts(<FzCustomLayout>[existing]);

      await settle(tester);

      await tester.tap(find.text(fzT('edit_grid', FzLang.en)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(fzT('split_tb', FzLang.en)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(fzT('save_layout', FzLang.en)));
      await tester.pumpAndSettle();

      final List<FzCustomLayout> saved = readCustom();
      expect(saved, hasLength(1), reason: 'the same uuid was replaced');
      expect(saved.first.uuid, existing.uuid);
      expect(saved.first.name, 'Two columns');
      expect(saved.first.rows, 2, reason: 'the split added a row');
    });
  });
}
