import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rack_topology.dart';

/// Owns the operator-configured rack -> unit -> port layout and persists it
/// locally (SharedPreferences). The app is the source of truth for the
/// topology; only the flat box/slot + a human label get pushed to the bridge
/// when a sensor is assigned.
class TopologyService extends ChangeNotifier {
  static const String _prefsKey = 'rack_topology_json';

  RackTopology _topology = RackTopology();
  bool _loaded = false;

  List<Rack> get racks => List.unmodifiable(_topology.racks);
  bool get isLoaded => _loaded;
  bool get isEmpty => _topology.racks.isEmpty;

  // ---- unique id helper -----------------------------------------------------
  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  // ---- persistence ----------------------------------------------------------
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _topology = RackTopology.fromJsonString(prefs.getString(_prefsKey) ?? '');
    } catch (_) {
      _topology = RackTopology();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _topology.toJsonString());
    } catch (_) {
      // best-effort; UI already updated
    }
  }

  // ---- racks ----------------------------------------------------------------
  void addRack(String name) {
    final n = name.trim().isEmpty ? 'Rack ${_topology.racks.length + 1}' : name.trim();
    _topology.racks.add(Rack(id: _newId(), name: n));
    _save();
  }

  void renameRack(String rackId, String name) {
    final r = _rack(rackId);
    if (r != null && name.trim().isNotEmpty) {
      r.name = name.trim();
      _save();
    }
  }

  void removeRack(String rackId) {
    _topology.racks.removeWhere((r) => r.id == rackId);
    _save();
  }

  // ---- units ----------------------------------------------------------------
  void addUnit(String rackId, [String? name]) {
    final r = _rack(rackId);
    if (r == null) return;
    final n = (name == null || name.trim().isEmpty)
        ? 'Unit ${r.units.length + 1}'
        : name.trim();
    r.units.add(RackUnit(id: _newId(), name: n));
    _save();
  }

  void removeUnit(String rackId, String unitId) {
    final r = _rack(rackId);
    if (r == null) return;
    r.units.removeWhere((u) => u.id == unitId);
    _save();
  }

  // ---- ports ----------------------------------------------------------------
  void addPort(String rackId, String unitId, PortType type) {
    final u = _unit(rackId, unitId);
    if (u == null) return;
    final count = u.ports.where((p) => p.type == type).length + 1;
    u.ports.add(Port(
      id: _newId(),
      type: type,
      label: '${type.label} $count',
      box: _topology.nextBoxId(),
    ));
    _save();
  }

  void removePort(String portId) {
    for (final r in _topology.racks) {
      for (final u in r.units) {
        u.ports.removeWhere((p) => p.id == portId);
      }
    }
    _save();
  }

  // ---- assignment -----------------------------------------------------------
  void assignEui(String portId, String? eui) {
    final p = portById(portId);
    if (p == null) return;
    final e = eui?.trim().toLowerCase();
    // A device can only live in one place: clear it from any other port first.
    if (e != null && e.isNotEmpty) {
      for (final r in _topology.racks) {
        for (final u in r.units) {
          for (final other in u.ports) {
            if (other.id != portId && other.assignedEui == e) {
              other.assignedEui = null;
            }
          }
        }
      }
    }
    p.assignedEui = (e == null || e.isEmpty) ? null : e;
    _save();
  }

  // ---- lookups --------------------------------------------------------------
  Rack? _rack(String rackId) {
    for (final r in _topology.racks) {
      if (r.id == rackId) return r;
    }
    return null;
  }

  RackUnit? _unit(String rackId, String unitId) {
    final r = _rack(rackId);
    if (r == null) return null;
    for (final u in r.units) {
      if (u.id == unitId) return u;
    }
    return null;
  }

  Port? portById(String portId) {
    for (final r in _topology.racks) {
      for (final u in r.units) {
        for (final p in u.ports) {
          if (p.id == portId) return p;
        }
      }
    }
    return null;
  }

  /// Human-readable location for a port, e.g. "Rack A / Unit 1 / Intake 1".
  String labelForPort(String portId) {
    for (final r in _topology.racks) {
      for (final u in r.units) {
        for (final p in u.ports) {
          if (p.id == portId) return '${r.name} / ${u.name} / ${p.label}';
        }
      }
    }
    return '';
  }
}
