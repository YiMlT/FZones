import 'dart:async';

import 'package:flutter/material.dart';

import 'app_bar.dart';
import 'canvas_editor.dart';
import 'design.dart';
import 'editor_shell.dart';
import 'grid_editor.dart';
import 'grid_model.dart';
import 'layout_store.dart';
import 'strings.dart';
import 'widgets.dart';

/// Stage 2a of the migration: the editor's browse page. It reads and writes the same six JSON
/// files the engine does (contract §6) - applying a layout, setting an orientation default and
/// binding a quick-switch digit are all real writes here. The grid and canvas sub-editors are
/// the next slice.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.lang, this.startPage = 'browse'});

  final FzLang lang;

  /// Review-only deep link (`--grid` / `--canvas`); the engine always passes just `--editor`.
  final String startPage;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

const List<String> kTemplates = <String>[
  't_blank',
  't_focus',
  't_columns',
  't_rows',
  't_grid',
  't_priority',
];

class _EditorPageState extends State<EditorPage> {
  FzEditorParameters _params = FzEditorParameters.empty;
  List<FzCustomLayout> _custom = <FzCustomLayout>[];
  Map<String, int> _hotkeys = <String, int>{};
  Map<String, FzLayout> _defaults = <String, FzLayout>{};

  int _monitor = 0;
  String _template = 't_grid';
  int _customSelected = -1;

  /// False only until the first load has had its say about what is selected.
  bool _selectionSettled = false;
  int _zoneCount = 3;

  /// Each template's own gap, keyed by the engine's type name, read from and written back to
  /// `layout-templates.json` - the file the native editor kept this in. One shared slider would
  /// make tuning 网格 to 8px move 优先级 with it, and those are different layouts.
  Map<String, FzLayout> _templates = <String, FzLayout>{};

  String _status = '';
  bool _error = false;

  /// Which page is showing. The sub-editors hand a finished layout back through _saveEdited;
  /// they never write to disk themselves.
  String _page = 'browse';
  FzCustomLayout? _editing;
  bool _editingIsNew = true;

  void _newGrid() {
    setState(() {
      _editing = FzGridModel.uniform(2, 2).toCustom('');
      _editingIsNew = true;
      _page = 'grid';
    });
  }

  void _newCanvas() {
    final FzMonitorInfo? monitor = _currentMonitor;
    if (monitor == null) return;
    // The canvas reference area is the monitor's work area, exactly like the native editor.
    final int w = monitor.workArea.width;
    final int h = monitor.workArea.height;
    setState(() {
      _editing = FzCustomLayout(
        name: '',
        isCanvas: true,
        referenceWidth: w,
        referenceHeight: h,
        canvasZones: <FzRect>[FzRect(0, 0, w, h)],
      );
      _editingIsNew = true;
      _page = 'canvas';
    });
  }

  /// Which sub-editor can hold the selected template's shape. Columns, rows, grid and priority are
  /// grid models, so they go to the grid editor carrying the zone count and spacing as set; focus
  /// lays zones over each other and blank has none, and neither is something a grid can say, so
  /// those two go to the canvas editor. Saving either one makes a new custom layout - the template
  /// belongs to the engine and stays as it is.
  FzCustomLayout? _templateAsLayout() {
    final FzMonitorInfo? monitor = _currentMonitor;
    if (monitor == null) return null;
    final int count = _zoneCount < 1 ? 1 : _zoneCount;
    final String name = fzT(_template, widget.lang);
    final FzGridModel? model = switch (_template) {
      't_columns' => FzGridModel.uniform(1, count),
      't_rows' => FzGridModel.uniform(count, 1),
      't_grid' => gridShapeFor(count),
      't_priority' => priorityGridShapeFor(count),
      _ => null,
    };
    if (model != null) {
      return model.toCustom(name)
        ..showSpacing = _showSpacingFor(_template)
        ..spacing = _spacingFor(_template);
    }
    final int w = monitor.workArea.width;
    final int h = monitor.workArea.height;
    final List<FzRect> zones = templateRects(
      _template,
      Size(w.toDouble(), h.toDouble()),
      count,
      _spacingFor(_template),
      _showSpacingFor(_template),
    );
    return FzCustomLayout(
      name: name,
      isCanvas: true,
      referenceWidth: w,
      referenceHeight: h,
      // A blank layout has no zones; the canvas needs one to start from, same as 新建画布.
      canvasZones: zones.isEmpty ? <FzRect>[FzRect(0, 0, w, h)] : zones,
    );
  }

  void _editSelected() {
    if (_customSelected >= 0 && _customSelected < _custom.length) {
      final FzCustomLayout layout = _custom[_customSelected];
      setState(() {
        _editing = layout;
        _editingIsNew = false;
        _page = layout.isCanvas ? 'canvas' : 'grid';
      });
      return;
    }
    // A fixed template opens its own page. The shape belongs to the engine, so what is on offer is
    // the two numbers that shape it - not splitting, merging or dragging, which need a layout of
    // your own.
    setState(() => _page = 'template');
  }

