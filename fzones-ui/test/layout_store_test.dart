import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fzones_ui/layout_store.dart';
import 'package:fzones_ui/settings_model.dart';

/// Guards §6 of the contract: the field names the engine parses, and the read-modify-write
/// behaviour of the two files the engine also touches.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fzstore');
    FzPaths.overrideDir = dir.path;
  });

  tearDown(() {
    FzPaths.overrideDir = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String path(String name) => [dir.path, name].join(Platform.pathSeparator);

  void write(String name, Object json) =>
      File(path(name)).writeAsStringSync(jsonEncode(json));

  test('a grid custom layout round-trips through the frozen field names', () {
    final FzCustomLayout original = FzCustomLayout(
      name: 'Two columns',
      rows: 1,
      columns: 2,
      rowsPercentage: <int>[10000],
      columnsPercentage: <int>[5000, 5000],
      cellChildMap: <List<int>>[
        <int>[0, 1]
      ],
      showSpacing: false,
      spacing: 24,
    );
    FzStore.writeCustomLayouts(<FzCustomLayout>[original]);

    final Map<String, dynamic> raw = jsonDecode(File(path('custom-layouts.json')).readAsStringSync())
        as Map<String, dynamic>;
    expect(raw.keys.toList(), <String>['custom-layouts']);

    final Map<String, dynamic> entry = (raw['custom-layouts'] as List<dynamic>).first as Map<String, dynamic>;
    expect(entry.keys.toSet(), <String>{'uuid', 'name', 'type', 'info'});
    expect(entry['type'], 'grid');
    final Map<String, dynamic> info = entry['info'] as Map<String, dynamic>;
    expect(info['rows'], 1);
    expect(info['columns'], 2);
    expect(info['show-spacing'], false);
    expect(info['spacing'], 24);
    expect(info['rows-percentage'], <dynamic>[10000]);
    expect(info['columns-percentage'], <dynamic>[5000, 5000]);
    expect(info['cell-child-map'], <dynamic>[
      <dynamic>[0, 1]
    ]);
    expect(info.containsKey('sensitivity-radius'), isTrue);

    final List<FzCustomLayout> back = FzStore.readCustomLayouts();
    expect(back, hasLength(1));
    expect(back.first.name, 'Two columns');
    expect(back.first.cellChildMap, <List<int>>[
      <int>[0, 1]
    ]);
    expect(back.first.showSpacing, isFalse);
  });

  test('a canvas custom layout uses X/Y/width/height, not left/top', () {
    FzStore.writeCustomLayouts(<FzCustomLayout>[
      FzCustomLayout(
        name: 'Triple',
        isCanvas: true,
        referenceWidth: 2560,
        referenceHeight: 1440,
        canvasZones: <FzRect>[const FzRect(0, 0, 1280, 1440), const FzRect(1280, 0, 2560, 720)],
      ),
    ]);

    final Map<String, dynamic> raw =
        jsonDecode(File(path('custom-layouts.json')).readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> info =
        ((raw['custom-layouts'] as List<dynamic>).first as Map<String, dynamic>)['info']
            as Map<String, dynamic>;
    expect(info['ref-width'], 2560);
    expect(info['ref-height'], 1440);
    expect((info['zones'] as List<dynamic>).first, <String, dynamic>{'X': 0, 'Y': 0, 'width': 1280, 'height': 1440});

    final FzCustomLayout back = FzStore.readCustomLayouts().first;
    expect(back.canvasZones.first.right, 1280);
    expect(back.zoneCount, 2);
  });

  test('applying a layout replaces only that monitor and leaves the others alone', () {
    write('applied-layouts.json', <String, dynamic>{
      'applied-layouts': <dynamic>[
        <String, dynamic>{
          'device': <String, dynamic>{'monitor': 'A', 'monitor-instance': 'i1', 'serial-number': 's1', 'monitor-number': 1, 'virtual-desktop': 'vd'},
          'applied-layout': FzLayout(type: FzLayoutType.rows, zoneCount: 3).toJson(),
        },
        <String, dynamic>{
          'device': <String, dynamic>{'monitor': 'B', 'monitor-instance': 'i2', 'serial-number': 's2', 'monitor-number': 2, 'virtual-desktop': 'vd'},
          'applied-layout': FzLayout(type: FzLayoutType.grid, zoneCount: 4).toJson(),
        },
      ],
    });

    const FzDevice a = FzDevice(monitor: 'A', instance: 'i1', serial: 's1', number: 1, virtualDesktop: 'vd');
    FzStore.applyLayoutToMonitor(a, FzLayout(type: FzLayoutType.columns, zoneCount: 5));

    final List<MapEntry<FzDevice, FzLayout>> back = FzStore.readAppliedLayouts();
    expect(back, hasLength(2), reason: 'no duplicate entry for monitor A');
    expect(back.firstWhere((MapEntry<FzDevice, FzLayout> e) => e.key.monitor == 'A').value.type,
        FzLayoutType.columns);
    expect(back.firstWhere((MapEntry<FzDevice, FzLayout> e) => e.key.monitor == 'A').value.zoneCount, 5);
    expect(back.firstWhere((MapEntry<FzDevice, FzLayout> e) => e.key.monitor == 'B').value.type,
        FzLayoutType.grid, reason: 'monitor B survives untouched');
  });

  test('quick-switch digits and orientation defaults are read-modify-write', () {
    FzStore.writeLayoutHotkeys(<String, int>{'{AAA}': 1, '{BBB}': 2});
    FzStore.writeLayoutHotkeys(<String, int>{'{AAA}': 3, '{BBB}': 2});
    expect(FzStore.readLayoutHotkeys(), <String, int>{'{AAA}': 3, '{BBB}': 2});

    FzStore.writeDefaultLayout('horizontal', FzLayout(type: FzLayoutType.rows));
    FzStore.writeDefaultLayout('vertical', FzLayout(type: FzLayoutType.columns));
    FzStore.writeDefaultLayout('horizontal', FzLayout(type: FzLayoutType.grid));

    final Map<String, FzLayout> defaults = FzStore.readDefaultLayouts();
    expect(defaults, hasLength(2), reason: 'one entry per orientation, no duplicates');
    expect(defaults['horizontal']!.type, FzLayoutType.grid);
    expect(defaults['vertical']!.type, FzLayoutType.columns);
  });

  test('the engine editor-parameters.json parses, including its two differently named fields', () {
    // This one deliberately reads the real folder rather than the temp one.
    final String? saved = FzPaths.overrideDir;
    FzPaths.overrideDir = null;
    try {
      final File real = File(<String>[
        Platform.environment['LOCALAPPDATA'] ?? '',
        'FZones',
        'FancyZones',
        'editor-parameters.json',
      ].join(Platform.pathSeparator));
      if (!real.existsSync()) {
        return; // Nothing to compare against before the app has run once.
      }

      final FzEditorParameters params = FzStore.readEditorParameters();
      expect(params.monitors, isNotEmpty);
      for (final FzMonitorInfo m in params.monitors) {
        expect(m.device.monitor, isNotEmpty);
        expect(m.device.instance, isNotEmpty, reason: 'monitor-instance-id was read');
        expect(m.fullArea.width, greaterThan(0));
      }
    } finally {
      FzPaths.overrideDir = saved;
    }
  });
}
