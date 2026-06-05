import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_api.dart';

enum DeviceKind { sensor, router, gateway }

/// A short human name derived from a device's EUI when no custom name is set, e.g.
/// "Sensor-4EC0", "Router-16E0", "Gateway-1BB0". Never a full hex string.
String autoNameFor(String eui, DeviceKind kind) {
  final e = eui.trim();
  final suffix = (e.length >= 4 ? e.substring(e.length - 4) : e).toUpperCase();
  const labels = {
    DeviceKind.sensor: 'Sensor',
    DeviceKind.router: 'Router',
    DeviceKind.gateway: 'Gateway',
  };
  return '${labels[kind]}-$suffix';
}

class KnownDevice {
  final String eui;
  DeviceKind kind;
  String role;     // 'G'/'R' for mesh nodes; '' for sensors
  String name;     // operator-assigned; '' => show the auto-name
  double lastSeen; // epoch seconds, last time observed (informational)
  KnownDevice({
    required this.eui,
    required this.kind,
    this.role = '',
    this.name = '',
    this.lastSeen = 0,
  });

  /// Friendly label: the custom name if set, else an EUI-derived auto-name.
  String get displayName => name.isNotEmpty ? name : autoNameFor(eui, kind);

  Map<String, dynamic> toJson() =>
      {'eui': eui, 'kind': kind.name, 'role': role, 'name': name, 'lastSeen': lastSeen};

  /// The cloud roster stores membership + type + name (no per-phone lastSeen).
  Map<String, dynamic> toCloudJson() =>
      {'eui': eui, 'kind': kind.name, 'role': role, 'name': name};

  factory KnownDevice.fromJson(Map<String, dynamic> j) => KnownDevice(
        eui: (j['eui'] as String).toLowerCase(),
        kind: DeviceKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => DeviceKind.sensor),
        role: j['role'] as String? ?? '',
        name: j['name'] as String? ?? '',
        lastSeen: (j['lastSeen'] as num?)?.toDouble() ?? 0,
      );
}

/// Registry of every sensor / mesh node the org has commissioned, so the Devices
/// list keeps showing a device (greyed, "offline") after it drops out of the live
/// rosters — and, crucially, **survives changing phones / reinstalls** because the
/// roster is stored in the cloud per tenant. SharedPreferences is a local cache
/// for instant load + offline use; the cloud is the source of truth once signed
/// in. Membership + type only — the UI computes live online status.
class DeviceRegistry extends ChangeNotifier {
  static const String _prefsKey = 'known_devices_json';
  final Map<String, KnownDevice> _devices = {};
  bool _loaded = false;
  CloudApi? _cloud;
  bool _dirty = false;   // local additions not yet merged to the cloud

  bool get isLoaded => _loaded;
  List<KnownDevice> get sensors =>
      _devices.values.where((d) => d.kind == DeviceKind.sensor).toList();
  List<KnownDevice> get meshNodes =>
      _devices.values.where((d) => d.kind != DeviceKind.sensor).toList();

  // ---- cloud binding (mirrors TopologyService) ------------------------------
  void bindCloud(CloudApi? cloud) {
    _cloud = cloud;
    if (cloud != null) _pushIfDirty();   // flush anything added while offline
  }

  /// Pull the authoritative roster from the cloud and replace the local cache.
  /// Flushes any pending local additions first so a replace can't drop them.
  Future<void> loadFromCloud() async {
    final cloud = _cloud;
    if (cloud == null || !cloud.isConfigured) return;
    await _pushIfDirty();
    try {
      final list = await cloud.getDevices();
      _devices.clear();
      for (final e in list) {
        final d = KnownDevice.fromJson(e as Map<String, dynamic>);
        _devices[d.eui] = d;
      }
      _dirty = false;
      await _cacheLocally();
      notifyListeners();
    } catch (_) {/* offline: keep the local cache */}
  }

