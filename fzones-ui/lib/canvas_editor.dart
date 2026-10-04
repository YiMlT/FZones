import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'design.dart';
import 'editor_shell.dart';
import 'layout_store.dart';
import 'strings.dart';
import 'widgets.dart';

/// Which sides of a zone the grab is on. Empty means "the middle", ie a move.
enum FzEdge { left, right, top, bottom }

const int kCanvasSnap = 32;
const int kCanvasMinSide = 64;
const double kCanvasHandleHit = 7;

/// The native canvas rules, as a pure function so they can be tested without a window:
/// snap every edge to 32 reference px, never go below 64, never leave the reference area.
FzRect fzDragZone({
  required FzRect original,
  required double dx,
  required double dy,
  required Set<FzEdge> edges,
  required int refW,
  required int refH,
}) {
  int snap(double v) => (v / kCanvasSnap).round() * kCanvasSnap;
  int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  final int minW = math.min(kCanvasMinSide, refW ~/ 2);
  final int minH = math.min(kCanvasMinSide, refH ~/ 2);

  int l = original.left;
  int t = original.top;
  int r = original.right;
  int b = original.bottom;

  if (edges.isEmpty) {
    l = clampInt(snap(original.left + dx), 0, math.max(0, refW - original.width));
    t = clampInt(snap(original.top + dy), 0, math.max(0, refH - original.height));
    r = l + original.width;
    b = t + original.height;
  } else {
    if (edges.contains(FzEdge.left)) {
      l = clampInt(snap(l + dx), 0, r - minW);
    }
    if (edges.contains(FzEdge.right)) {
      r = clampInt(snap(r + dx), l + minW, refW);
    }
    if (edges.contains(FzEdge.top)) {
      t = clampInt(snap(t + dy), 0, b - minH);
    }
    if (edges.contains(FzEdge.bottom)) {
      b = clampInt(snap(b + dy), t + minH, refH);
    }
  }
  return FzRect(l, t, r, b);
}

/// The same drag, but a border other zones sit on moves them with it, the way a splitter between
/// two panes does. Without it, widening the tall zone on the left of a "one left, two right"
/// layout opens a gap on one side and an overlap on the other, and every adjustment has to be
/// finished by hand.
///
/// Only an exact contact counts as sitting on the border: the canvas snaps every edge to
/// [kCanvasSnap], so an edge a pixel away is a coincidence rather than a seam. The wanted movement
/// is then reduced until no zone on either side falls below [kCanvasMinSide] or leaves the
/// reference area, which is what makes the drag stop instead of turning a zone inside out.
List<FzRect> fzDragZoneLinked({
  required List<FzRect> zones,
  required int index,
  required Set<FzEdge> edges,
  required double dx,
  required double dy,
  required int refW,
  required int refH,
}) {
  if (index < 0 || index >= zones.length) return List<FzRect>.of(zones);
  final FzRect self = zones[index];
  final FzRect moved = fzDragZone(
    original: self,
    dx: dx,
    dy: dy,
    edges: edges,
    refW: refW,
    refH: refH,
  );
  if (edges.isEmpty) {
    // A move, not a resize: nothing may be dragged into another zone.
    return <FzRect>[
      for (int i = 0; i < zones.length; i++) i == index ? moved : zones[i],
    ];
  }
  List<FzRect> out = List<FzRect>.of(zones);
  if (edges.contains(FzEdge.left)) {
    out = _shiftBorder(out, self, true, self.left, moved.left - self.left, refW);
  }
  if (edges.contains(FzEdge.right)) {
    out = _shiftBorder(out, self, true, self.right, moved.right - self.right, refW);
  }
  if (edges.contains(FzEdge.top)) {
    out = _shiftBorder(out, self, false, self.top, moved.top - self.top, refH);
  }
  if (edges.contains(FzEdge.bottom)) {
    out = _shiftBorder(out, self, false, self.bottom, moved.bottom - self.bottom, refH);
  }
  return out;
}

