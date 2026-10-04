import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/editor_page.dart';
import 'package:fzones_ui/grid_model.dart';
import 'package:fzones_ui/layout_store.dart';

/// The priority-grid shapes are copied by hand from the engine's C++ table, which is exactly the
/// kind of copy that drifts. So one test compares them against the source text itself.
void main() {
  const FzRect monitor = FzRect(0, 0, 1000, 600);

  List<FzRect> shapes(int zoneCount) =>
      priorityGridShapeFor(zoneCount).zoneRects(monitor);

  test('the ported table is entry for entry the engine table', () {
    final File source = File(
      [
        '..',
        'PowerToys',
        'src',
        'modules',
        'fancyzones',
        'FancyZonesLib',
        'LayoutConfigurator.cpp',
      ].join(Platform.pathSeparator),
    );
    if (!source.existsSync()) {
      markTestSkipped('no engine source next to the UI checkout at ${source.path}');
      return;
    }

    final String text = source.readAsStringSync();
    final int start = text.indexOf('predefinedPriorityGridLayouts');
    final int end = text.indexOf('};', start);
    expect(start, greaterThan(0), reason: 'the engine table moved or was renamed');
    final List<String> entries = text
        .substring(start, end)
        .split('FancyZonesDataTypes::GridLayoutInfo(FancyZonesDataTypes::GridLayoutInfo::Full{')
        .where((String e) => e.contains('.rows'))
        .toList();

    expect(entries.length, kPriorityGridShapes.length,
        reason: 'a row was added to one table and not the other');

    List<int> numbers(String raw) =>
        RegExp(r'-?\d+').allMatches(raw).map((Match m) => int.parse(m.group(0)!)).toList();

    for (int i = 0; i < entries.length; i++) {
      final String entry = entries[i];
      final FzGridModel mine = kPriorityGridShapes[i];
      final String rows = entry.split('.columns').first;
      final String columns = entry
          .split('.columns')[1]
          .split('.rowsPercents')
          .first;
      final String rowsPercent = entry
          .split('.rowsPercents = {')[1]
          .split('}')
          .first;
      final String columnsPercent = entry
          .split('.columnsPercents = {')[1]
          .split('}')
          .first;
      final String cellMap = entry.split('.cellChildMap = {')[1].split(' } }),').first;

      expect(numbers(rows).first, mine.rows, reason: 'zone count ${i + 1}: rows');
      expect(numbers(columns).first, mine.columns, reason: 'zone count ${i + 1}: columns');
      expect(numbers(rowsPercent), mine.rowsPercentage,
          reason: 'zone count ${i + 1}: row percentages');
      expect(numbers(columnsPercent), mine.columnsPercentage,
          reason: 'zone count ${i + 1}: column percentages');
      expect(
        RegExp(r'\{\s*[-\d,\s]+?\}')
            .allMatches(cellMap)
            .map((Match m) => numbers(m.group(0)!))
            .toList(),
        mine.cellChildMap,
        reason: 'zone count ${i + 1}: cell child map',
      );
    }
  });

  test('the specimen draws the same eleven shapes', () {
    final File html = File(
      ['..', 'fzones-ui-v3.html'].join(Platform.pathSeparator),
    );
    if (!html.existsSync()) {
      markTestSkipped('no specimen next to the UI checkout at ${html.path}');
      return;
    }

    final String text = html.readAsStringSync();
    final int start = text.indexOf('const PRIORITY = [');
    final int end = text.indexOf('];', start);
    expect(start, greaterThan(0), reason: 'the specimen table moved or was renamed');
    final List<String> entries = RegExp(
      r'\{r:\d+,c:\d+,rp:\[[^\]]*\],cp:\[[^\]]*\],m:\[[^\]]*\](?:,[^\]]*\])*\]\}',
    ).allMatches(text.substring(start, end)).map((Match m) => m.group(0)!).toList();

    expect(entries.length, kPriorityGridShapes.length,
        reason: 'the specimen and the app carry different numbers of shapes');

    List<int> numbers(String raw) =>
        RegExp(r'\d+').allMatches(raw).map((Match m) => int.parse(m.group(0)!)).toList();

    for (int i = 0; i < entries.length; i++) {
      final String entry = entries[i];
      final FzGridModel mine = kPriorityGridShapes[i];
      expect(numbers(entry.split('rp:').last.split(']').first), mine.rowsPercentage,
          reason: 'zone count ${i + 1}: the specimen row bands differ');
      expect(numbers(entry.split('cp:').last.split(']').first), mine.columnsPercentage,
          reason: 'zone count ${i + 1}: the specimen column bands differ');
      expect(
        RegExp(r'\[\d+(?:,\d+)*\]')
            .allMatches(entry.split('m:[').last)
            .map((Match m) => numbers(m.group(0)!))
            .toList(),
        mine.cellChildMap,
        reason: 'zone count ${i + 1}: the specimen cell map differs',
      );
    }
  });

  test('the priority family is not the plain grid: two zones is 2/3 plus 1/3', () {
    expect(shapes(2), <FzRect>[
      const FzRect(0, 0, 667, 600),
      const FzRect(667, 0, 1000, 600),
    ]);
  });

  test('three zones keeps the middle one as the priority zone', () {
    expect(shapes(3), <FzRect>[
      const FzRect(0, 0, 250, 600),
      const FzRect(250, 0, 750, 600),
      const FzRect(750, 0, 1000, 600),
    ]);
  });

  test('four zones splits the outer columns and leaves the middle full height', () {
    final List<FzRect> zones = shapes(4);
    expect(zones, <FzRect>[
      const FzRect(0, 0, 250, 600),
      const FzRect(250, 0, 750, 600),
      const FzRect(750, 0, 1000, 300),
      const FzRect(750, 300, 1000, 600),
    ]);
    // Zones come back in id order, which is what the tile numbers and the engine snaps to.
    expect(zones.map((FzRect r) => r.width).toList(), <int>[250, 500, 250, 250]);
  });

  test('every shape covers the monitor without leaving a hole', () {
    for (int count = 1; count <= 10; count++) {
      final List<FzRect> zones = shapes(count);
      expect(zones.length, count, reason: 'zone count $count');
      int area = 0;
      for (final FzRect z in zones) {
        area += z.width * z.height;
      }
      expect(area, 1000 * 600, reason: 'zone count $count tiles the whole area');
    }
  });

  test('eleven zones falls back to the plain grid, exactly like the engine', () {
    // `PriorityGrid` tests `zoneCount < predefinedLayoutsCount`, so the eleventh table entry is
    // never reached in C++ either. The preview follows the engine rather than the intention.
    expect(shapes(11), gridShapeFor(11).zoneRects(monitor));
    expect(shapes(11), isNot(kPriorityGridShapes[10].zoneRects(monitor)),
        reason: 'the hand-tuned eleventh shape is the one the engine never builds');
    expect(shapes(12), gridShapeFor(12).zoneRects(monitor));
  });

  test('the tile draws the priority template, not the columns one', () {
    final Size size = const Size(128, 88);
    final List<FzRect> priority = templateRects('t_priority', size, 3, 0, false);
    final List<FzRect> columns = templateRects('t_columns', size, 3, 0, false);
    expect(priority, isNot(columns),
        reason: 'three equal columns is what the two used to have in common');
    expect(templateRects('t_grid', size, 3, 0, false), isNot(priority));
  });
}
