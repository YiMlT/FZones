import 'dart:collection';
import 'dart:math' as math;

import 'layout_store.dart';

/// Mirrors the GridModel inside FZones/LayoutEditor.cpp, including its rounding:
/// band boundaries come from MulDiv (round to nearest) and the last band always ends exactly
/// at the area edge, so the rectangles tile the preview without a seam.
class FzSpan {
  const FzSpan(this.r1, this.c1, this.r2, this.c2, {this.found = true});
  final int r1;
  final int c1;
  final int r2;
  final int c2;
  final bool found;

  static const FzSpan none = FzSpan(0, 0, 0, 0, found: false);

  bool sameAs(FzSpan o) => r1 == o.r1 && c1 == o.c1 && r2 == o.r2 && c2 == o.c2;
}

class FzGridModel {
  FzGridModel({
    required this.rows,
    required this.columns,
    required this.rowsPercentage,
    required this.columnsPercentage,
    required this.cellChildMap,
  });

  int rows;
  int columns;
  List<int> rowsPercentage;
  List<int> columnsPercentage;
  List<List<int>> cellChildMap;

  static const int percentMultiplier = 10000;

  /// Same as the engine's even split: every band gets the same share and the last one absorbs
  /// the remainder, so the percentages always add up to exactly 10000.
  static List<int> evenSplit(int count) {
    final int each = percentMultiplier ~/ count;
    // growable: splitLeftRight inserts a band, and List.filled returns a fixed-length list.
    final List<int> values = List<int>.filled(count, each, growable: true);
    values[count - 1] = percentMultiplier - each * (count - 1);
    return values;
  }

  factory FzGridModel.uniform(int rows, int columns) => FzGridModel(
        rows: rows,
        columns: columns,
        rowsPercentage: evenSplit(rows),
        columnsPercentage: evenSplit(columns),
        cellChildMap: List<List<int>>.generate(
            rows, (int r) => List<int>.generate(columns, (int c) => r * columns + c)),
      );

  static FzGridModel? fromCustom(FzCustomLayout layout) {
    if (layout.isCanvas ||
        layout.rows <= 0 ||
        layout.columns <= 0 ||
        layout.rowsPercentage.length != layout.rows ||
        layout.columnsPercentage.length != layout.columns ||
        layout.cellChildMap.length != layout.rows) {
      return null;
    }
    for (final List<int> row in layout.cellChildMap) {
      if (row.length != layout.columns) return null;
    }
    return FzGridModel(
      rows: layout.rows,
      columns: layout.columns,
      rowsPercentage: List<int>.from(layout.rowsPercentage),
      columnsPercentage: List<int>.from(layout.columnsPercentage),
      cellChildMap: layout.cellChildMap.map(List<int>.from).toList(),
    );
  }

  int maxZone() {
    int highest = -1;
    for (final List<int> row in cellChildMap) {
      for (final int id in row) {
        highest = math.max(highest, id);
      }
    }
    return highest;
  }

  int get zoneCount => maxZone() + 1;