/// Moves the border at [at] along one axis by [want], taking every zone edge that sits exactly on
/// it, and stops early at the tightest one. [dragged] selects which edges count: a border is a
/// seam between two zones, not a coincidence of coordinates somewhere else on the canvas.
List<FzRect> _shiftBorder(
  List<FzRect> zones,
  FzRect dragged,
  bool xAxis,
  int at,
  int want,
  int refSize,
) {
  if (want == 0) return zones;
  final int minSide = math.min(kCanvasMinSide, refSize ~/ 2);
  int lo = -refSize, hi = refSize;
  final List<int> hits = <int>[];
  for (int i = 0; i < zones.length; i++) {
    final FzRect z = zones[i];
    if (!_sharesRun(z, dragged, xAxis)) continue;
    final int start = xAxis ? z.left : z.top;
    final int end = xAxis ? z.right : z.bottom;
    final bool starts = start == at, ends = end == at;
    if (!starts && !ends) continue;
    hits.add(i);
    // The zone to the far side of the border loses width as it moves; the zone on the near side
    // gains it, and both stop at the minimum side or the edge of the area.
    if (starts) {
      hi = math.min(hi, end - minSide - at);
      lo = math.max(lo, -at);
    }
    if (ends) {
      lo = math.max(lo, start + minSide - at);
      hi = math.min(hi, refSize - at);
    }
  }
  final int d = want < lo ? lo : (want > hi ? hi : want);
  if (d == 0) return zones;
  return <FzRect>[
    for (int i = 0; i < zones.length; i++)
      hits.contains(i) ? _nudge(zones[i], xAxis, at, d) : zones[i],
  ];
}

/// Double-clicking a seam hands each side the same share of the space those two sides occupy - the
/// way a splitter's double-click resets its panes, and the only tidy way back to an even split once
/// a drag has made one lopsided. The same minimum-side and reference-area limits apply, so a seam
/// that cannot reach the middle stops as short as it must.
List<FzRect> fzEqualiseBorder({
  required List<FzRect> zones,
  required int index,
  required FzEdge edge,
  required int refW,
  required int refH,
}) {
  if (index < 0 || index >= zones.length) return List<FzRect>.of(zones);
  final FzRect self = zones[index];
  final bool xAxis = edge == FzEdge.left || edge == FzEdge.right;
  final int at = switch (edge) {
    FzEdge.left => self.left,
    FzEdge.right => self.right,
    FzEdge.top => self.top,
    FzEdge.bottom => self.bottom,
  };
  int snapRound(double v) => (v / kCanvasSnap).round() * kCanvasSnap;

  // The seam is wider than the zone under the pointer: grab either of the two stacked zones on the
  // right of "one left, two right" and the seam still runs the full height, so the band is worked
  // out first and then everything sitting on it is taken along.
  int seamStart = xAxis ? self.top : self.left;
  int seamEnd = xAxis ? self.bottom : self.right;
  for (final FzRect z in zones) {
    if (!_sharesRun(z, self, xAxis)) continue;
    final int zStart = xAxis ? z.top : z.left;
    final int zEnd = xAxis ? z.bottom : z.right;
    if ((xAxis ? z.right : z.bottom) == at || (xAxis ? z.left : z.top) == at) {
      seamStart = math.min(seamStart, zStart);
      seamEnd = math.max(seamEnd, zEnd);
    }
  }
  final FzRect band = xAxis ? FzRect(0, seamStart, refW, seamEnd) : FzRect(seamStart, 0, refH, seamEnd);

  int start = at;
  int end = at;
  for (final FzRect z in zones) {
    if (!_sharesRun(z, band, xAxis)) continue;
    final int zStart = xAxis ? z.left : z.top;
    final int zEnd = xAxis ? z.right : z.bottom;
    // The near side of the seam ends here; the far side starts here. Either can hold several
    // zones, and the group is as wide as its outermost member.
    if (zEnd == at) start = math.min(start, zStart);
    if (zStart == at) end = math.max(end, zEnd);
  }
  if (end <= start) return List<FzRect>.of(zones);

  final int target = start + snapRound((end - start) / 2);
  return _shiftBorder(zones, band, xAxis, at, target - at, xAxis ? refW : refH);
}

