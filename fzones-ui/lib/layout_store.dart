/// Mirrors FZones/LayoutStore.cpp. Every field name below is frozen by
/// documents/designs/fzones_ipc_contract.md §6: the engine parses these files with the same
/// names, and a typo does not fail loudly, it silently falls back to a default.
library;

import 'dart:io';
import 'dart:math' as math;

import 'settings_model.dart' show FzPaths;
import 'settings_writer.dart' show SettingsWriter;

int _int(Map<String, dynamic> o, String k, int fallback) {
  final Object? v = o[k];
  if (v is int) return v;
  if (v is double) return v.round();
  return fallback;
}

bool _bool(Map<String, dynamic> o, String k, bool fallback) {
  final Object? v = o[k];
  return v is bool ? v : fallback;
}

String _str(Map<String, dynamic> o, String k) {
  final Object? v = o[k];
  return v is String ? v : '';
}

List<int> _intArray(Map<String, dynamic> o, String k) {
  final Object? v = o[k];
  if (v is! List) return <int>[];
  return v.whereType<num>().map((num n) => n.round()).toList();
}

Map<String, dynamic> _obj(Map<String, dynamic> o, String k) {
  final Object? v = o[k];
  return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
}

List<dynamic> _arr(Map<String, dynamic> o, String k) {
  final Object? v = o[k];
  return v is List ? v : <dynamic>[];
}

/// RECT semantics, because the canvas layout stores X/Y/width/height and everything else
/// thinks in left/top/right/bottom.
class FzRect {
  const FzRect(this.left, this.top, this.right, this.bottom);
  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;

  static FzRect fromXYWH(Map<String, dynamic> o) {
    final int x = _int(o, 'X', 0);
    final int y = _int(o, 'Y', 0);
    return FzRect(x, y, x + _int(o, 'width', 0), y + _int(o, 'height', 0));
  }

  Map<String, dynamic> toXYWH() =>
      <String, dynamic>{'X': left, 'Y': top, 'width': width, 'height': height};

  @override
  String toString() => '[$left,$top,$right,$bottom]';

  @override
  bool operator ==(Object other) =>
      other is FzRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

class FzUuid {
  static final math.Random _rng = math.Random();
  static const String nullUuid = '{00000000-0000-0000-0000-000000000000}';

  /// Same shape StringFromCLSID produces, braces and uppercase included.
  static String newUuid() {
    String hex(int n) {
      final StringBuffer b = StringBuffer();
      for (int i = 0; i < n; i++) {
        b.write(_rng.nextInt(16).toRadixString(16).toUpperCase());
      }
      return b.toString();
    }

    return '{${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}}';
  }

  static String normalize(String raw) => raw.isEmpty ? nullUuid : raw.toUpperCase();
}

enum FzLayoutType { blank, focus, columns, rows, grid, priorityGrid, custom }

const Map<FzLayoutType, String> kLayoutTypeNames = <FzLayoutType, String>{
  FzLayoutType.blank: 'blank',
  FzLayoutType.focus: 'focus',
  FzLayoutType.columns: 'columns',
  FzLayoutType.rows: 'rows',
  FzLayoutType.grid: 'grid',
  FzLayoutType.priorityGrid: 'priority-grid',
  FzLayoutType.custom: 'custom',
};

FzLayoutType fzLayoutTypeFromName(String name) {
  for (final MapEntry<FzLayoutType, String> e in kLayoutTypeNames.entries) {
    if (e.value == name) return e.key;
  }
  return FzLayoutType.blank;
}

class FzLayout {
  FzLayout({
    this.uuid = FzUuid.nullUuid,
    this.type = FzLayoutType.priorityGrid,
    this.showSpacing = true,
    this.spacing = 16,
    this.zoneCount = 3,
    this.sensitivityRadius = 20,
  });

  String uuid;
  FzLayoutType type;
  bool showSpacing;
  int spacing;
  int zoneCount;
  int sensitivityRadius;

