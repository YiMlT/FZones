import 'dart:io';

import 'design.dart';
import 'settings_model.dart';
import 'settings_writer.dart';

/// The two switches that belong to the UI rather than to the engine: theme and language.
///
/// They live in `ui-settings.json` next to `settings.json`. The engine never reads that file, so
/// writing it cannot make it reload anything. The two windows do talk through it: each one watches
/// it and follows a change the other one made.
class FzUiSettings {
  const FzUiSettings({
    this.theme = FzThemeMode.system,
    this.language = FzLangMode.system,
  });

  final FzThemeMode theme;
  final FzLangMode language;

  static FzUiSettings load() {
    final Map<String, Object?> root =
        SettingsWriter.readRoot(FzPaths.uiSettingsJson);
    return FzUiSettings(
      theme: _named(FzThemeMode.values, root['theme'], FzThemeMode.system),
      language: _named(FzLangMode.values, root['language'], FzLangMode.system),
    );
  }

  static T _named<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final T value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return fallback;
  }

  FzUiSettings withTheme(FzThemeMode next) =>
      FzUiSettings(theme: next, language: language);

  FzUiSettings withLanguage(FzLangMode next) =>
      FzUiSettings(theme: theme, language: next);

  /// Value equality, because the window that wrote the file also gets its own watcher event and
  /// must not rebuild the theme it just asked for.
  @override
  bool operator ==(Object other) =>
      other is FzUiSettings &&
      other.theme == theme &&
      other.language == language;

  @override
  int get hashCode => Object.hash(theme, language);

  /// Atomic like every other write here: a temp file plus a rename, so a window watching the
  /// directory never reads a half-written document.
  void save() {
    try {
      final Directory dir = Directory(FzPaths.fancyZonesDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      SettingsWriter.writeAtomic(FzPaths.uiSettingsJson, <String, Object?>{
        'theme': theme.name,
        'language': language.name,
      });
    } catch (_) {
      // A read-only profile or a locked directory costs a setting, not a crash: the value still
      // holds for this run.
    }
  }
}
