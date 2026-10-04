import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/grid_model.dart';
import 'package:fzones_ui/layout_store.dart';
import 'package:fzones_ui/editor_page.dart';

void main() {
  test('a uniform grid tiles the area with no gap and no overlap', () {
    final FzGridModel grid = FzGridModel.uniform(2, 3);
    final List<FzRect> rects = grid.zoneRects(const FzRect(0, 0, 300, 200));
    expect(rects, hasLength(6));

    int covered = 0;
    for (final FzRect r in rects) {
      covered += r.width * r.height;
    }
    expect(covered, 300 * 200, reason: 'the zones tile the area exactly');
  });

  test('percentages always add up to exactly 10000, whatever the split', () {
    final FzGridModel grid = FzGridModel.uniform(3, 3);
    expect(grid.rowsPercentage.reduce((int a, int b) => a + b), 10000);
    grid.splitLeftRight(0);
    expect(grid.columnsPercentage.reduce((int a, int b) => a + b), 10000,
        reason: 'a split re-divides the band, it does not lose a unit');
    grid.splitTopBottom(0);
    expect(grid.rowsPercentage.reduce((int a, int b) => a + b), 10000);
  });

  test('splitting then merging a zone returns to the same shape', () {
    final FzGridModel grid = FzGridModel.uniform(1, 1);
    expect(grid.zoneCount, 1);

    final int left = grid.splitLeftRight(0);
    expect(grid.zoneCount, 2);
    expect(grid.columns, 2);
    expect(left, isNot(-1));

    final int merged = grid.merge(left, FzGridModel.mergeLeft);
    expect(merged, isNot(-1));
    expect(grid.zoneCount, 1);
    expect(grid.zoneRects(const FzRect(0, 0, 200, 100)), hasLength(1));
    // The band itself survives: the C++ MergeZone only rewrites cells and renumbers, so a
    // 2-column grid whose cells all hold one zone is 1 zone across 2 bands. Kept identical
    // here so the editor and the engine agree on what "one zone" means.
    expect(grid.columns, 2, reason: 'MergeZone does not remove the band');
  });

  test('the built-in grid shape matches LayoutConfigurator::Grid', () {
    // rows/columns as the C++ loop computes them: rows grows until rows*rows > count.
    const Map<int, List<int>> expected = <int, List<int>>{
      1: <int>[1, 1],
      2: <int>[1, 2],
      3: <int>[1, 3],
      4: <int>[2, 2],
      5: <int>[2, 3],
      6: <int>[2, 3],
      8: <int>[2, 4],
      9: <int>[3, 3],
    };

    expected.forEach((int count, List<int> shape) {
      final FzGridModel grid = gridShapeFor(count);
      expect(<int>[grid.rows, grid.columns], shape, reason: 'zoneCount=$count');
      expect(grid.rowsPercentage.reduce((int a, int b) => a + b), 10000);
      expect(grid.columnsPercentage.reduce((int a, int b) => a + b), 10000);
      expect(grid.zoneRects(const FzRect(0, 0, 400, 300)), hasLength(count));
    });
  });

  test('customLayoutRects scales a canvas layout to the tile', () {
    final FzCustomLayout layout = FzCustomLayout(
      isCanvas: true,
      referenceWidth: 1000,
      referenceHeight: 500,
      canvasZones: <FzRect>[const FzRect(0, 0, 500, 500)],
    );
    final List<FzRect> rects = customLayoutRects(layout, const Size(200, 100));
    expect(rects, hasLength(1));
    expect(rects.first.left, 0);
    expect(rects.first.right, 100, reason: 'half of the reference width');
    expect(rects.first.bottom, 100, reason: 'the full reference height');
  });

  test('the tile shapes stay inside their preview box', () {
    for (final String template in kTemplates) {
      final List<FzRect> rects =
          templateRects(template, const Size(106, 72), 4, 16, true);
      for (final FzRect r in rects) {
        expect(r.left, greaterThanOrEqualTo(0), reason: template);
        expect(r.top, greaterThanOrEqualTo(0), reason: template);
        expect(r.right, lessThanOrEqualTo(106), reason: template);
        expect(r.bottom, lessThanOrEqualTo(72), reason: template);
        expect(r.width, greaterThan(0), reason: template);
        expect(r.height, greaterThan(0), reason: template);
      }
    }
    expect(templateRects('t_blank', const Size(106, 72), 4, 16, true), isEmpty);
    expect(templateRects('t_focus', const Size(106, 72), 1, 16, true), hasLength(1));
    expect(templateRects('t_columns', const Size(106, 72), 5, 16, true), hasLength(5));
    expect(math.max(1, 1), 1);
  });
}