  factory FzLayout.fromJson(Map<String, dynamic> o) => FzLayout(
        uuid: FzUuid.normalize(_str(o, 'uuid')),
        type: fzLayoutTypeFromName(_str(o, 'type')),
        showSpacing: _bool(o, 'show-spacing', true),
        spacing: _int(o, 'spacing', 16),
        zoneCount: _int(o, 'zone-count', 3),
        sensitivityRadius: _int(o, 'sensitivity-radius', 20),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uuid': uuid,
        'type': kLayoutTypeNames[type],
        'show-spacing': showSpacing,
        'spacing': spacing,
        'zone-count': zoneCount,
        'sensitivity-radius': sensitivityRadius,
      };
}

class FzCustomLayout {
  FzCustomLayout({
    String? uuid,
    this.name = '',
    this.isCanvas = false,
    this.rows = 1,
    this.columns = 1,
    List<int>? rowsPercentage,
    List<int>? columnsPercentage,
    List<List<int>>? cellChildMap,
    List<FzRect>? canvasZones,
    this.referenceWidth = 0,
    this.referenceHeight = 0,
    this.showSpacing = true,
    this.spacing = 16,
    this.sensitivityRadius = 20,
  })  : uuid = uuid ?? FzUuid.newUuid(),
        rowsPercentage = rowsPercentage ?? <int>[],
        columnsPercentage = columnsPercentage ?? <int>[],
        cellChildMap = cellChildMap ?? <List<int>>[],
        canvasZones = canvasZones ?? <FzRect>[];

  String uuid;
  String name;
  bool isCanvas;
  int rows;
  int columns;
  List<int> rowsPercentage;
  List<int> columnsPercentage;
  List<List<int>> cellChildMap;
  List<FzRect> canvasZones;
  int referenceWidth;
  int referenceHeight;
  bool showSpacing;
  int spacing;
  int sensitivityRadius;

  int get zoneCount {
    if (isCanvas) return canvasZones.length;
    int highest = -1;
    for (final List<int> row in cellChildMap) {
      for (final int cell in row) {
        highest = math.max(highest, cell);
      }
    }
    return highest + 1;
  }

  factory FzCustomLayout.fromJson(Map<String, dynamic> entry) {
    final FzCustomLayout layout = FzCustomLayout(
      uuid: FzUuid.normalize(_str(entry, 'uuid')),
      name: _str(entry, 'name'),
    );
    final Map<String, dynamic> info = _obj(entry, 'info');
    layout.sensitivityRadius = _int(info, 'sensitivity-radius', 20);

    if (_str(entry, 'type') == 'canvas') {
      layout.isCanvas = true;
      layout.referenceWidth = _int(info, 'ref-width', 0);
      layout.referenceHeight = _int(info, 'ref-height', 0);
      for (final Object? zone in _arr(info, 'zones')) {
        if (zone is Map) {
          layout.canvasZones.add(FzRect.fromXYWH(zone.cast<String, dynamic>()));
        }
      }
    } else {
      layout.rows = _int(info, 'rows', 1);
      layout.columns = _int(info, 'columns', 1);
      layout.rowsPercentage = _intArray(info, 'rows-percentage');
      layout.columnsPercentage = _intArray(info, 'columns-percentage');
      layout.showSpacing = _bool(info, 'show-spacing', true);
      layout.spacing = _int(info, 'spacing', 16);
      for (final Object? row in _arr(info, 'cell-child-map')) {
        if (row is List) {
          layout.cellChildMap.add(row.whereType<num>().map((num n) => n.round()).toList());
        }
      }
    }
    return layout;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> info = <String, dynamic>{'sensitivity-radius': sensitivityRadius};
    if (isCanvas) {
      info['ref-width'] = referenceWidth;
      info['ref-height'] = referenceHeight;
      info['zones'] = canvasZones.map((FzRect r) => r.toXYWH()).toList();
    } else {
      info['rows'] = rows;
      info['columns'] = columns;
      info['show-spacing'] = showSpacing;
      info['spacing'] = spacing;
      info['rows-percentage'] = rowsPercentage;
      info['columns-percentage'] = columnsPercentage;
      info['cell-child-map'] = cellChildMap;
    }
    return <String, dynamic>{
      'uuid': uuid,
      'name': name,
      'type': isCanvas ? 'canvas' : 'grid',
      'info': info,
    };
  }
}

class FzDevice {
  const FzDevice({
    this.monitor = '',
    this.instance = '',
    this.serial = '',
    this.number = 0,
    this.virtualDesktop = '',
  });

  final String monitor;
  final String instance;
  final String serial;
  final int number;
  final String virtualDesktop;

