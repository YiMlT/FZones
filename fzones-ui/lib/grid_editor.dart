import 'dart:collection';

import 'package:flutter/material.dart';

import 'design.dart';
import 'editor_shell.dart';
import 'grid_model.dart';
import 'layout_store.dart';
import 'strings.dart';
import 'widgets.dart';

/// The grid sub-editor: the same split/merge model as the C++ one, driven from a preview you
/// click zones in. Saving hands a custom layout back up; nothing is written from here.
class GridEditorPage extends StatefulWidget {
  const GridEditorPage({
    super.key,
    required this.lang,
    required this.initial,
    required this.isNew,
    required this.onCancel,
    required this.onSave,
  });

  final FzLang lang;
  final FzCustomLayout initial;
  final bool isNew;
  final VoidCallback onCancel;
  final ValueChanged<FzCustomLayout> onSave;

  @override
  State<GridEditorPage> createState() => _GridEditorPageState();
}

class _GridEditorPageState extends State<GridEditorPage> {
  late FzGridModel _grid;
  late final TextEditingController _name =
      TextEditingController(text: widget.initial.name);
  int _selected = 0;

  /// The layout's own gap, editable here because every saved layout carries it in its `info` -
  /// two grids of the same shape can sit 0 and 24 apart, and neither should move the other.
  late int _spacing = widget.initial.spacing;
  late bool _showSpacing = widget.initial.showSpacing;

  @override
  void initState() {
    super.initState();
    _grid = FzGridModel.fromCustom(widget.initial) ?? FzGridModel.uniform(2, 2);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _tool(void Function() act) => setState(act);

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final FzLang lang = widget.lang;
    String t(String k) => fzT(k, lang);

    return FzEditorShell(
      colors: c,
      bar: <Widget>[
        FzFieldLabel(colors: c, text: t('grid_rows')),
        FzNumberField(
          value: _grid.rows,
          width: 56,
          min: 1,
          max: 8,
          enabled: widget.isNew,
          onCommit: (int v) => _tool(() {
            _grid = FzGridModel.uniform(v.clamp(1, 8), _grid.columns);
            _selected = 0;
          }),
        ),
        const SizedBox(width: 12),
        FzFieldLabel(colors: c, text: t('grid_cols')),
        FzNumberField(
          value: _grid.columns,
          width: 56,
          min: 1,
          max: 8,
          enabled: widget.isNew,
          onCommit: (int v) => _tool(() {
            _grid = FzGridModel.uniform(_grid.rows, v.clamp(1, 8));
            _selected = 0;
          }),
        ),
        const SizedBox(width: 12),
        FzFieldLabel(colors: c, text: t('layout_name')),
        SizedBox(
          width: 208,
          child: FzTextField(colors: c, controller: _name, hint: 'Custom'),
        ),
        const Spacer(),
        FzButton(label: t('cancel'), width: 90, onTap: widget.onCancel),
        const SizedBox(width: 12),
        FzButton(
          label: t('save_layout'),
          width: 120,
          primary: true,
          onTap: () {
            final FzCustomLayout result = _grid.toCustom(
              _name.text.trim().isEmpty ? 'Custom' : _name.text.trim(),
              uuid: widget.initial.uuid,
            )
              ..spacing = _spacing
              ..showSpacing = _showSpacing;
            widget.onSave(result);
          },
        ),
      ],
      body: <Widget>[
        SizedBox(
          height: 300,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final FzRect area = FzRect(
                  2, 2, constraints.maxWidth.round() - 2, 298);
              final SplayTreeMap<int, FzRect> rects = _grid.zoneRectsById(area);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails d) {
                  // The innermost zone wins, so an overlapped preview still picks sensibly.
                  int hit = -1;
                  rects.forEach((int id, FzRect r) {
                    if (d.localPosition.dx >= r.left &&
                        d.localPosition.dx <= r.right &&
                        d.localPosition.dy >= r.top &&
                        d.localPosition.dy <= r.bottom) {
                      hit = id;
                    }
                  });
                  if (hit >= 0) setState(() => _selected = hit);
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.field,
                    borderRadius: BorderRadius.circular(FzRadius.base),
                  ),
                  child: Stack(
                    children: rects.entries.map((MapEntry<int, FzRect> e) {
                      final bool selected = e.key == _selected;
                      // A schematic gap, not the layout's own spacing scaled - the preview is a
                      // third of a monitor, where 16px would be invisible. It still answers to the
                      // switch, so the row below is not the only thing that moves.
                      final double gap = _showSpacing ? 8 : 2;
                      return AnimatedPositioned(
                        duration: FzMotion.page,
                        curve: Curves.easeOutCubic,
                        left: e.value.left + gap / 2,
                        top: e.value.top + gap / 2,
                        width: (e.value.width - gap).clamp(0, double.infinity).toDouble(),
                        height: (e.value.height - gap).clamp(0, double.infinity).toDouble(),
                        child: AnimatedContainer(
                          duration: FzMotion.select,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? c.accent : c.fieldBorder.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(FzRadius.small),
                          ),
                          child: Text(
                            '${e.key + 1}',
                            style: TextStyle(
                                color: selected ? c.accentInk : c.ink2,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            _toolButton(c, t('split_lr'), 120, () => _tool(() {
                  final int r = _grid.splitLeftRight(_selected);
                  if (r >= 0) _selected = r;
                })),
            const SizedBox(width: 8),
            _toolButton(c, t('split_tb'), 120, () => _tool(() {
                  final int r = _grid.splitTopBottom(_selected);
                  if (r >= 0) _selected = r;
                })),
            const SizedBox(width: 8),
            _mergeButton(c, t('merge_left'), FzGridModel.mergeLeft),
            _mergeButton(c, t('merge_up'), FzGridModel.mergeUp),
            _mergeButton(c, t('merge_right'), FzGridModel.mergeRight),
            _mergeButton(c, t('merge_down'), FzGridModel.mergeDown),
          ],
        ),
        const SizedBox(height: 12),
        // The gap this layout saves with. Its own row: the tool row above is already within a
        // whisker of the card's width at the window's default size.
        Row(
          children: <Widget>[
            Text(
              t('spacing'),
              style: TextStyle(color: c.ink2, fontSize: 12),
            ),
            const SizedBox(width: 8),
            FzNumberField(
              value: _spacing,
              width: 56,
              min: 0,
              max: 100,
              onChanged: (int v) => setState(() => _spacing = v.clamp(0, 100)),
            ),
            const SizedBox(width: 16),
            FzToggle(
              value: _showSpacing,
              onChanged: (bool v) => setState(() => _showSpacing = v),
            ),
            const SizedBox(width: 8),
            Text(
              t('show_spacing'),
              style: TextStyle(color: c.ink2, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(t('grid_hint'), style: TextStyle(color: c.ink2, fontSize: 11)),
      ],
    );
  }

  Widget _toolButton(FzColors c, String label, double width, VoidCallback onTap) =>
      FzButton(label: label, width: width, onTap: onTap);

  Widget _mergeButton(FzColors c, String label, int direction) {
    // A merge is only offered when the union really is those two zones, same rule as the engine.
    final bool allowed = _grid.canMerge(_selected, direction) != null;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FzButton(
        label: label,
        width: 100,
        enabled: allowed,
        onTap: () => _tool(() {
          final int r = _grid.merge(_selected, direction);
          if (r >= 0) _selected = r;
        }),
      ),
    );
  }
}