  Future<void> _pushIfDirty() async {
    final cloud = _cloud;
    if (cloud == null || !cloud.isConfigured || !_dirty) return;
    try {
      await cloud.putDevices(_devices.values.map((d) => d.toCloudJson()).toList());
      _dirty = false;
    } catch (_) {/* stays dirty; retried on the next observe / bind */}
  }

  // ---- local cache ----------------------------------------------------------
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        for (final e in jsonDecode(raw) as List) {
          final d = KnownDevice.fromJson(e as Map<String, dynamic>);
          _devices[d.eui] = d;
        }
      }
    } catch (_) {/* corrupt cache -> start empty */}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _cacheLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_devices.values.map((d) => d.toJson()).toList()));
    } catch (_) {/* best-effort */}
  }

  void _save() {
    _dirty = true;
    _cacheLocally();
    _pushIfDirty();
    notifyListeners();
  }

  // ---- mutation -------------------------------------------------------------
  /// Merge in the currently-known devices (membership). A device that ever reports
  /// readings is a sensor. Persists + pushes only on a membership/type change.
  void observe({
    Iterable<String> sensors = const [],
    Map<String, String> meshNodes = const {}, // eui -> 'G'/'R'
  }) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    var changed = false;

    for (final raw in sensors) {
      final eui = raw.toLowerCase();
      if (eui.isEmpty) continue;
      final d = _devices[eui];
      if (d == null) {
        _devices[eui] = KnownDevice(eui: eui, kind: DeviceKind.sensor, lastSeen: now);
        changed = true;
      } else if (d.kind != DeviceKind.sensor) {
        d.kind = DeviceKind.sensor;
        d.role = '';
        d.lastSeen = now;
        changed = true;
      } else {
        d.lastSeen = now;
      }
    }

    meshNodes.forEach((raw, role) {
      final eui = raw.toLowerCase();
      if (eui.isEmpty) return;
      final kind = role.toUpperCase() == 'G' ? DeviceKind.gateway : DeviceKind.router;
      final d = _devices[eui];
      if (d == null) {
        _devices[eui] = KnownDevice(eui: eui, kind: kind, role: role, lastSeen: now);
        changed = true;
      } else if (d.kind != DeviceKind.sensor) {
        if (d.kind != kind || d.role != role) changed = true;
        d.kind = kind;
        d.role = role;
        d.lastSeen = now;
      }
    });

    if (changed) {
      _save();
    } else {
      _pushIfDirty();   // back online -> flush any earlier offline additions
    }
  }

  /// Friendly name for [eui] — the custom name if one is set, else an EUI-derived
  /// auto-name. [fallbackKind] is used when the device isn't in the roster yet.
  String displayNameForEui(String eui, {DeviceKind fallbackKind = DeviceKind.sensor}) {
    final d = _devices[eui.trim().toLowerCase()];
    return d != null ? d.displayName : autoNameFor(eui, fallbackKind);
  }

  /// The raw custom name (empty if none) — for prefilling the rename field.
  String customNameFor(String eui) => _devices[eui.trim().toLowerCase()]?.name ?? '';

  /// Set (or clear) a device's custom name and sync it to the cloud roster.
  void rename(String eui, String name) {
    final e = eui.trim().toLowerCase();
    final n = name.trim();
    final d = _devices[e];
    if (d != null) {
      if (d.name == n) return;
      d.name = n;
    } else {
      _devices[e] = KnownDevice(eui: e, kind: DeviceKind.sensor, name: n);
    }
    _save();   // caches + pushes the roster (the cloud preserves non-empty names)
  }

  /// Remove a device from the roster (decommission). Removes it on the cloud too.
  void forget(String eui) {
    final e = eui.toLowerCase();
    if (_devices.remove(e) != null) {
      _cacheLocally();
      notifyListeners();
      final cloud = _cloud;
      if (cloud != null && cloud.isConfigured) {
        cloud.deleteDevice(e).catchError((_) {});   // best-effort
      }
    }
  }
}