  factory FzDevice.fromJson(Map<String, dynamic> o) {
    // editor-parameters.json names these two fields differently from applied-layouts.json.
    final String instance = _str(o, 'monitor-instance');
    final String serial = _str(o, 'serial-number');
    return FzDevice(
      monitor: _str(o, 'monitor'),
      instance: instance.isEmpty ? _str(o, 'monitor-instance-id') : instance,
      serial: serial.isEmpty ? _str(o, 'monitor-serial-number') : serial,
      number: _int(o, 'monitor-number', 0),
      virtualDesktop: _str(o, 'virtual-desktop'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'monitor': monitor,
        'monitor-instance': instance,
        'serial-number': serial,
        'monitor-number': number,
        'virtual-desktop': virtualDesktop,
      };

  bool sameAs(FzDevice other) =>
      monitor == other.monitor &&
      instance == other.instance &&
      serial == other.serial &&
      number == other.number &&
      virtualDesktop == other.virtualDesktop;
}

class FzMonitorInfo {
  const FzMonitorInfo({
    required this.device,
    this.dpi = 96,
    this.workArea = const FzRect(0, 0, 0, 0),
    this.fullArea = const FzRect(0, 0, 0, 0),
    this.selected = false,
  });

  final FzDevice device;
  final int dpi;
  final FzRect workArea;
  final FzRect fullArea;
  final bool selected;

  /// The engine picks the orientation from the monitor's own rect, not the work area.
  bool get vertical => fullArea.height > fullArea.width;

  factory FzMonitorInfo.fromJson(Map<String, dynamic> o) {
    final int left = _int(o, 'left-coordinate', 0);
    final int top = _int(o, 'top-coordinate', 0);
    return FzMonitorInfo(
      device: FzDevice.fromJson(o),
      dpi: _int(o, 'dpi', 96),
      workArea: FzRect(left, top, left + _int(o, 'work-area-width', 0),
          top + _int(o, 'work-area-height', 0)),
      fullArea: FzRect(left, top, left + _int(o, 'monitor-width', 0),
          top + _int(o, 'monitor-height', 0)),
      selected: _bool(o, 'is-selected', false),
    );
  }
}

class FzEditorParameters {
  const FzEditorParameters({
    this.processId = 0,
    this.spanAcrossMonitors = false,
    this.monitors = const <FzMonitorInfo>[],
  });

  final int processId;
  final bool spanAcrossMonitors;
  final List<FzMonitorInfo> monitors;

  static const FzEditorParameters empty = FzEditorParameters();
}

/// Read/write for the six files the editor owns. Writes go through SettingsWriter so they are
/// atomic for the same reason settings.json is: the engine watches these files too.
class FzStore {
  static String _path(String name) => FzPaths.fancyZonesDir + Platform.pathSeparator + name;

  static Map<String, dynamic> _root(String name) =>
      SettingsWriter.readRoot(_path(name));

  static void _writeRoot(String name, String arrayName, List<dynamic> array) {
    SettingsWriter.writeAtomic(_path(name), <String, dynamic>{arrayName: array});
  }

  // ---- editor-parameters.json (engine writes it; the editor only reads) ----

  static FzEditorParameters readEditorParameters() {
    final Map<String, dynamic> root = _root('editor-parameters.json');
    if (root.isEmpty) return FzEditorParameters.empty;

    final List<FzMonitorInfo> monitors = <FzMonitorInfo>[];
    for (final Object? item in _arr(root, 'monitors')) {
      if (item is Map) monitors.add(FzMonitorInfo.fromJson(item.cast<String, dynamic>()));
    }
    return FzEditorParameters(
      processId: _int(root, 'process-id', 0),
      spanAcrossMonitors: _bool(root, 'span-zones-across-monitors', false),
      monitors: monitors,
    );
  }

  // ---- custom-layouts.json ----

  static List<FzCustomLayout> readCustomLayouts() {
    final Map<String, dynamic> root = _root('custom-layouts.json');
    final List<FzCustomLayout> result = <FzCustomLayout>[];
    for (final Object? item in _arr(root, 'custom-layouts')) {
      if (item is Map) {
        result.add(FzCustomLayout.fromJson(item.cast<String, dynamic>()));
      }
    }
    return result;
  }

  static void writeCustomLayouts(List<FzCustomLayout> layouts) {
    _writeRoot('custom-layouts.json', 'custom-layouts',
        layouts.map((FzCustomLayout l) => l.toJson()).toList());
  }

  // ---- applied-layouts.json (the engine writes it too, so replace in place) ----

  static List<MapEntry<FzDevice, FzLayout>> readAppliedLayouts() {
    final Map<String, dynamic> root = _root('applied-layouts.json');
    final List<MapEntry<FzDevice, FzLayout>> result = <MapEntry<FzDevice, FzLayout>>[];
    for (final Object? item in _arr(root, 'applied-layouts')) {
      if (item is! Map) continue;
      final Map<String, dynamic> entry = item.cast<String, dynamic>();
      if (entry['device'] is! Map || entry['applied-layout'] is! Map) continue;
      result.add(MapEntry<FzDevice, FzLayout>(
        FzDevice.fromJson((entry['device'] as Map).cast<String, dynamic>()),
        FzLayout.fromJson((entry['applied-layout'] as Map).cast<String, dynamic>()),
      ));
    }
    return result;
  }

  /// Only the target monitor's entry is replaced; every other monitor survives untouched.
  static void applyLayoutToMonitor(FzDevice device, FzLayout layout) {
    final List<dynamic> array = <dynamic>[];
    bool replaced = false;
    for (final Object? item in _arr(_root('applied-layouts.json'), 'applied-layouts')) {
      if (item is! Map) continue;
      final Map<String, dynamic> entry = item.cast<String, dynamic>();
      final bool same = entry['device'] is Map &&
          FzDevice.fromJson((entry['device'] as Map).cast<String, dynamic>()).sameAs(device);
      if (same) {
        if (!replaced) {
          array.add(<String, dynamic>{
            'device': device.toJson(),
            'applied-layout': layout.toJson(),
          });
          replaced = true;
        }
        continue;
      }
      array.add(entry);
    }

    if (!replaced) {
      array.add(<String, dynamic>{
        'device': device.toJson(),
        'applied-layout': layout.toJson(),
      });
    }
    _writeRoot('applied-layouts.json', 'applied-layouts', array);
  }

  // ---- layout-templates.json ----

  static List<FzLayout> readTemplates() {
    final List<FzLayout> result = <FzLayout>[];
    for (final Object? item in _arr(_root('layout-templates.json'), 'layout-templates')) {
      if (item is Map) result.add(FzLayout.fromJson(item.cast<String, dynamic>()));
    }
    return result;
  }

  static void writeTemplates(List<FzLayout> templates) {
    _writeRoot('layout-templates.json', 'layout-templates',
        templates.map((FzLayout l) => l.toJson()).toList());
  }

  // ---- layout-hotkeys.json (stores the digit 0-9, not a virtual key code) ----

  static Map<String, int> readLayoutHotkeys() {
    final Map<String, int> result = <String, int>{};
    for (final Object? item in _arr(_root('layout-hotkeys.json'), 'layout-hotkeys')) {
      if (item is! Map) continue;
      final Map<String, dynamic> entry = item.cast<String, dynamic>();
      final String id = FzUuid.normalize(_str(entry, 'layout-id'));
      if (id != FzUuid.nullUuid) result[id] = _int(entry, 'key', 0);
    }
    return result;
  }

  static void writeLayoutHotkeys(Map<String, int> hotkeys) {
    _writeRoot(
      'layout-hotkeys.json',
      'layout-hotkeys',
      hotkeys.entries
          .map((MapEntry<String, int> e) =>
              <String, dynamic>{'layout-id': e.key, 'key': e.value})
          .toList(),
    );
  }

  // ---- default-layouts.json ----

  static Map<String, FzLayout> readDefaultLayouts() {
    final Map<String, FzLayout> result = <String, FzLayout>{};
    for (final Object? item in _arr(_root('default-layouts.json'), 'default-layouts')) {
      if (item is! Map) continue;
      final Map<String, dynamic> entry = item.cast<String, dynamic>();
      if (entry['layout'] is! Map) continue;
      final String orientation =
          _str(entry, 'monitor-configuration') == 'vertical' ? 'vertical' : 'horizontal';
      result[orientation] = FzLayout.fromJson((entry['layout'] as Map).cast<String, dynamic>());
    }
    return result;
  }

  static void writeDefaultLayout(String orientation, FzLayout layout) {
    final List<dynamic> array = <dynamic>[];
    bool replaced = false;
    for (final Object? item in _arr(_root('default-layouts.json'), 'default-layouts')) {
      if (item is! Map) continue;
      final Map<String, dynamic> entry = item.cast<String, dynamic>();
      final bool same =
          (_str(entry, 'monitor-configuration') == 'vertical') == (orientation == 'vertical');
      if (same) {
        if (!replaced) {
          array.add(<String, dynamic>{'monitor-configuration': orientation, 'layout': layout.toJson()});
          replaced = true;
        }
        continue;
      }
      array.add(entry);
    }
    if (!replaced) {
      array.add(<String, dynamic>{'monitor-configuration': orientation, 'layout': layout.toJson()});
    }
    _writeRoot('default-layouts.json', 'default-layouts', array);
  }
}
