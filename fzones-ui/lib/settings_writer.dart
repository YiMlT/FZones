import 'dart:convert';
import 'dart:io';

/// Writes settings.json the way documents/designs/fzones_ipc_contract.md §5 demands:
/// read-modify-write, then an atomic replace.
///
/// Dart's [File.rename] maps to MoveFileEx with MOVEFILE_REPLACE_EXISTING on Windows, so a
/// sibling temp file plus a rename is a real atomic swap - the engine's FileWatcher can never
/// catch the file half-written, which would parse as "no settings" and silently reset defaults.
class SettingsWriter {
  /// The whole document as the engine wrote it, unknown keys included.
  static Map<String, Object?> readRoot(String path) {
    try {
      final File file = File(path);
      if (!file.existsSync()) {
        return <String, Object?>{};
      }
      final Object? decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
    } catch (_) {
      // A corrupt file is not ours to fix here; the caller decides what to do.
      return <String, Object?>{};
    }
  }

  static Map<String, Object?> _properties(Map<String, Object?> root) {
    final Object? props = root['properties'];
    return props is Map ? props.cast<String, Object?>() : <String, Object?>{};
  }

  /// Changes one key and leaves every other key exactly where the engine put it.
  /// Order is preserved because Dart maps keep insertion order, so the diff stays one line.
  static void writeValue(String path, String key, Object? value) {
    final Map<String, Object?> root = readRoot(path);
    final Map<String, Object?> props = _properties(root);
    props[key] = <String, Object?>{'value': value};
    root['properties'] = props;
    root['name'] ??= 'FancyZones';
    root['version'] ??= '1.0';
    writeAtomic(path, root);
  }

  /// Compact JSON, matching what JsonObject::Stringify() produces on the C++ side.
  static String encode(Map<String, Object?> root) => jsonEncode(root);

  /// The file as it is on disk, for tests that need a byte comparison.
  static String raw(String path) {
    final File file = File(path);
    return file.existsSync() ? file.readAsStringSync() : '';
  }

  static void writeAtomic(String path, Map<String, Object?> root) {
    final String text = encode(root);
    final File temp = File('$path.tmp');
    temp.writeAsStringSync(text, flush: true);
    temp.renameSync(path);
  }
}
