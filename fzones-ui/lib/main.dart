import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_bar.dart';
import 'color_picker.dart';
import 'design.dart';
import 'editor_page.dart';
import 'settings_model.dart';
import 'settings_writer.dart';
import 'strings.dart';
import 'ui_settings.dart';
import 'widgets.dart';
import 'window_bridge.dart';

/// The runner hands the command line to the Dart entrypoint, so one exe serves both windows:
/// --editor opens the layout editor, anything else the settings window.
void main(List<String> args) {
  // --dark/--light and --zh/--en are review-only deep links that override the persisted choice;
  // without them the app reads ui-settings.json, whose default is "follow system" both ways.
  final bool pinned = args.any(
    (String a) => a == '--dark' || a == '--light' || a == '--zh' || a == '--en',
  );
  runApp(
    FzApp(
      startInEditor: args.contains('--editor'),
      // Review-only deep links, the same idea as the HTML specimen's ?page=; the engine only
      // ever passes --editor.
      startEditorPage: args.contains('--grid')
          ? 'grid'
          : (args.contains('--canvas')
                ? 'canvas'
                : (args.contains('--template') ? 'template' : 'browse')),
      revealApp: args.contains('--app'),
      ui: pinned
          ? FzUiSettings(
              theme: args.contains('--dark')
                  ? FzThemeMode.dark
                  : (args.contains('--light')
                        ? FzThemeMode.light
                        : FzThemeMode.system),
              language: args.contains('--zh')
                  ? FzLangMode.zh
                  : (args.contains('--en') ? FzLangMode.en : FzLangMode.system),
            )
          : FzUiSettings.load(),
      // A pinned review run stays pinned: it must not be dragged back to the file by the other
      // window's settings button.
      followUiSettingsFile: !pinned,
    ),
  );
}