FzRect _nudge(FzRect z, bool xAxis, int at, int d) => xAxis
    ? FzRect(
        z.left == at ? z.left + d : z.left,
        z.top,
        z.right == at ? z.right + d : z.right,
        z.bottom,
      )
    : FzRect(
        z.left,
        z.top == at ? z.top + d : z.top,
        z.right,
        z.bottom == at ? z.bottom + d : z.bottom,
      );

/// Whether the two zones share a run of the axis at right angles to the border.
bool _sharesRun(FzRect a, FzRect b, bool xAxis) {
  final int a0 = xAxis ? a.top : a.left;
  final int a1 = xAxis ? a.bottom : a.right;
  final int b0 = xAxis ? b.top : b.left;
  final int b1 = xAxis ? b.bottom : b.right;
  return math.max(a0, b0) < math.min(a1, b1);
}

Set<FzEdge> fzEdgesAt(Rect screenRect, Offset point) {
  final Set<FzEdge> edges = <FzEdge>{};
  if ((point.dx - screenRect.left).abs() <= kCanvasHandleHit) edges.add(FzEdge.left);
  if ((point.dx - screenRect.right).abs() <= kCanvasHandleHit) edges.add(FzEdge.right);
  if ((point.dy - screenRect.top).abs() <= kCanvasHandleHit) edges.add(FzEdge.top);
  if ((point.dy - screenRect.bottom).abs() <= kCanvasHandleHit) edges.add(FzEdge.bottom);
  return edges;
}

MouseCursor fzCursorFor(Set<FzEdge> e) {
  final bool l = e.contains(FzEdge.left), r = e.contains(FzEdge.right);
  final bool t = e.contains(FzEdge.top), b = e.contains(FzEdge.bottom);
  if ((l && t) || (r && b)) return SystemMouseCursors.resizeUpLeftDownRight;
  if ((r && t) || (l && b)) return SystemMouseCursors.resizeUpRightDownLeft;
  if (l || r) return SystemMouseCursors.resizeLeftRight;
  if (t || b) return SystemMouseCursors.resizeUpDown;
  return SystemMouseCursors.grab;
}

/// Adds a quarter-size zone, cascading until it lands somewhere nothing overlaps - the same
/// search the native 添加区域 does, so repeated adds never stack exactly.
FzRect fzNewCanvasZone(int refW, int refH, List<FzRect> existing) {
  int snapRound(num v) => (v / kCanvasSnap).round() * kCanvasSnap;
  final int w = math.max(kCanvasSnap, snapRound(refW / 4));
  final int h = math.max(kCanvasSnap, snapRound(refH / 4));

  FzRect at(int step) {
    final int x = (step * kCanvasSnap * 2) % math.max(1, refW - w);
    final int y = (step * kCanvasSnap * 2) % math.max(1, refH - h);
    return FzRect(x, y, x + w, y + h);
  }

  bool hits(FzRect z) => existing.any((FzRect o) =>
      z.left < o.right && o.left < z.right && z.top < o.bottom && o.top < z.bottom);

  FzRect placed = at(existing.length);
  for (int step = 0; step < 24; step++) {
    final FzRect candidate = at(step);
    if (!hits(candidate)) {
      placed = candidate;
      break;
    }
  }
  return placed;
}

class CanvasEditorPage extends StatefulWidget {
  const CanvasEditorPage({
    super.key,
    required this.lang,
    required this.initial,
    required this.onCancel,
    required this.onSave,
  });

  final FzLang lang;
  final FzCustomLayout initial;
  final VoidCallback onCancel;
  final ValueChanged<FzCustomLayout> onSave;

  @override
  State<CanvasEditorPage> createState() => _CanvasEditorPageState();
}