  FzSpan spanOf(int zone) {
    int r1 = rows, c1 = columns, r2 = -1, c2 = -1;
    bool found = false;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < columns; c++) {
        if (cellChildMap[r][c] == zone) {
          r1 = math.min(r1, r);
          c1 = math.min(c1, c);
          r2 = math.max(r2, r);
          c2 = math.max(c2, c);
          found = true;
        }
      }
    }
    return found ? FzSpan(r1, c1, r2, c2) : FzSpan.none;
  }

  void renumber() {
    final List<int> mapping = List<int>.filled(maxZone() + 1, -1);
    int next = 0;
    for (int r = 0; r < cellChildMap.length; r++) {
      for (int c = 0; c < cellChildMap[r].length; c++) {
        final int id = cellChildMap[r][c];
        if (mapping[id] < 0) mapping[id] = next++;
        cellChildMap[r][c] = mapping[id];
      }
    }
  }

  int _zoneWithSpan(FzSpan want) {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < columns; c++) {
        if (spanOf(cellChildMap[r][c]).sameAs(want)) return cellChildMap[r][c];
      }
    }
    return -1;
  }

  /// A zone wider than one band hands its leftmost band to a fresh id; a one-band zone gets a
  /// new band first, which is what keeps the grid refinable instead of stalling.
  int splitLeftRight(int zone) {
    final FzSpan span = spanOf(zone);
    if (!span.found) return -1;

    final int fresh = maxZone() + 1;
    if (span.c2 > span.c1) {
      for (int r = span.r1; r <= span.r2; r++) {
        cellChildMap[r][span.c1] = fresh;
      }
      renumber();
      return _zoneWithSpan(FzSpan(span.r1, span.c1, span.r2, span.c1));
    }

    final int each = columnsPercentage[span.c1] ~/ 2;
    columnsPercentage[span.c1] -= each;
    columnsPercentage.insert(span.c1 + 1, each);
    for (final List<int> row in cellChildMap) {
      row.insert(span.c1 + 1, row[span.c1]);
    }
    for (int r = span.r1; r <= span.r2; r++) {
      cellChildMap[r][span.c1 + 1] = fresh;
    }
    columns++;
    renumber();
    return _zoneWithSpan(FzSpan(span.r1, span.c1 + 1, span.r2, span.c1 + 1));
  }

  int splitTopBottom(int zone) {
    final FzSpan span = spanOf(zone);
    if (!span.found) return -1;

    final int fresh = maxZone() + 1;
    if (span.r2 > span.r1) {
      for (int c = span.c1; c <= span.c2; c++) {
        cellChildMap[span.r1][c] = fresh;
      }
      renumber();
      return _zoneWithSpan(FzSpan(span.r1, span.c1, span.r1, span.c2));
    }

    final int each = rowsPercentage[span.r1] ~/ 2;
    rowsPercentage[span.r1] -= each;
    rowsPercentage.insert(span.r1 + 1, each);
    cellChildMap.insert(span.r1 + 1, List<int>.from(cellChildMap[span.r1]));
    for (int c = span.c1; c <= span.c2; c++) {
      cellChildMap[span.r1][c] = fresh;
    }
    rows++;
    renumber();
    return _zoneWithSpan(FzSpan(span.r1, span.c1, span.r1, span.c2));
  }

  static const int mergeLeft = 0;
  static const int mergeUp = 1;
  static const int mergeRight = 2;
  static const int mergeDown = 3;

  /// The union is only legal when it contains nothing but the two zones being joined.
  FzSpan? canMerge(int zone, int direction) {
    final FzSpan s = spanOf(zone);
    if (!s.found) return null;

    int r = s.r1;
    int c = s.c1;
    if (direction == mergeLeft) c = s.c1 - 1;
    if (direction == mergeUp) r = s.r1 - 1;
    if (direction == mergeRight) c = s.c2 + 1;
    if (direction == mergeDown) r = s.r2 + 1;
    if (r < 0 || c < 0 || r >= rows || c >= columns) return null;

    final int other = cellChildMap[r][c];
    if (other == zone) return null;
    final FzSpan o = spanOf(other);
    if (!o.found) return null;

    final FzSpan union = FzSpan(
      math.min(s.r1, o.r1),
      math.min(s.c1, o.c1),
      math.max(s.r2, o.r2),
      math.max(s.c2, o.c2),
    );
    for (int rr = union.r1; rr <= union.r2; rr++) {
      for (int cc = union.c1; cc <= union.c2; cc++) {
        final int id = cellChildMap[rr][cc];
        if (id != zone && id != other) return null;
      }
    }
    return union;
  }

  int merge(int zone, int direction) {
    final FzSpan? union = canMerge(zone, direction);
    if (union == null) return -1;
    for (int r = union.r1; r <= union.r2; r++) {
      for (int c = union.c1; c <= union.c2; c++) {
        cellChildMap[r][c] = zone;
      }
    }
    renumber();
    return _zoneWithSpan(union);
  }

  static List<FzRect> _boundaries(int origin, int extent, List<int> percentages) {
    final List<FzRect> bands = <FzRect>[];
    int accumulated = 0;
    for (int i = 0; i < percentages.length; i++) {
      accumulated += percentages[i];
      final int start =
          origin + (((extent * (accumulated - percentages[i])) / percentMultiplier).round());
      final int end = i + 1 == percentages.length
          ? origin + extent
          : origin + (((extent * accumulated) / percentMultiplier).round());
      bands.add(FzRect(start, 0, end, 0));
    }
    return bands;
  }

  /// Zone id -> rect, in id order. The editor needs the ids: the preview numbers a zone
  /// `id + 1`, and the split/merge calls take a zone id, not a position.
  SplayTreeMap<int, FzRect> zoneRectsById(FzRect area) {
    final List<FzRect> columnBands =
        _boundaries(area.left, area.width, columnsPercentage);
    final List<FzRect> rowBands = _boundaries(area.top, area.height, rowsPercentage);

    final SplayTreeMap<int, FzRect> merged = SplayTreeMap<int, FzRect>();
    for (int r = 0; r < rows && r < rowBands.length; r++) {
      for (int c = 0; c < columns && c < columnBands.length; c++) {
        final FzRect cell = FzRect(columnBands[c].left, rowBands[r].left,
            columnBands[c].right, rowBands[r].right);
        final int id = cellChildMap[r][c];
        final FzRect? existing = merged[id];
        if (existing == null) {
          merged[id] = cell;
        } else {
          merged[id] = FzRect(
            math.min(existing.left, cell.left),
            math.min(existing.top, cell.top),
            math.max(existing.right, cell.right),
            math.max(existing.bottom, cell.bottom),
          );
        }
      }
    }
    return merged;
  }

  /// Ordered by zone id, which is what the preview numbers (1-based) follow.
  List<FzRect> zoneRects(FzRect area) => zoneRectsById(area).values.toList();

  /// [uuid] keeps the identity of the layout being edited; omit it for a brand new one and a
  /// fresh uuid is generated.
  FzCustomLayout toCustom(String name, {String? uuid}) => FzCustomLayout(
        uuid: uuid,
        name: name,
        isCanvas: false,
        rows: rows,
        columns: columns,
        rowsPercentage: List<int>.from(rowsPercentage),
        columnsPercentage: List<int>.from(columnsPercentage),
        cellChildMap: cellChildMap.map(List<int>.from).toList(),
      );
}