/// Lower-cased file name of a path, so a directory event can be matched against one file. Both
/// separators appear depending on how the event was raised.
String fzFileName(String path) {
  final String slashed = path.replaceAll(r'\', '/');
  return slashed.substring(slashed.lastIndexOf('/') + 1).toLowerCase();
}

/// Whether a directory event could mean one file changed.
///
/// Every write here goes through `SettingsWriter.writeAtomic`, which is a sibling `name.tmp` plus a
/// rename - and Dart's Windows watcher reports that rename under the *old* name only, so no event
/// ever carries the real file name for a first write. Filtering on the name alone is what lost the
/// first theme switch between the two windows; from the second write on, the replaced file produced
/// a `delete` event, which is why it started working after it had once failed. Reading early yields
/// the previous content, and both watchers compare before they act, so the extra events are free.
bool fzEventTouches(String path, String name) {
  final String lower = name.toLowerCase();
  final String seen = fzFileName(path);
  return seen == lower || seen == '$lower.tmp';
}

class FzApp extends StatefulWidget {
  const FzApp({
    super.key,
    this.startInEditor = false,
    this.startEditorPage = 'browse',
    this.revealApp = false,
    this.ui = const FzUiSettings(),
    this.followUiSettingsFile = true,
  });

  final bool startInEditor;
  final String startEditorPage;
  final FzUiSettings ui;

  /// `--app`: open the settings list already scrolled to the App group, so the theme, language
  /// and autostart rows can be reviewed - or clicked by a script - without a scroll gesture.
  final bool revealApp;

  /// Whether to keep re-reading `ui-settings.json`. Both windows are separate processes, so
  /// this is the whole of the protocol between them: whichever one changes theme or language
  /// writes the file, the other one watches it.
  final bool followUiSettingsFile;

  @override
  State<FzApp> createState() => _FzAppState();
}

class _FzAppState extends State<FzApp> {
  late FzUiSettings _ui = widget.ui;
  StreamSubscription<FileSystemEvent>? _uiWatch;

  @override
  void initState() {
    super.initState();
    if (widget.followUiSettingsFile) {
      _watchUiSettings();
    }
  }

  @override
  void dispose() {
    _uiWatch?.cancel();
    super.dispose();
  }

  /// The other window's settings button, seen from here. Reading the file back is what keeps
  /// the two windows on one theme instead of two.
  void _watchUiSettings() {
    try {
      final Directory dir = Directory(FzPaths.fancyZonesDir);
      // Watch it into existence: a first run has no data folder until somebody writes to it, and
      // a watcher that gave up then would leave the two windows out of step for the whole session.
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _uiWatch = dir.watch(events: FileSystemEvent.all).listen((
        FileSystemEvent e,
      ) {
        if (!fzEventTouches(e.path, 'ui-settings.json')) {
          return;
        }
        // save() writes on every toggle too, so compare before rebuilding - and let an
        // unreadable mid-rename state fall through to the next event.
        final FzUiSettings next = FzUiSettings.load();
        if (mounted && next != _ui) {
          setState(() => _ui = next);
        }
      });
    } catch (_) {
      // Watching is a convenience; the values still came from the file at startup.
    }
  }

  FzLang get _lang {
    switch (_ui.language) {
      case FzLangMode.en:
        return FzLang.en;
      case FzLangMode.zh:
        return FzLang.zh;
      case FzLangMode.system:
        return fzResolveLang(Platform.localeName);
    }
  }

  /// The App group's two switches: they change this run at once and land in ui-settings.json,
  /// which the other window is watching.
  void _setTheme(FzThemeMode mode) =>
      setState(() => _ui = _ui.withTheme(mode)..save());

  void _setLanguage(FzLangMode mode) =>
      setState(() => _ui = _ui.withLanguage(mode)..save());

  @override
  Widget build(BuildContext context) {
    final bool chinese = _lang == FzLang.zh;
    return MaterialApp(
      title: 'FZones',
      debugShowCheckedModeBanner: false,
      theme: buildFzTheme(FzColors.light, chinese),
      darkTheme: buildFzTheme(FzColors.dark, chinese),
      themeMode: switch (_ui.theme) {
        FzThemeMode.light => ThemeMode.light,
        FzThemeMode.dark => ThemeMode.dark,
        FzThemeMode.system => ThemeMode.system,
      },
      // The 240ms crossfade the native side implements in Theme::AdvanceTheme.
      themeAnimationDuration: FzMotion.theme,
      themeAnimationCurve: Curves.easeOutCubic,
      home: widget.startInEditor
          ? EditorPage(lang: _lang, startPage: widget.startEditorPage)
          : SettingsPage(
              lang: _lang,
              ui: _ui,
              onTheme: _setTheme,
              onLanguage: _setLanguage,
              revealApp: widget.revealApp,
            ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.lang,
    required this.ui,
    required this.onTheme,
    required this.onLanguage,
    this.revealApp = false,
  });

  final FzLang lang;

  /// Read back into the App group, so the segments show what is persisted.
  final FzUiSettings ui;
  final ValueChanged<FzThemeMode> onTheme;
  final ValueChanged<FzLangMode> onLanguage;

  /// See `--app` on [FzApp].
  final bool revealApp;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsSnapshot _snapshot = SettingsSnapshot.empty();
  StreamSubscription<FileSystemEvent>? _watch;
  final ScrollController _scroll = ScrollController();

  /// The autostart row follows the registry, which the window channel reports into these.
  final Listenable _autostart = Listenable.merge(<Listenable>[
    FzWindow.autostart,
    FzWindow.autostartManaged,
  ]);

  /// Values already sent to the file, kept on screen until the reload lands so a control
  /// never flickers back to the old value for a frame.
  final Map<String, Object?> _pending = <String, Object?>{};

  /// Read-modify-write plus an atomic replace; the engine's FileWatcher does the rest.
  Future<void> _commit(String key, Object? value) async {
    if (!mounted) {
      return;
    }
    setState(() => _pending[key] = value);
    try {
      SettingsWriter.writeValue(FzPaths.settingsJson, key, value);
      final SettingsSnapshot next = SettingsSnapshot.load(FzPaths.settingsJson);
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = next;
        _pending.remove(key);
      });
    } catch (_) {
      // The control falls back to what the file says. There is no status line to report into
      // since the review strip went away.
      if (!mounted) {
        return;
      }
      setState(() => _pending.remove(key));
    }
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _startWatching();
    if (widget.revealApp) {
      _revealAppGroup();
    }
  }

  /// `--app`: land on the last card. Two jumps, because a list of explicit children estimates the
  /// extent of whatever it has not built yet and only the second pass sees the real one.
  void _revealAppGroup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    final SettingsSnapshot next = SettingsSnapshot.load(FzPaths.settingsJson);
    if (!mounted) {
      _snapshot = next;
      return;
    }
    setState(() {
      _snapshot = next;
      // An external write (the engine, or the other window) wins over anything pending.
      _pending.clear();
    });
  }

  /// The engine's FileWatcher watches this same file, so a write here is picked up there with no
  /// extra protocol.
  void _startWatching() {
    try {
      final Directory dir = Directory(FzPaths.fancyZonesDir);
      if (!dir.existsSync()) {
        return;
      }
      _watch = dir.watch(events: FileSystemEvent.all).listen((
        FileSystemEvent e,
      ) {
        if (fzEventTouches(e.path, 'settings.json')) {
          _reload();
        }
      });
    } catch (_) {
      // Watching is a convenience; the page still reads the file at startup.
    }
  }

  Object? _valueOf(RowDef row) {
    if (_pending.containsKey(row.key)) {
      return _pending[row.key];
    }
    switch (row.kind) {
      case RowKind.boolean:
        return _snapshot.flag(row.key, row.defaultValue == true);
      case RowKind.integer:
        return _snapshot.number(row.key, (row.defaultValue as int?) ?? 0);
      case RowKind.color:
        return _snapshot.text(row.key, row.defaultText);
      case RowKind.multiline:
        return _snapshot.text(row.key, '');
      case RowKind.choice:
        if (row.choiceIsFlag) {
          return _snapshot.flag(row.key, row.defaultValue == true) ? 1 : 0;
        }
        return _snapshot.number(row.key, (row.defaultValue as int?) ?? 0);
      case RowKind.readonly:
        return _snapshot.hotkey(row.key, row.defaultText);
      case RowKind.header:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final FzLang lang = widget.lang;
    String t(String k) => fzT(k, lang);

    final List<Widget> children = <Widget>[];
    List<Widget> cardRows = <Widget>[];
    String? cardTitle;

    void flushCard() {
      final String? title = cardTitle;
      if (title != null) {
        children.add(_Card(title: title, children: cardRows));
        cardTitle = null;
        cardRows = <Widget>[];
      }
    }

    for (final RowDef row in kRows) {
      if (row.kind == RowKind.header) {
        flushCard();
        cardTitle = t(row.label);
        continue;
      }
      final bool enabled = rowEnabled(_snapshot, row);
      final bool hidden = !enabled && row.hideWhenGatedOff;
      cardRows.add(
        AnimatedSize(
          duration: FzMotion.collapse,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: hidden
              ? const SizedBox(width: double.infinity, height: 0)
              : _Row(
                  label: t(row.label),
                  enabled: enabled,
                  stacked: row.kind == RowKind.multiline,
                  control: _controlFor(row, t),
                ),
        ),
      );
    }
    flushCard();
    children.add(_appCard(t));

    return FzWindowFrame(
      title: t('app_title'),
      tooltips: FzCaptionTooltips(
        minimize: t('win_minimize'),
        close: t('win_close'),
      ),
      hasSettingsButton: false,
      child: FzViewport(controller: _scroll, children: children),
    );
  }

  /// The App group. Theme and language belong to this UI and persist in ui-settings.json, which
  /// the engine never reads; autostart is the exception - it is the engine's own HKCU Run entry,
  /// shared with the installer, so it goes over the window channel instead.
  Widget _appCard(String Function(String) t) => _Card(
    title: t('group_app'),
    children: <Widget>[
      _Row(
        label: t('theme'),
        enabled: true,
        control: FzSegmented(
          labels: <String>[
            t('theme_system'),
            t('theme_light'),
            t('theme_dark'),
          ],
          index: widget.ui.theme.index,
          onChanged: (int i) => widget.onTheme(FzThemeMode.values[i]),
        ),
      ),
      _Row(
        label: t('language'),
        enabled: true,
        control: FzSegmented(
          labels: <String>[t('lang_system'), t('lang_en'), t('lang_zh')],
          index: widget.ui.language.index,
          onChanged: (int i) => widget.onLanguage(FzLangMode.values[i]),
        ),
      ),
      ListenableBuilder(
        listenable: _autostart,
        builder: (BuildContext context, Widget? _) {
          final bool managed = FzWindow.autostartManaged.value;
          return _Row(
            label: t('autostart'),
            // A build that has no engine next to it - `flutter build` alone, say - cannot
            // register anything, and a switch that silently refuses is worse than one that
            // plainly is off.
            enabled: managed,
            control: FzToggle(
              value: FzWindow.autostart.value,
              onChanged: (bool v) => FzWindow.setAutostart(v),
            ),
          );
        },
      ),
    ],
  );

  Widget _controlFor(RowDef row, String Function(String) t) {
    final Object? value = _valueOf(row);
    switch (row.kind) {
      case RowKind.boolean:
        return FzToggle(
          value: value == true,
          onChanged: (bool v) => _commit(row.key, v),
        );
      case RowKind.integer:
        return FzNumberField(
          value: (value as int?) ?? 0,
          min: row.minValue,
          max: row.maxValue,
          onCommit: (int v) => _commit(row.key, v),
        );
      case RowKind.color:
        return FzColorRow(
          hex: (value as String?) ?? row.defaultText,
          title: t('pick_color'),
          cancelLabel: t('cancel'),
          okLabel: t('ok'),
          onCommit: (String v) => _commit(row.key, v.toUpperCase()),
        );
      case RowKind.multiline:
        return FzMultiline(
          text: (value as String?) ?? '',
          hint: 'outlook.exe',
          onCommit: (String v) => _commit(row.key, v),
        );
      case RowKind.choice:
        return FzChoice(
          labels: row.choices.map(t).toList(),
          index: (value as int?) ?? 0,
          segmented: row.segmented,
          // A flag-backed choice stores a bool, so index 1 means true - same as NumberOf()
          // in the native window.
          onChanged: (int i) => _commit(row.key, row.choiceIsFlag ? i == 1 : i),
        );
      case RowKind.readonly:
        final List<String> keys = value is List<String>
            ? value
            : <String>[row.defaultText];
        return FzKeycaps(
          keys: keys,
          hint: t('hotkey_capture'),
          onCommit: (Map<String, Object?> v) => _commit(row.key, v),
        );
      case RowKind.header:
        return const SizedBox.shrink();
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(
        FzMetrics.cardPadX,
        0,
        FzMetrics.cardPadX,
        12,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(FzRadius.base),
      ),
      // The hairline is a foreground stroke, like the specimen's inset box-shadow: a border in
      // `decoration` would eat 2px of the content width, and the 280 control band the rows are
      // measured against would come out 278.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FzRadius.base),
        border: Border.all(color: c.cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: FzMetrics.header,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.label,
    required this.enabled,
    required this.control,
    this.stacked = false,
  });

  final String label;
  final bool enabled;
  final Widget control;

  /// Label on its own line, control across the full width below it.
  final bool stacked;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final TextStyle labelStyle = TextStyle(
      color: widget.enabled ? c.ink : c.ink3,
      fontSize: 12,
      height: 1.35,
    );
    final Widget faded = AnimatedOpacity(
      duration: FzMotion.select,
      opacity: widget.enabled ? 1 : 0.45,
      child: IgnorePointer(ignoring: !widget.enabled, child: widget.control),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        height: widget.stacked ? null : FzMetrics.row,
        child: Stack(
          children: <Widget>[
            // The highlight is inset on all four sides, and the content is inset further, so the
            // band frames the label and the control instead of running under them.
            if (!widget.stacked)
              Positioned.fill(
                child: Padding(
                  padding: FzMetrics.rowInset,
                  child: AnimatedContainer(
                    duration: FzMotion.hover,
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: _hover ? c.hover : fade(c.hover),
                      borderRadius: BorderRadius.circular(FzRadius.base),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: FzMetrics.rowContentInset,
              child: widget.stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(widget.label, maxLines: 2, style: labelStyle),
                        const SizedBox(height: 8),
                        faded,
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        SizedBox(
                          width: FzMetrics.labelWidth,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.label,
                              maxLines: 2,
                              style: labelStyle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: faded,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class FzColorRow extends StatefulWidget {
  const FzColorRow({
    super.key,
    required this.hex,
    required this.title,
    required this.cancelLabel,
    required this.okLabel,
    required this.onCommit,
  });

  final String hex;

  /// The picker's heading is the row's own label; the two buttons come from the table so the
  /// dialog is bilingual like the rest of the window.
  final String title;
  final String cancelLabel;
  final String okLabel;
  final ValueChanged<String> onCommit;

  @override
  State<FzColorRow> createState() => _FzColorRowState();
}

class _FzColorRowState extends State<FzColorRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.hex.toUpperCase(),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant FzColorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hex != oldWidget.hex && !_focus.hasFocus) {
      _controller.text = widget.hex.toUpperCase();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final String text = _controller.text.trim().toUpperCase();
    if (text != widget.hex.toUpperCase()) {
      widget.onCommit(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return Row(
      // Shrink-wrapped so the row's right-align puts the "..." button on the same edge as every
      // other control; a max Row left the group hanging 50px short in a wide window.
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FzFieldFrame(
          focusNode: _focus,
          width: 228,
          child: FzFieldText(
            focusNode: _focus,
            controller: _controller,
            enabled: true,
            onSubmitted: (_) => _commit(),
            style: TextStyle(
              color: c.ink,
              fontSize: 11,
              fontFamily: 'Consolas',
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FzButton(
          label: '...',
          width: 40,
          onTap: () async {
            final String? next = await showFzColorPicker(
              context,
              hex: widget.hex,
              title: widget.title,
              cancelLabel: widget.cancelLabel,
              okLabel: widget.okLabel,
            );
            if (next != null &&
                next.toUpperCase() != widget.hex.toUpperCase()) {
              widget.onCommit(next);
            }
          },
        ),
      ],
    );
  }
}

class FzMultiline extends StatefulWidget {
  const FzMultiline({
    super.key,
    required this.text,
    required this.hint,
    required this.onCommit,
  });

  final String text;
  final String hint;
  final ValueChanged<String> onCommit;

  @override
  State<FzMultiline> createState() => _FzMultilineState();
}

class _FzMultilineState extends State<FzMultiline> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant FzMultiline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && !_focus.hasFocus) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    if (_controller.text != widget.text) {
      widget.onCommit(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return FzFieldFrame(
      focusNode: _focus,
      height: 100,
      padding: const EdgeInsets.all(12),
      child: FzFieldText(
        focusNode: _focus,
        controller: _controller,
        enabled: true,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        hintText: widget.hint,
        hintStyle: TextStyle(color: c.ink3, fontSize: 12),
        style: TextStyle(color: c.ink, fontSize: 12),
      ),
    );
  }
}

/// The engine's key names, as `HotkeyObject::get_hotkey_description` prints them.
String fzKeyName(LogicalKeyboardKey key) {
  final Map<LogicalKeyboardKey, String> named = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Del',
    LogicalKeyboardKey.insert: 'Insert',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'Page Up',
    LogicalKeyboardKey.pageDown: 'Page Down',
    LogicalKeyboardKey.arrowLeft: 'Left',
    LogicalKeyboardKey.arrowRight: 'Right',
    LogicalKeyboardKey.arrowUp: 'Up',
    LogicalKeyboardKey.arrowDown: 'Down',
    LogicalKeyboardKey.comma: ',',
    LogicalKeyboardKey.period: '.',
    LogicalKeyboardKey.slash: '/',
    LogicalKeyboardKey.backslash: '\\',
    LogicalKeyboardKey.semicolon: ';',
    LogicalKeyboardKey.quoteSingle: '\'',
    LogicalKeyboardKey.minus: '-',
    LogicalKeyboardKey.equal: '=',
    LogicalKeyboardKey.bracketLeft: '[',
    LogicalKeyboardKey.bracketRight: ']',
    LogicalKeyboardKey.backquote: '`',
  };
  final String? hit = named[key];
  if (hit != null) {
    return hit;
  }
  final String label = key.keyLabel;
  if (label.length == 1) {
    return label.toUpperCase();
  }
  // F1..F12 and the rest have no keyLabel; the debug name is the engine's spelling already.
  final String name = key.debugName ?? '';
  final RegExpMatch? function = RegExp(
    r'^f(\d+)$',
  ).firstMatch(name.toLowerCase());
  if (function != null) {
    return 'F${function.group(1)}';
  }
  return name.isEmpty ? label : name;
}

final Set<LogicalKeyboardKey> _modifiers = <LogicalKeyboardKey>{
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

/// The read-only chips, which become a capture box on click - the same contract the native
/// window had: bare modifiers only arm the box, a chord of at least one modifier plus a key
/// commits, and Esc or losing focus cancels without writing.
class FzKeycaps extends StatefulWidget {
  const FzKeycaps({
    super.key,
    required this.keys,
    required this.hint,
    this.onCommit,
  });

  final List<String> keys;
  final String hint;
  final ValueChanged<Map<String, Object?>>? onCommit;

  @override
  State<FzKeycaps> createState() => _FzKeycapsState();
}

class _FzKeycapsState extends State<FzKeycaps> {
  final FocusNode _focus = FocusNode();
  bool _capturing = false;
  List<String> _armed = const <String>[];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _capturing) {
        _cancel();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _begin() {
    if (widget.onCommit == null) {
      return;
    }
    setState(() {
      _capturing = true;
      _armed = const <String>[];
    });
    _focus.requestFocus();
  }

  void _cancel() {
    setState(() {
      _capturing = false;
      _armed = const <String>[];
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.handled;
    }
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    final bool shift = keyboard.isShiftPressed;
    final bool ctrl = keyboard.isControlPressed;
    final bool alt = keyboard.isAltPressed;
    final bool win = keyboard.isMetaPressed;
    if (_modifiers.contains(key)) {
      // Arming only: the chord needs a real key on top of the modifiers.
      setState(
        () => _armed = <String>[
          if (shift) 'shift',
          if (ctrl) 'ctrl',
          if (win) 'win',
          if (alt) 'alt',
        ],
      );
      return KeyEventResult.handled;
    }
    if (!(shift || ctrl || alt || win) || widget.onCommit == null) {
      return KeyEventResult.handled;
    }
    final Map<String, Object?> value = <String, Object?>{
      'key': fzKeyName(key),
      'shift': shift,
      'ctrl': ctrl,
      'win': win,
      'alt': alt,
    };
    _cancel();
    widget.onCommit!(value);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return AnimatedSwitcher(
      duration: FzMotion.page,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: !_capturing
          ? GestureDetector(
              key: const ValueKey<String>('chips'),
              onTap: _begin,
              child: MouseRegion(
                cursor: widget.onCommit == null
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: Row(
                  // Shrink-wrapped, so the row's right-align actually moves the group: a max
                  // Row filled the control column and the chips hung 50px short of the edge.
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < widget.keys.length; i++)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                        child: Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(FzRadius.small),
                            border: Border.all(color: c.fieldBorder, width: 1),
                          ),
                          child: Text(
                            widget.keys[i],
                            style: TextStyle(
                              color: c.ink2,
                              fontSize: 11,
                              fontFamily: 'Consolas',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : Focus(
              key: const ValueKey<String>('capture'),
              focusNode: _focus,
              onKeyEvent: _onKey,
              child: FzFieldFrame(
                focusNode: _focus,
                enabled: true,
                width: FzMetrics.fieldWidth,
                child: Center(
                  child: Text(
                    _armed.isEmpty ? widget.hint : _armed.join('+'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _armed.isEmpty ? c.ink2 : c.ink,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