  /// From the template page: carry the tuned shape into the real sub-editor as a new custom layout,
  /// which is where the zones can be pulled apart. A grid can say columns, rows, grid and priority;
  /// focus lays zones over each other and blank has none, so those two go to the canvas editor.
  void _saveTemplateAsCustom() {
    final FzCustomLayout? seeded = _templateAsLayout();
    if (seeded == null) return;
    setState(() {
      _editing = seeded;
      _editingIsNew = true;
      _page = seeded.isCanvas ? 'canvas' : 'grid';
    });
  }

  /// Deleting is the one write on this page nothing else can take back, so it asks first. It also
  /// takes the layout's quick-switch digit with it: a bound digit pointing at a layout that no
  /// longer exists is a key that does nothing.
  Future<void> _deleteCustom(int index) async {
    if (index < 0 || index >= _custom.length) {
      return;
    }
    final FzCustomLayout layout = _custom[index];
    final String name = layout.name.isEmpty ? layout.uuid : layout.name;
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => _ConfirmDelete(
        title: fzT('delete_layout', widget.lang),
        name: name,
        cancelLabel: fzT('cancel', widget.lang),
        okLabel: fzT('ok', widget.lang),
      ),
    );
    if (yes != true || !mounted) {
      return;
    }
    try {
      final List<FzCustomLayout> rest = List<FzCustomLayout>.from(
        _custom,
      )..removeAt(index);
      FzStore.writeCustomLayouts(rest);
      if (_hotkeys.containsKey(layout.uuid)) {
        final Map<String, int> keys = Map<String, int>.from(
          _hotkeys,
        )..remove(layout.uuid);
        FzStore.writeLayoutHotkeys(keys);
      }
      _showStatus('${fzT('deleted', widget.lang)}$name', false);
      setState(() {
        _selectionSettled = true;
        _customSelected = rest.isEmpty ? -1 : index.clamp(0, rest.length - 1);
      });
      _reload();
    } catch (e) {
      _showStatus('write failed: $e', true);
    }
  }

  /// Replaces by uuid when it already exists, appends otherwise, then rewrites the whole file
  /// through FzStore so the field names and the atomic replace stay in one place.
  void _saveEdited(FzCustomLayout result) {
    try {
      final List<FzCustomLayout> next = List<FzCustomLayout>.from(_custom);
      final int at = next.indexWhere(
        (FzCustomLayout l) => l.uuid == result.uuid,
      );
      if (at >= 0) {
        next[at] = result;
      } else {
        next.add(result);
      }
      FzStore.writeCustomLayouts(next);
      setState(() {
        _page = 'browse';
        _editing = null;
        _customSelected = at >= 0 ? at : next.length - 1;
      });
      _showStatus('${fzT('applied', widget.lang)}${result.name}', false);
      _reload();
    } catch (e) {
      _showStatus('write failed: $e', true);
    }
  }

  void _cancelEdited() => setState(() {
    _page = 'browse';
    _editing = null;
  });

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.startPage == 'grid') {
      _newGrid();
    } else if (widget.startPage == 'canvas') {
      _newCanvas();
    } else if (widget.startPage == 'template') {
      _page = 'template';
    }
  }

  void _reload() {
    final FzEditorParameters params = FzStore.readEditorParameters();
    setState(() {
      _params = params;
      _custom = FzStore.readCustomLayouts();
      _hotkeys = FzStore.readLayoutHotkeys();
      _defaults = FzStore.readDefaultLayouts();
      _templates = <String, FzLayout>{
        for (final FzLayout l in FzStore.readTemplates())
          kLayoutTypeNames[l.type]!: l,
      };
      if (_monitor >= params.monitors.length) {
        _monitor = params.monitors.isEmpty ? 0 : 0;
      }
      // Picking a template deliberately clears the custom selection, so only the first load may
      // read -1 as "nothing chosen yet". Without this the reload that follows 应用 would jump the
      // highlight off the template the user just applied and onto the first custom layout.
      if (!_selectionSettled) {
        _selectionSettled = true;
        if (_customSelected < 0 || _customSelected >= _custom.length) {
          _customSelected = _custom.isEmpty ? -1 : 0;
        }
      } else if (_customSelected >= _custom.length) {
        // The list shrank under us - a layout was deleted elsewhere.
        _customSelected = _custom.isEmpty ? -1 : _custom.length - 1;
      }
    });
  }

  FzMonitorInfo? get _currentMonitor =>
      _monitor >= 0 && _monitor < _params.monitors.length
      ? _params.monitors[_monitor]
      : null;

  /// The layout the current selection would apply.
  FzLayout _currentLayout() {
    final FzLayout layout = FzLayout(
      type: _templateType(),
      showSpacing: _showSpacingFor(_template),
      spacing: _spacingFor(_template),
      zoneCount: _zoneCount,
    );
    if (_customSelected >= 0 && _customSelected < _custom.length) {
      final FzCustomLayout chosen = _custom[_customSelected];
      layout.type = FzLayoutType.custom;
      layout.uuid = chosen.uuid;
      layout.zoneCount = chosen.zoneCount;
      // A saved layout carries its own gap in its info, and that is the one the engine draws -
      // not whatever the last template happened to be tuned to.
      layout.showSpacing = chosen.showSpacing;
      layout.spacing = chosen.spacing;
    }
    return layout;
  }

  FzLayoutType _templateType() => _templateTypeFor(_template);

  static FzLayoutType _templateTypeFor(String tileId) {
    switch (tileId) {
      case 't_blank':
        return FzLayoutType.blank;
      case 't_focus':
        return FzLayoutType.focus;
      case 't_columns':
        return FzLayoutType.columns;
      case 't_rows':
        return FzLayoutType.rows;
      case 't_grid':
        return FzLayoutType.grid;
      default:
        return FzLayoutType.priorityGrid;
    }
  }

  /// The key `layout-templates.json` stores a template's tuning under.
  static String _templateKey(String tileId) =>
      kLayoutTypeNames[_templateTypeFor(tileId)]!;

  static const int _defaultSpacing = 16;

  int _spacingFor(String tileId) =>
      _templates[_templateKey(tileId)]?.spacing ?? _defaultSpacing;

  bool _showSpacingFor(String tileId) =>
      _templates[_templateKey(tileId)]?.showSpacing ?? true;

  /// Store and persist one template's gap. The engine watches this file too, but only its own
  /// editor reads the values back - what changes here is what 应用 writes into the applied layout.
  void _setSpacing(String tileId, {int? spacing, bool? showSpacing}) {
    final String key = _templateKey(tileId);
    final FzLayout tuned =
        _templates[key] ?? FzLayout(type: _templateTypeFor(tileId));
    tuned.spacing = (spacing ?? tuned.spacing).clamp(0, 100);
    tuned.showSpacing = showSpacing ?? tuned.showSpacing;
    _templates[key] = tuned;
    try {
      FzStore.writeTemplates(_templates.values.toList());
    } catch (e) {
      _showStatus('write failed: $e', true);
    }
    setState(() {});
  }

  /// Every write goes through FzStore, so the field names and the atomic replace are the ones
  /// the contract pins down. The engine's FileWatcher picks the change up.
  void _write(String what, void Function() write) {
    try {
      write();
      _showStatus('${fzT('applied', widget.lang)}$what', false);
      _reload();
    } catch (e) {
      _showStatus('write failed: $e', true);
    }
  }

  Timer? _statusTimer;
  final ScrollController _scroll = ScrollController();

  /// The confirmation lives for a moment and then collapses itself.
  void _showStatus(String text, bool error) {
    _statusTimer?.cancel();
    setState(() {
      _status = text;
      _error = error;
    });
    _statusTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) {
        setState(() => _status = '');
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final FzLang lang = widget.lang;
    String t(String k) => fzT(k, lang);

    return FzWindowFrame(
      title: t('editor_title'),
      tooltips: FzCaptionTooltips(
        minimize: t('win_minimize'),
        close: t('win_close'),
        settings: t('win_settings'),
      ),
      hasSettingsButton: true,
      child: Column(
        children: <Widget>[
          Expanded(
            child: _params.monitors.isEmpty
                ? _emptyState(c, t)
                // Cross-fade between the pages, like the native editor's 200ms page change.
                : AnimatedSwitcher(
                    duration: FzMotion.page,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: _pageWidget(c, t),
                  ),
          ),
          // The write-back confirmation. It slides away on its own, so the window keeps no
          // permanent status chrome.
          AnimatedSize(
            duration: FzMotion.collapse,
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: _status.isEmpty
                // 1px of card colour, so the seam above it never doubles as a second hairline.
                ? const SizedBox(width: double.infinity, height: 1)
                : Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(
                      horizontal: FzMetrics.pagePadX,
                    ),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: c.card,
                      border: Border(top: BorderSide(color: c.cardBorder)),
                    ),
                    child: Text(
                      _status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _error ? c.danger : c.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pageWidget(FzColors c, String Function(String) t) {
    switch (_page) {
      case 'grid':
        final FzCustomLayout editing = _editing!;
        return GridEditorPage(
          key: const ValueKey<String>('grid'),
          lang: widget.lang,
          initial: editing,
          isNew: _editingIsNew,
          onCancel: _cancelEdited,
          onSave: _saveEdited,
        );
      case 'canvas':
        return CanvasEditorPage(
          key: const ValueKey<String>('canvas'),
          lang: widget.lang,
          initial: _editing!,
          onCancel: _cancelEdited,
          onSave: _saveEdited,
        );
      case 'template':
        return _templatePage(c, t);
      default:
        return FzViewport(
          key: const ValueKey<String>('browse'),
          controller: _scroll,
          top: 0,
          children: <Widget>[
            _card(c, <Widget>[
              _monitorTabs(c, t),
              _section(c, t('templates')),
              _templateTiles(c, t),
              if (_custom.isNotEmpty) ...<Widget>[
                _section(c, t('custom_layouts')),
                _customTiles(c, t),
              ],
              if (_customSelected >= 0) _quickSwitch(c, t),
              _actionRow(c, t),
              _footer(c, t),
            ]),
          ],
        );
    }
  }

  Widget _emptyState(FzColors c, String Function(String) t) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        t('no_monitors'),
        textAlign: TextAlign.center,
        style: TextStyle(color: c.ink2, fontSize: 12, height: 1.6),
      ),
    ),
  );

  Widget _card(FzColors c, List<Widget> children) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(FzRadius.base),
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(FzRadius.base),
      border: Border.all(color: c.cardBorder, width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _section(FzColors c, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: TextStyle(color: c.ink, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  Widget _monitorTabs(FzColors c, String Function(String) t) {
    // One tab per monitor, exactly like the native editor - including when there is only one,
    // where it doubles as "this is the display you are editing".
    // The specimen's `.tabs` carries `margin-bottom: var(--section)`; this used `header`, which is
    // twice that and left the tab strip floating above the first section.
    return Padding(
      padding: const EdgeInsets.only(bottom: FzMetrics.section),
      child: Row(
        children: _params.monitors.asMap().entries.map((
          MapEntry<int, FzMonitorInfo> e,
        ) {
          final FzMonitorInfo m = e.value;
          final bool selected = e.key == _monitor;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: e.key == _params.monitors.length - 1 ? 0 : 8,
              ),
              child: GestureDetector(
                onTap: () => setState(() => _monitor = e.key),
                child: FzHoverBuilder(
                  builder: (BuildContext context, bool hovering) => AnimatedContainer(
                    duration: FzMotion.select,
                    curve: Curves.easeOutCubic,
                    height: FzMetrics.tab,
                    decoration: BoxDecoration(
                      color: selected
                          ? c.field
                          : hovering
                          ? c.hover
                          : fade(c.hover),
                      borderRadius: BorderRadius.circular(FzRadius.base),
                    ),
                    // The Stack has to fill the cell, or the underline lands on the text
                    // instead of 4px off the tab's own bottom edge.
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Text(
                          '${m.device.monitor}  ${m.fullArea.width}×${m.fullArea.height}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? c.ink : c.ink2,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        // The tab underline is one of the five pill-family slots.
                        Positioned(
                          bottom: 4,
                          child: AnimatedContainer(
                            duration: FzMotion.select,
                            curve: Curves.easeOutCubic,
                            width: selected ? 28 : 0,
                            height: 3,
                            decoration: BoxDecoration(
                              color: selected ? c.accent : fade(c.accent),
                              borderRadius: BorderRadius.circular(
                                FzRadius.pill,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _templateTiles(FzColors c, String Function(String) t) => Padding(
    padding: const EdgeInsets.only(bottom: FzMetrics.section),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: kTemplates.asMap().entries.map((MapEntry<int, String> e) {
        final String id = e.value;
        final bool selected = _customSelected < 0 && _template == id;
        return FzEnter(
          index: e.key,
          child: _tile(
            c: c,
            selected: selected,
            caption: t(id),
            build: (Size size) => templateRects(
              id,
              size,
              _zoneCount,
              _spacingFor(id),
              _showSpacingFor(id),
            ),
            onTap: () => setState(() {
              _template = id;
              _customSelected = -1;
            }),
          ),
        );
      }).toList(),
    ),
  );

  Widget _customTiles(FzColors c, String Function(String) t) => Padding(
    padding: const EdgeInsets.only(bottom: FzMetrics.section),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _custom.asMap().entries.map((MapEntry<int, FzCustomLayout> e) {
        final FzCustomLayout layout = e.value;
        final int? digit = _hotkeys[layout.uuid];
        return FzEnter(
          index: kTemplates.length + e.key,
          child: _tile(
            c: c,
            selected: e.key == _customSelected,
            caption: layout.name.isEmpty ? layout.uuid : layout.name,
            badge: digit,
            build: (Size size) => customLayoutRects(layout, size),
            onTap: () => setState(() => _customSelected = e.key),
          ),
        );
      }).toList(),
    ),
  );

  Widget _tile({
    required FzColors c,
    required bool selected,
    required String caption,
    required List<FzRect> Function(Size) build,
    required VoidCallback onTap,
    int? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: FzHoverBuilder(
        builder: (BuildContext context, bool hovering) => AnimatedContainer(
          duration: FzMotion.select,
          curve: Curves.easeOutCubic,
          width: 128,
          height: 108,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(FzRadius.base),
            border: Border.all(
              color: selected
                  ? c.accent
                  : hovering
                  ? c.fieldBorderHot
                  : c.fieldBorder,
              width: selected ? 2 : 1,
            ),
            // One shadow slot, always present, so the halo fades instead of popping.
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: selected ? c.accentSoft : fade(c.accentSoft),
                blurRadius: 0,
                spreadRadius: selected ? 3 : 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: FzZonePreview(rectsFor: build, selected: selected),
                    ),
                    if (badge != null)
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(FzRadius.small),
                          ),
                          child: Text(
                            '$badge',
                            style: TextStyle(
                              color: c.accentInk,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickSwitch(FzColors c, String Function(String) t) {
    final FzCustomLayout layout = _custom[_customSelected];
    return Padding(
      padding: const EdgeInsets.only(bottom: FzMetrics.section),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 80,
            child: Text(
              t('quick_switch'),
              style: TextStyle(color: c.ink, fontSize: 12),
            ),
          ),
          ...List<Widget>.generate(10, (int slot) {
            final int digit = (slot + 1) % 10;
            final bool mine =
                layout.uuid.isNotEmpty && _hotkeys[layout.uuid] == digit;
            final bool taken =
                !mine &&
                _hotkeys.entries.any(
                  (MapEntry<String, int> e) =>
                      e.value == digit && e.key != layout.uuid,
                );
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FzEnter(
                index: slot,
                step: const Duration(milliseconds: 18),
                child: FzDigit(
                  digit: digit,
                  state: mine
                      ? FzDigitState.on
                      : (taken ? FzDigitState.taken : FzDigitState.idle),
                  onTap: () => _write('Win+Ctrl+Alt+$digit', () {
                    // The file stores the digit 0-9, not a virtual key code.
                    final Map<String, int> next = Map<String, int>.from(
                      _hotkeys,
                    );
                    next.removeWhere((String id, int d) => d == digit);
                    if (!mine) {
                      next[layout.uuid] = digit;
                    }
                    FzStore.writeLayoutHotkeys(next);
                  }),
                ),
              ),
            );
          }),
          Expanded(
            child: Text(
              t('quick_switch_hint'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.ink2, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// Every button on this line is fixed width, so the line they need is arithmetic rather than font
  /// dependent: 504 of create/edit/delete, 308 of defaults, 8 between - the same sum the specimen's
  /// `flex-wrap` breaks on. Below it the defaults take a line of their own and stay right-aligned,
  /// which is the case the window's 880 default lands in (816 of card content). A `Spacer` used to
  /// overflow instead of adapting, which is what the 620-logical minimum hit.
  Widget _actionRow(FzColors c, String Function(String) t) {
    final bool hasCustom =
        _customSelected >= 0 && _customSelected < _custom.length;
    final String editKey = !hasCustom
        ? 'edit_template'
        : (_custom[_customSelected].isCanvas ? 'edit_canvas' : 'edit_grid');
    final List<Widget> create = <Widget>[
      FzButton(label: t('new_layout'), width: 120, onTap: _newGrid),
      const SizedBox(width: 8),
      FzButton(label: t('new_canvas'), width: 120, onTap: _newCanvas),
      const SizedBox(width: 8),
      FzButton(
        label: t(editKey),
        width: 120,
        // A template opens its own page, so this one is never disabled - there is always a
        // selection, and a template always has two numbers to tune.
        enabled: _currentMonitor != null,
        onTap: _editSelected,
      ),
      const SizedBox(width: 8),
      // A delete, so it borrows the close button's danger treatment - and the same
      // second-thoughts dialog the corner badge used to raise.
      FzButton(
        label: t('delete_layout'),
        width: 120,
        enabled: hasCustom,
        dangerOnHover: true,
        onTap: () => _deleteCustom(_customSelected),
      ),
    ];
    final List<Widget> defaults = <Widget>[
      FzButton(
        label: t('set_default_horizontal'),
        width: 150,
        primary: _defaults['horizontal']?.uuid == _currentLayout().uuid &&
            _defaults['horizontal'] != null,
        onTap: () => _write(
          'horizontal default',
          () => FzStore.writeDefaultLayout('horizontal', _currentLayout()),
        ),
      ),
      const SizedBox(width: 8),
      FzButton(
        label: t('set_default_vertical'),
        width: 150,
        primary: _defaults['vertical']?.uuid == _currentLayout().uuid &&
            _defaults['vertical'] != null,
        onTap: () => _write(
          'vertical default',
          () => FzStore.writeDefaultLayout('vertical', _currentLayout()),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => box.maxWidth >= 820
            ? Row(children: <Widget>[...create, const Spacer(), ...defaults])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(children: create),
                  const SizedBox(height: 8),
                  Row(children: <Widget>[const Spacer(), ...defaults]),
                ],
              ),
      ),
    );
  }

  /// The page a fixed template opens on. The shape is the engine's, so the only things to adjust are
  /// the two numbers that shape it and whether the gap between zones is drawn; splitting, merging
  /// and dragging need a layout of your own, which is what 另存为自定义布局 hands over to.
  Widget _templatePage(FzColors c, String Function(String) t) => FzEditorShell(
    key: const ValueKey<String>('template'),
    colors: c,
    bar: <Widget>[
      FzFieldLabel(colors: c, text: t(_template)),
      const Spacer(),
      // A Wrap rather than three bare buttons: at the window's minimum the three would overflow the
      // row instead of giving way.
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: <Widget>[
          FzButton(
            label: t('cancel'),
            width: 90,
            onTap: () => setState(() => _page = 'browse'),
          ),
          FzButton(
            label: t('save_as_custom'),
            width: 150,
            onTap: _saveTemplateAsCustom,
          ),
          FzButton(
            label: t('apply_only'),
            width: 160,
            primary: true,
            onTap: _applyCurrent,
          ),
        ],
      ),
    ],
    body: <Widget>[
      SizedBox(
        height: 260,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(FzRadius.base),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: FzZonePreview(
              rectsFor: (Size size) => templateRects(
                _template,
                size,
                _zoneCount,
                _spacingFor(_template),
                _showSpacingFor(_template),
              ),
              selected: true,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _tuningRow(c, t),
      const SizedBox(height: 12),
      Text(
        t('template_hint'),
        style: TextStyle(color: c.ink2, fontSize: 11, height: 1.5),
      ),
    ],
  );

  /// The zone count, the spacing and the switch. They feed the layout 应用 writes rather than
  /// editing custom-layouts.json - the engine reads the spacing off the applied layout, so a saved
  /// layout's own value is its default, and these belong to the template being tuned.
  Widget _tuningRow(FzColors c, String Function(String) t) => Wrap(
    // The pairs are 32 tall but the toggle is 20: without this the switch rides at the top of the
    // line while the fields sit centred in theirs.
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: 8,
    children: <Widget>[
      _tuningPair(
        c,
        label: t('zone_count'),
        field: FzNumberField(
          value: _zoneCount,
          width: 56,
          min: 1,
          max: 128,
          onChanged: (int v) => setState(() => _zoneCount = v.clamp(1, 128)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 16),
        child: _tuningPair(
          c,
          label: t('spacing'),
          field: FzNumberField(
            value: _spacingFor(_template),
            width: 56,
            min: 0,
            max: 100,
            onChanged: (int v) => _setSpacing(_template, spacing: v),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FzToggle(
              value: _showSpacingFor(_template),
              onChanged: (bool v) => _setSpacing(_template, showSpacing: v),
            ),
            const SizedBox(width: 8),
            Text(
              t('show_spacing'),
              style: TextStyle(color: c.ink2, fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );

  /// The one write the browse page and the template page both offer.
  void _applyCurrent() {
    final FzMonitorInfo? monitor = _currentMonitor;
    if (monitor == null) return;
    _write(
      monitor.device.monitor,
      () => FzStore.applyLayoutToMonitor(monitor.device, _currentLayout()),
    );
  }

  /// The apply button, on a line of its own.
  Widget _footer(FzColors c, String Function(String) t) => Container(
    margin: const EdgeInsets.only(top: FzMetrics.section),
    padding: const EdgeInsets.only(top: FzMetrics.section),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: c.cardBorder)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        FzButton(
          label: t('apply'),
          width: 160,
          primary: true,
          onTap: _applyCurrent,
        ),
      ],
    ),
  );

  Widget _tuningPair(FzColors c, {required String label, required Widget field}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(label, style: TextStyle(color: c.ink2, fontSize: 12)),
      const SizedBox(width: 8),
      field,
    ],
  );
}

enum FzDigitState { idle, on, taken }

class FzDigit extends StatelessWidget {
  const FzDigit({
    super.key,
    required this.digit,
    required this.state,
    required this.onTap,
  });
  final int digit;
  final FzDigitState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final bool on = state == FzDigitState.on;
    return GestureDetector(
      onTap: onTap,
      child: FzHoverBuilder(
        builder: (BuildContext context, bool hovering) => AnimatedContainer(
          duration: FzMotion.select,
          curve: Curves.easeOutCubic,
          width: 32,
          height: FzMetrics.control,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.accent : c.field,
            borderRadius: BorderRadius.circular(FzRadius.base),
            border: Border.all(
              color: on
                  ? c.accent
                  : hovering
                  ? c.fieldBorderHot
                  : c.fieldBorder,
              width: 1,
            ),
          ),
          child: Text(
            '$digit',
            style: TextStyle(
              color: on
                  ? c.accentInk
                  : (state == FzDigitState.taken ? c.ink3 : c.ink),
              fontSize: 12,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Zone rectangles that animate between layouts: the Flutter equivalent of the 200ms morph the
/// native preview does by hand in PaintGridPreview.
class FzZonePreview extends StatelessWidget {
  const FzZonePreview({
    super.key,
    required this.rectsFor,
    this.selected = false,
  });
  final List<FzRect> Function(Size size) rectsFor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);
        final List<FzRect> rects = rectsFor(size);
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: rects.map((FzRect r) {
            return AnimatedPositioned(
              duration: FzMotion.page,
              curve: Curves.easeOutCubic,
              left: r.left.toDouble(),
              top: r.top.toDouble(),
              width: r.width.toDouble().clamp(0, size.width),
              height: r.height.toDouble().clamp(0, size.height),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? c.accent
                      : c.fieldBorder.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(FzRadius.small),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Mirrors LayoutConfigurator::Grid: rows grow until rows*rows exceeds the count, then the
/// columns take the remainder, and percentages are computed so they sum to exactly 10000.
FzGridModel gridShapeFor(int zoneCount) {
  final int count = zoneCount < 1 ? 1 : zoneCount;
  int rows = 1;
  while (count ~/ rows >= rows) {
    rows++;
  }
  rows--;
  int columns = count ~/ rows;
  if (count % rows != 0) {
    columns++;
  }

  final List<int> rowsPercent = List<int>.generate(
    rows,
    (int i) =>
        FzGridModel.percentMultiplier * (i + 1) ~/ rows -
        FzGridModel.percentMultiplier * i ~/ rows,
  );
  final List<int> columnsPercent = List<int>.generate(
    columns,
    (int i) =>
        FzGridModel.percentMultiplier * (i + 1) ~/ columns -
        FzGridModel.percentMultiplier * i ~/ columns,
  );

  int index = 0;
  final List<List<int>> map = <List<int>>[];
  for (int r = 0; r < rows; r++) {
    final List<int> line = <int>[];
    for (int col = 0; col < columns; col++) {
      line.add(index++);
      if (index == count) index--;
    }
    map.add(line);
  }

  return FzGridModel(
    rows: rows,
    columns: columns,
    rowsPercentage: rowsPercent,
    columnsPercentage: columnsPercent,
    cellChildMap: map,
  );
}

FzGridModel _priorityShape(
  int rows,
  int columns,
  List<int> rowsPercent,
  List<int> columnsPercent,
  List<List<int>> map,
) => FzGridModel(
  rows: rows,
  columns: columns,
  rowsPercentage: rowsPercent,
  columnsPercentage: columnsPercent,
  cellChildMap: map,
);

/// `LayoutConfigurator.cpp`'s `predefinedPriorityGridLayouts`, entry for entry: the eleven shapes
/// a priority grid is hand-tuned to, indexed by zone count minus one. The wide middle column is
/// the point of the whole family - zone 1 is the one a window is meant to land in.
final List<FzGridModel> kPriorityGridShapes = <FzGridModel>[
  _priorityShape(1, 1, <int>[10000], <int>[10000], <List<int>>[
    <int>[0],
  ]),
  _priorityShape(1, 2, <int>[10000], <int>[6667, 3333], <List<int>>[
    <int>[0, 1],
  ]),
  _priorityShape(1, 3, <int>[10000], <int>[2500, 5000, 2500], <List<int>>[
    <int>[0, 1, 2],
  ]),
  _priorityShape(2, 3, <int>[5000, 5000], <int>[2500, 5000, 2500], <List<int>>[
    <int>[0, 1, 2],
    <int>[0, 1, 3],
  ]),
  _priorityShape(2, 3, <int>[5000, 5000], <int>[2500, 5000, 2500], <List<int>>[
    <int>[0, 1, 2],
    <int>[3, 1, 4],
  ]),
  _priorityShape(3, 3, <int>[3333, 3334, 3333], <int>[2500, 5000, 2500], <List<int>>[
    <int>[0, 1, 2],
    <int>[0, 1, 3],
    <int>[4, 1, 5],
  ]),
  _priorityShape(3, 3, <int>[3333, 3334, 3333], <int>[2500, 5000, 2500], <List<int>>[
    <int>[0, 1, 2],
    <int>[3, 1, 4],
    <int>[5, 1, 6],
  ]),
  _priorityShape(3, 4, <int>[3333, 3334, 3333], <int>[2500, 2500, 2500, 2500], <List<int>>[
    <int>[0, 1, 2, 3],
    <int>[4, 1, 2, 5],
    <int>[6, 1, 2, 7],
  ]),
  _priorityShape(3, 4, <int>[3333, 3334, 3333], <int>[2500, 2500, 2500, 2500], <List<int>>[
    <int>[0, 1, 2, 3],
    <int>[4, 1, 2, 5],
    <int>[6, 1, 7, 8],
  ]),
  _priorityShape(3, 4, <int>[3333, 3334, 3333], <int>[2500, 2500, 2500, 2500], <List<int>>[
    <int>[0, 1, 2, 3],
    <int>[4, 1, 5, 6],
    <int>[7, 1, 8, 9],
  ]),
  _priorityShape(3, 4, <int>[3333, 3334, 3333], <int>[2500, 2500, 2500, 2500], <List<int>>[
    <int>[0, 1, 2, 3],
    <int>[4, 1, 5, 6],
    <int>[7, 8, 9, 10],
  ]),
];

/// The shape the engine would really build, quirk included: `PriorityGrid` tests
/// `zoneCount < predefinedLayoutsCount`, so eleven zones is a plain grid and the eleventh entry
/// above is never reached - in C++ as here. The preview matches the engine rather than fixing it,
/// because a tile that promises a shape the zones will not take is the worse bug.
FzGridModel priorityGridShapeFor(int zoneCount) =>
    zoneCount >= 1 && zoneCount < kPriorityGridShapes.length
    ? kPriorityGridShapes[zoneCount - 1]
    : gridShapeFor(zoneCount);

List<FzRect> _inset(List<FzRect> rects, int inset) {
  final List<FzRect> out = <FzRect>[];
  for (final FzRect r in rects) {
    final FzRect shrunk = FzRect(
      r.left + inset,
      r.top + inset,
      r.right - inset,
      r.bottom - inset,
    );
    if (shrunk.width >= 2 && shrunk.height >= 2) out.add(shrunk);
  }
  return out;
}

/// What each template tile draws. The engine picks the same shapes for the same names.
List<FzRect> templateRects(
  String template,
  Size size,
  int zoneCount,
  int spacing,
  bool showSpacing,
) {
  final FzRect area = FzRect(0, 0, size.width.round(), size.height.round());
  final int count = zoneCount < 1 ? 1 : zoneCount;
  final int inset = showSpacing ? spacing ~/ 2 : 1;

  switch (template) {
    case 't_blank':
      return <FzRect>[];
    case 't_focus':
      // The engine's Focus zone is a 40% rect inset by 100px with a 50px cascade per extra
      // zone; those offsets only make sense on a full monitor, so the tile scales them.
      final int pad = (area.width * 0.06).round();
      final int w = (area.width * 0.40).round();
      final int h = (area.height * 0.40).round();
      final int step = count <= 1 ? 0 : (area.width * 0.05).round();
      return _inset(
        List<FzRect>.generate(count, (int i) {
          final int l = pad + i * step;
          final int t = pad + i * step;
          return FzRect(
            l,
            t,
            (l + w).clamp(0, area.right),
            (t + h).clamp(0, area.bottom),
          );
        }),
        inset,
      );
    case 't_columns':
      return _inset(FzGridModel.uniform(1, count).zoneRects(area), inset);
    case 't_rows':
      return _inset(FzGridModel.uniform(count, 1).zoneRects(area), inset);
    case 't_grid':
      return _inset(gridShapeFor(count).zoneRects(area), inset);
    case 't_priority':
      return _inset(priorityGridShapeFor(count).zoneRects(area), inset);
    default:
      return _inset(gridShapeFor(count).zoneRects(area), inset);
  }
}

List<FzRect> customLayoutRects(FzCustomLayout layout, Size size) {
  final FzRect area = FzRect(0, 0, size.width.round(), size.height.round());
  if (layout.isCanvas) {
    if (layout.referenceWidth <= 0 || layout.referenceHeight <= 0) {
      return <FzRect>[];
    }
    return layout.canvasZones.map((FzRect z) {
      return FzRect(
        (z.left * area.width / layout.referenceWidth).round(),
        (z.top * area.height / layout.referenceHeight).round(),
        (z.right * area.width / layout.referenceWidth).round(),
        (z.bottom * area.height / layout.referenceHeight).round(),
      );
    }).toList();
  }

  final FzGridModel? grid = FzGridModel.fromCustom(layout);
  if (grid == null) return <FzRect>[];
  final int inset = layout.showSpacing ? layout.spacing ~/ 2 : 1;
  return _inset(grid.zoneRects(area), inset);
}

/// The way out of a delete, animated both directions like the colour picker: a layout someone
/// built by hand is not worth losing to one stray click, and a confirm that blinks in and out
/// does not count as asking.
class _ConfirmDelete extends StatefulWidget {
  const _ConfirmDelete({
    required this.title,
    required this.name,
    required this.cancelLabel,
    required this.okLabel,
  });

  final String title;
  final String name;
  final String cancelLabel;
  final String okLabel;

  @override
  State<_ConfirmDelete> createState() => _ConfirmDeleteState();
}

class _ConfirmDeleteState extends State<_ConfirmDelete> {
  bool _shown = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _shown = true);
      }
    });
  }

  void _exit([bool? result]) {
    if (_closing) {
      return;
    }
    setState(() => _closing = true);
    Future<void>.delayed(FzMotion.select, () {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final bool up = _shown && !_closing;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          _exit();
        }
      },
      child: AnimatedScale(
        scale: up ? 1 : 0.96,
        duration: _closing ? FzMotion.select : FzMotion.page,
        curve: Curves.fastOutSlowIn,
        child: AnimatedOpacity(
          opacity: up ? 1 : 0,
          duration: _closing ? FzMotion.select : FzMotion.page,
          child: Dialog(
            backgroundColor: c.card,
            elevation: 0,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FzRadius.base),
              side: BorderSide(color: c.cardBorder),
            ),
            child: SizedBox(
              width: 300,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.ink2, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        const Spacer(),
                        FzButton(
                          label: widget.cancelLabel,
                          width: 88,
                          onTap: () => _exit(false),
                        ),
                        const SizedBox(width: 8),
                        FzButton(
                          label: widget.okLabel,
                          width: 88,
                          primary: true,
                          onTap: () => _exit(true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
