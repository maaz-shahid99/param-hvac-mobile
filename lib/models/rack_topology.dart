import 'dart:convert';

/// A probe position within a server unit.
/// Intake = left / cold-aisle / blower-fan side; Exhaust = right / hot-aisle /
/// blower-out side. Slot "A" maps to intake, "B" to exhaust so the legacy
/// box-grid dashboard keeps working.
enum PortType { intake, exhaust }

extension PortTypeX on PortType {
  String get label => this == PortType.intake ? 'Intake' : 'Exhaust';
  String get slot => this == PortType.intake ? 'A' : 'B';
  String get key => name; // for JSON
  static PortType fromKey(String? k) =>
      k == 'exhaust' ? PortType.exhaust : PortType.intake;
}

/// A single probe/port on a unit, optionally assigned to one probe of a sensor.
class Port {
  final String id;
  PortType type;
  String label; // e.g. "Intake 1"
  int box; // unique flat box id -> keeps the legacy 3D grid working
  String? assignedEui; // null until a sensor is mapped here
  // Which DS18B20 probe of [assignedEui] feeds this port, identified by its
  // 64-bit ROM (plug/unplug-stable). null = whole-sensor (legacy) mapping.
  String? assignedProbeRom;
  String? probeLabel; // friendly label shown in the UI, e.g. "Probe 3"

  Port({
    required this.id,
    required this.type,
    required this.label,
    required this.box,
    this.assignedEui,
    this.assignedProbeRom,
    this.probeLabel,
  });

  String get slot => type.slot;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.key,
        'label': label,
        'box': box,
        'assignedEui': assignedEui,
        'assignedProbeRom': assignedProbeRom,
        'probeLabel': probeLabel,
      };

  factory Port.fromJson(Map<String, dynamic> j) => Port(
        id: j['id'] as String,
        type: PortTypeX.fromKey(j['type'] as String?),
        label: j['label'] as String? ?? 'Port',
        box: (j['box'] as num?)?.toInt() ?? 0,
        assignedEui: j['assignedEui'] as String?,
        assignedProbeRom: j['assignedProbeRom'] as String?,
        probeLabel: j['probeLabel'] as String?,
      );
}

/// A server unit inside a rack; holds an arbitrary number of ports.
class RackUnit {
  final String id;
  String name; // e.g. "Unit 1"
  List<Port> ports;

  RackUnit({required this.id, required this.name, List<Port>? ports})
      : ports = ports ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ports': ports.map((p) => p.toJson()).toList(),
      };

  factory RackUnit.fromJson(Map<String, dynamic> j) => RackUnit(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Unit',
        ports: (j['ports'] as List? ?? [])
            .map((e) => Port.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A rack; holds an arbitrary number of units.
class Rack {
  final String id;
  String name; // e.g. "Rack A"
  List<RackUnit> units;

  Rack({required this.id, required this.name, List<RackUnit>? units})
      : units = units ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'units': units.map((u) => u.toJson()).toList(),
      };

  factory Rack.fromJson(Map<String, dynamic> j) => Rack(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Rack',
        units: (j['units'] as List? ?? [])
            .map((e) => RackUnit.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The whole operator-configured layout.
class RackTopology {
  List<Rack> racks;

  RackTopology({List<Rack>? racks}) : racks = racks ?? [];

  /// Next unused flat box id (>= 1) across every port, for the legacy grid.
  int nextBoxId() {
    var max = 0;
    for (final r in racks) {
      for (final u in r.units) {
        for (final p in u.ports) {
          if (p.box > max) max = p.box;
        }
      }
    }
    return max + 1;
  }

  String toJsonString() => jsonEncode({
        'racks': racks.map((r) => r.toJson()).toList(),
      });

  factory RackTopology.fromJsonString(String s) {
    if (s.isEmpty) return RackTopology();
    final j = jsonDecode(s) as Map<String, dynamic>;
    return RackTopology(
      racks: (j['racks'] as List? ?? [])
          .map((e) => Rack.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
