import 'dart:convert';
import 'dart:io';

import 'package:fzones_ui/settings_model.dart';
import 'package:fzones_ui/settings_writer.dart';

/// Writes one settings key through the same SettingsWriter the app uses, so the engine-level
/// end-to-end test exercises the shipped write path rather than a copy of it.
///
///   dart run tool/set_setting.dart fancyzones_shiftDrag false
///   dart run tool/set_setting.dart fancyzones_editor_hotkey @hotkey.json
///
/// A value that starts with @ is read from that file, which is the only reliable way to hand
/// an object literal through a Windows shell without its quotes being eaten.
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: set_setting.dart <key> <json-value|@file>');
    exit(2);
  }

  final String key = args[0];
  final String raw = args[1].startsWith('@')
      ? File(args[1].substring(1)).readAsStringSync()
      : args[1];
  final Object? value = jsonDecode(raw);

  try {
    SettingsWriter.writeValue(FzPaths.settingsJson, key, value);
    stdout.writeln('wrote $key = $raw');
  } catch (e) {
    stderr.writeln('write failed: $e');
    exit(1);
  }
}