class _CanvasEditorPageState extends State<CanvasEditorPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial.name);
  late List<FzRect> _zones = List<FzRect>.from(widget.initial.canvasZones);
  int _selected = 0;

  int get _refW => widget.initial.referenceWidth;
  int get _refH => widget.initial.referenceHeight;

  FzRect? _dragOrigin;

  /// The whole set as it was when the grab began. A linked resize recomputes every frame from the
  /// total delta, so the neighbours must be read from that snapshot - moving them again from where
  /// the last frame left them would double the shift on every step of the pointer.
  List<FzRect>? _dragSnapshot;
  Set<FzEdge> _dragEdges = <FzEdge>{};
  Offset _dragFrom = Offset.zero;
  double _scale = 1;
  Set<FzEdge> _hoverEdges = <FzEdge>{};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final FzLang lang = widget.lang;
    String t(String k) => fzT(k, lang);

    return FzEditorShell(
      colors: c,
      bar: <Widget>[
        FzFieldLabel(colors: c, text: t('layout_name')),
        FzTextField(colors: c, controller: _name, hint: 'Custom', width: 208),
        const Spacer(),
        FzButton(label: t('cancel'), width: 90, onTap: widget.onCancel),
        const SizedBox(width: 12),
        FzButton(
          label: t('save_layout'),
          width: 120,
          primary: true,
          onTap: () => widget.onSave(FzCustomLayout(
            uuid: widget.initial.uuid,
            name: _name.text.trim().isEmpty ? 'Custom' : _name.text.trim(),
            isCanvas: true,
            referenceWidth: _refW,
            referenceHeight: _refH,
            canvasZones: List<FzRect>.from(_zones),
            sensitivityRadius: widget.initial.sensitivityRadius,
          )),
        ),
      ],
      body: <Widget>[
        SizedBox(
          height: 300,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Aspect fit with a 6px inset so a handle on the edge is still inside the box.
              final double bw = constraints.maxWidth - 12;
              final double bh = constraints.maxHeight - 12;
              double w = bw;
              double h = w * _refH / _refW;
              if (h > bh) {
                h = bh;
                w = h * _refW / _refH;
              }
              _scale = w / _refW;
              final Rect monitor = Rect.fromLTWH(
                  (constraints.maxWidth - w) / 2,
                  (constraints.maxHeight - h) / 2,
                  w,
                  h);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails d) {
                  final int hit = _zoneAt(d.localPosition, monitor);
                  if (hit < 0) return;
                  setState(() {
                    _selected = hit;
                    _dragOrigin = _zones[hit];
                    _dragSnapshot = List<FzRect>.from(_zones);
                    _dragEdges = fzEdgesAt(_screenRect(_zones[hit], monitor), d.localPosition);
                    _dragFrom = d.localPosition;
                  });
                },
                onPanUpdate: (DragUpdateDetails d) {
                  final List<FzRect>? snap = _dragSnapshot;
                  if (snap == null) return;
                  final Offset delta = d.localPosition - _dragFrom;
                  setState(() {
                    _zones = fzDragZoneLinked(
                      zones: snap,
                      index: _selected,
                      edges: _dragEdges,
                      dx: delta.dx / _scale,
                      dy: delta.dy / _scale,
                      refW: _refW,
                      refH: _refH,
                    );
                  });
                },
                onPanEnd: (_) => setState(() {
                  _dragOrigin = null;
                  _dragSnapshot = null;
                }),
                onPanCancel: () => setState(() {
                  _dragOrigin = null;
                  _dragSnapshot = null;
                }),
                onTapUp: (TapUpDetails d) {
                  final int hit = _zoneAt(d.localPosition, monitor);
                  if (hit >= 0) setState(() => _selected = hit);
                },
                // A double-click on a seam evens out the two sides of it. Only an edge counts:
                // double-clicking the middle of a zone is a selection, not a reset.
                onDoubleTapDown: (TapDownDetails d) {
                  final int hit = _zoneAt(d.localPosition, monitor);
                  if (hit < 0) return;
                  final Set<FzEdge> edges = fzEdgesAt(
                    _screenRect(_zones[hit], monitor),
                    d.localPosition,
                  );
                  final FzEdge? seam = edges.contains(FzEdge.left)
                      ? FzEdge.left
                      : edges.contains(FzEdge.right)
                      ? FzEdge.right
                      : edges.contains(FzEdge.top)
                      ? FzEdge.top
                      : edges.contains(FzEdge.bottom)
                      ? FzEdge.bottom
                      : null;
                  if (seam == null) return;
                  setState(() {
                    _zones = fzEqualiseBorder(
                      zones: _zones,
                      index: hit,
                      edge: seam,
                      refW: _refW,
                      refH: _refH,
                    );
                  });
                },
                child: MouseRegion(
                  cursor: fzCursorFor(_hoverEdges),
                  onHover: (PointerHoverEvent e) {
                    final int hit = _zoneAt(e.localPosition, monitor);
                    setState(() => _hoverEdges = hit < 0
                        ? <FzEdge>{}
                        : fzEdgesAt(_screenRect(_zones[hit], monitor), e.localPosition));
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.field,
                      borderRadius: BorderRadius.circular(FzRadius.base),
                    ),
                    child: Stack(
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: monitor,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(FzRadius.small),
                              border: Border.all(color: c.fieldBorder),
                            ),
                          ),
                        ),
                        ..._zones.asMap().entries.map((MapEntry<int, FzRect> e) {
                          final bool selected = e.key == _selected;
                          // During a drag the whole set is recomputed from the grab's snapshot on
                          // every pointer step, so easing would put the borders a frame behind the
                          // mouse - including the neighbours a linked resize moves with it.
                          // Everything else - add, delete, a snap landing - eases on the page
                          // duration, like the native preview's 200ms morph.
                          final bool dragging = _dragOrigin != null;
                          return AnimatedPositioned.fromRect(
                            duration:
                                dragging ? Duration.zero : FzMotion.page,
                            curve: Curves.easeOutCubic,
                            rect: _screenRect(e.value, monitor),
                            child: AnimatedContainer(
                              duration: FzMotion.select,
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                color: selected
                                    ? c.accent
                                    : c.fieldBorder.withValues(alpha: 0.55),
                                borderRadius:
                                    BorderRadius.circular(FzRadius.small),
                              ),
                              child: Stack(
                                children: <Widget>[
                                  Center(
                                    child: Text(
                                      '${e.key + 1}',
                                      style: TextStyle(
                                          color: selected ? c.accentInk : c.ink2,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  // Four corner grips, same as the native selected zone.
                                  if (selected)
                                    ...<Widget>[
                                      _grip(c, Alignment.topLeft),
                                      _grip(c, Alignment.topRight),
                                      _grip(c, Alignment.bottomLeft),
                                      _grip(c, Alignment.bottomRight),
                                    ],
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            FzButton(
              label: t('add_zone'),
              width: 120,
              onTap: () => setState(() {
                _zones.add(fzNewCanvasZone(_refW, _refH, _zones));
                _selected = _zones.length - 1;
              }),
            ),
            const SizedBox(width: 8),
            FzButton(
              label: t('delete_zone'),
              width: 120,
              enabled: _selected >= 0 && _zones.length > 1,
              onTap: () => setState(() {
                if (_selected < 0 || _zones.length <= 1) return;
                _zones.removeAt(_selected);
                _selected = math.min(_selected, _zones.length - 1);
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(t('canvas_hint'), style: TextStyle(color: c.ink2, fontSize: 11)),
      ],
    );
  }

  Widget _grip(FzColors c, Alignment at) => Align(
        alignment: at,
        child: FractionalTranslation(
          translation: Offset(at.x * 0.5, at.y * 0.5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: c.accentInk,
              border: Border.all(color: c.accent),
              borderRadius: BorderRadius.circular(FzRadius.grip),
            ),
          ),
        ),
      );

  Rect _screenRect(FzRect r, Rect monitor) => Rect.fromLTWH(
        monitor.left + r.left * _scale,
        monitor.top + r.top * _scale,
        r.width * _scale,
        r.height * _scale,
      );

  /// Topmost zone wins, and only inside the monitor rect.
  int _zoneAt(Offset point, Rect monitor) {
    if (!monitor.contains(point)) return -1;
    for (int i = _zones.length - 1; i >= 0; i--) {
      if (_screenRect(_zones[i], monitor).contains(point)) return i;
    }
    return -1;
  }
}
