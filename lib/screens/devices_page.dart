import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../services/auth_service.dart';
import '../services/topology_service.dart';

/// Fleet view: the connected gateway/router and every commissioned sensor with
/// a live online/offline indicator.
///
/// Online sources (a sensor is online if EITHER says so):
///   • cloud `/v1/current` — last reading within [_staleSeconds]
///   • gateway `NODES?`     — EUIs the gateway has seen recently over the mesh
/// The rack topology supplies friendly Rack/Unit/Port names.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  static const int _staleSeconds = 180; // matches the server's STALE_AFTER_S
  List<Map<String, dynamic>> _cloudSensors = [];
  List<Map<String, dynamic>> _cloudRouters = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ble = context.read<BLEService>();
    // Ask the connected gateway for fresh status + live node/router lists.
    if (ble.isConnected) {
      ble.requestSystemStatus();
      ble.requestNodes();
      ble.requestRouters();
    }
    // Pull last-reading-per-sensor + router roster from the cloud (no BLE needed).
    final auth = context.read<AuthService>();
    try {
      final s = await auth.api.currentTemps();
      List<dynamic> rt = const [];
      try { rt = await auth.api.routers(); } catch (_) {/* older server: no routers */}
      if (mounted) {
        setState(() {
          _cloudSensors = s.cast<Map<String, dynamic>>();
          _cloudRouters = rt.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _nowSec => DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BLEService>();
    final topo = context.watch<TopologyService>();

    // ---- build the unified sensor list ----
    final live = ble.liveNodes.map((e) => e.toLowerCase()).toSet();
    final byEui = <String, _Dev>{};

    // 1) from the rack topology (the commissioned/mapped set)
    for (final r in topo.racks) {
      for (final u in r.units) {
        for (final p in u.ports) {
          final eui = p.assignedEui?.toLowerCase();
          if (eui != null && eui.isNotEmpty) {
            byEui[eui] = _Dev(eui: eui, label: '${r.name} / ${u.name} / ${p.label}');
          }
        }
      }
    }
    // 2) from the cloud (adds last-seen + any not-yet-mapped sensors)
    for (final s in _cloudSensors) {
      final eui = (s['eui'] ?? '').toString().toLowerCase();
      if (eui.isEmpty) continue;
      final ts = (s['ts'] is num) ? (s['ts'] as num).toDouble() : 0.0;
      final loc = (s['location'] ?? '').toString();
      final d = byEui[eui] ?? _Dev(eui: eui, label: loc.isEmpty ? 'Unmapped' : loc);
      d.lastSeen = ts;
      if (loc.isNotEmpty) d.label = loc;
      byEui[eui] = d;
    }
    // 3) anything the gateway sees live but we don't know about
    for (final eui in live) {
      byEui.putIfAbsent(eui, () => _Dev(eui: eui, label: 'Unmapped'));
    }

    // online = recently seen by the cloud OR currently in the gateway's NODES list
    for (final d in byEui.values) {
      final freshCloud = d.lastSeen != null && (_nowSec - d.lastSeen!) < _staleSeconds;
      d.online = freshCloud || live.contains(d.eui);
    }

    final sensors = byEui.values.toList()
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1; // online first
        return a.label.compareTo(b.label);
      });
    final onlineCount = sensors.where((d) => d.online).length;

    // ---- build the router list (cloud /v1/routers ∪ gateway ROUTERS?) ----
    final liveR = ble.liveRouters.map((e) => e.toLowerCase()).toSet();
    final routerByEui = <String, _Dev>{};
    for (final r in _cloudRouters) {
      final eui = (r['eui'] ?? '').toString().toLowerCase();
      if (eui.isEmpty) continue;
      final ls = (r['last_seen'] is num) ? (r['last_seen'] as num).toDouble() : 0.0;
      final d = _Dev(eui: eui, label: 'Router')
        ..lastSeen = ls
        ..online = (r['online'] == true) || liveR.contains(eui);
      routerByEui[eui] = d;
    }
    for (final eui in liveR) {
      routerByEui.putIfAbsent(eui, () => _Dev(eui: eui, label: 'Router')..online = true);
    }
    final routers = routerByEui.values.toList()
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.eui.compareTo(b.eui);
      });
    final routersOnline = routers.where((d) => d.online).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _sectionTitle('Gateway'),
            _gatewayCard(ble),
            _sectionTitle('Routers  ($routersOnline/${routers.length} online)'),
            if (routers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No routers in the mesh yet. Commission a router — it joins the '
                  'network and appears here (sensors relay through routers).',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...routers.map(_sensorTile),
            _sectionTitle('Sensors  ($onlineCount/${sensors.length} online)'),
            if (_loading && sensors.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (sensors.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No sensors yet. Commission a sensor, then assign it in Rack Layout.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...sensors.map(_sensorTile),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _statusDot(bool online) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: online ? Colors.green : Colors.grey,
        ),
      );

  Widget _gatewayCard(BLEService ble) {
    final connected = ble.isConnected;
    final st = ble.systemStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusDot(connected),
                const SizedBox(width: 10),
                Text(connected ? 'This gateway' : 'Gateway (not connected)',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(connected ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: connected ? Colors.green : Colors.grey)),
              ],
            ),
            if (connected && st != null) ...[
              const Divider(),
              _kv('Role', st.role),
              _kv('Firmware', 'C3 v${st.c3Version}  ·  C6 v${st.c6Version}'),
              _kv('Commissioner', st.commState),
              _kv('Wi-Fi uplink', st.wifiUp ? 'connected' : 'down'),
              _kv('Display node', st.uplinkUp ? 'reachable' : 'not found'),
            ] else if (connected) ...[
              const SizedBox(height: 6),
              const Text('Querying status…',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ] else ...[
              const SizedBox(height: 6),
              const Text('Connect to the bridge over Bluetooth to see status.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Widget _sensorTile(_Dev d) {
    final subtitle = StringBuffer(d.eui);
    if (d.lastSeen != null && d.lastSeen! > 0) {
      final ago = (_nowSec - d.lastSeen!).round();
      subtitle.write('  ·  ${_ago(ago)}');
    }
    return Card(
      child: ListTile(
        leading: _statusDot(d.online),
        title: Text(d.label),
        subtitle: Text(subtitle.toString(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        trailing: Text(
          d.online ? 'ONLINE' : 'OFFLINE',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: d.online ? Colors.green : Colors.grey),
        ),
      ),
    );
  }

  String _ago(int s) {
    if (s < 60) return '${s}s ago';
    if (s < 3600) return '${s ~/ 60}m ago';
    if (s < 86400) return '${s ~/ 3600}h ago';
    return '${s ~/ 86400}d ago';
  }
}

class _Dev {
  final String eui;
  String label;
  double? lastSeen;
  bool online = false;
  _Dev({required this.eui, required this.label});
}
