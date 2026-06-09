import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rack_topology.dart';
import 'cloud_api.dart';

/// Owns the operator-configured rack -> unit -> port layout.
///
/// The cloud (AWS) is the source of truth once signed in, so the layout follows
/// the organization across phones and reinstalls; SharedPreferences is kept as a
/// local cache for instant load and offline use. When [_cloud] is bound, every
/// mutation is pushed to the cloud (best-effort) and the cloud rebuilds its
/// sensor map for the threshold engine.
class TopologyService extends ChangeNotifier {
  static const String _prefsKey = 'rack_topology_json';

  RackTopology _topology = RackTopology();
  bool _loaded = false;
  CloudApi? _cloud;
  bool _syncing = false;

  // Push coordination: coalesce rapid edits (debounce) and never let two PUTs
  // overlap (serialize) — overlapping/out-of-order PUTs were losing assignments.
  Timer? _pushTimer;
  bool _pushInFlight = false;
  bool _pushQueued = false;
  bool get _hasPendingPush =>
      _pushInFlight || _pushQueued || (_pushTimer?.isActive ?? false);

  List<Rack> get racks => List.unmodifiable(_topology.racks);
  bool get isLoaded => _loaded;
  bool get isEmpty => _topology.racks.isEmpty;
  bool get isSyncing => _syncing;

  // ---- unique id helper -----------------------------------------------------
  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  // ---- cloud binding --------------------------------------------------------
  /// Bind (on sign-in) or unbind (on sign-out) the cloud backend.
  void bindCloud(CloudApi? cloud) {
    _cloud = cloud;
  }

  /// Pull the authoritative topology from the cloud and replace the local cache.
  Future<void> loadFromCloud() async {
    final cloud = _cloud;
    if (cloud == null || !cloud.isConfigured) return;
    // Never clobber local edits that haven't finished syncing up — otherwise a
    // pull racing a fresh assignment would silently discard it.
    if (_hasPendingPush) return;
    _syncing = true;
    notifyListeners();
    try {
      final data = await cloud.getTopology();
      final topo = data['topology'];
      if (topo is Map<String, dynamic>) {
        _topology = RackTopology.fromJsonString(jsonEncode(topo));
        _loaded = true;
        await _cacheLocally();
      }
    } catch (_) {
      // Offline / not reachable: keep the local cache that load() already set.
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Serialized + coalescing push. Two assignments in quick succession used to
  /// fire two overlapping PUTs that could arrive out of order, leaving the cloud
  /// on the stale state. Now: at most one PUT in flight; any edit arriving during
  /// a push re-pushes the *latest* full state afterwards; failures retry.
  Future<void> _pushToCloud() async {
    final cloud = _cloud;
    if (cloud == null || !cloud.isConfigured) return;
    if (_pushInFlight) {
      _pushQueued = true; // a newer edit arrived mid-flight — push again after
      return;
    }
    _pushInFlight = true;
    bool ok = false;
    try {
      await cloud.putTopology(
          jsonDecode(_topology.toJsonString()) as Map<String, dynamic>);
      ok = true;
    } catch (_) {
      // best-effort; retried below
    } finally {
      _pushInFlight = false;
    }
    if (_pushQueued) {
      _pushQueued = false;
      await _pushToCloud(); // send the newest state that landed during the push
    } else if (!ok) {
      _pushTimer?.cancel();
      _pushTimer = Timer(const Duration(seconds: 5), _pushToCloud); // retry stale push
    }
  }

  /// Debounce rapid edits into a single push of the final state.
  void _schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 500), _pushToCloud);
  }

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

  Future<void> _cacheLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _topology.toJsonString());
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _save() async {
    notifyListeners();
    await _cacheLocally();
    _schedulePush();
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

  void renameUnit(String rackId, String unitId, String name) {
    final u = _unit(rackId, unitId);
    if (u != null && name.trim().isNotEmpty) {
      u.name = name.trim();
      _save();   // caches locally + pushes the topology to the cloud (persists)
    }
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
  /// Assign one probe of a sensor to a port. [rom] is the DS18B20 ROM (null/empty
  /// = whole-sensor legacy mapping). A given physical probe lives in exactly one
  /// place, so the same (eui, rom) is cleared from any other port first; the same
  /// eui may legitimately occupy many ports with *different* roms.
  void assignProbe(String portId, String? eui, {String? rom, String? probeLabel}) {
    final p = portById(portId);
    if (p == null) return;
    final e = eui?.trim().toLowerCase();
    final r0 = rom?.trim().toLowerCase();
    if (e != null && e.isNotEmpty) {
      for (final r in _topology.racks) {
        for (final u in r.units) {
          for (final other in u.ports) {
            if (other.id != portId &&
                other.assignedEui == e &&
                (other.assignedProbeRom ?? '') == (r0 ?? '')) {
              other.assignedEui = null;
              other.assignedProbeRom = null;
              other.probeLabel = null;
            }
          }
        }
      }
    }
    if (e == null || e.isEmpty) {
      p.assignedEui = null;
      p.assignedProbeRom = null;
      p.probeLabel = null;
    } else {
      p.assignedEui = e;
      p.assignedProbeRom = (r0 == null || r0.isEmpty) ? null : r0;
      p.probeLabel = probeLabel;
    }
    _save();
  }

  /// Back-compat shim: assign a whole sensor (no probe) to a port.
  void assignEui(String portId, String? eui) => assignProbe(portId, eui);

  /// The probe ROMs (lower-case) of [eui] already assigned to some port, so the
  /// assign dialog can hide probes that are already taken. [exceptPortId] is
  /// skipped — the port being (re)assigned keeps its own probe selectable.
  Set<String> assignedProbeRomsFor(String eui, {String? exceptPortId}) {
    final e = eui.trim().toLowerCase();
    final out = <String>{};
    for (final r in _topology.racks) {
      for (final u in r.units) {
        for (final p in u.ports) {
          if (p.id == exceptPortId) continue;
          if ((p.assignedEui ?? '').toLowerCase() == e) {
            final rom = (p.assignedProbeRom ?? '').toLowerCase();
            if (rom.isNotEmpty) out.add(rom);
          }
        }
      }
    }
    return out;
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
