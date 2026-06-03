import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../services/topology_service.dart';
import '../models/rack_topology.dart';

/// Opens the dropdown-based "assign a sensor to a location" dialog.
///
/// - [port] fixed: the location is locked (launched from a port row); the user
///   only picks the device.
/// - [presetEui] set: the device is pre-selected (post-commission flow); the
///   user picks Rack → Unit → Port.
Future<void> showAssignSensorDialog(
  BuildContext context, {
  Port? port,
  String? presetEui,
}) {
  return showDialog(
    context: context,
    builder: (_) => _AssignSensorDialog(fixedPort: port, presetEui: presetEui),
  );
}

class _AssignSensorDialog extends StatefulWidget {
  final Port? fixedPort;
  final String? presetEui;
  const _AssignSensorDialog({this.fixedPort, this.presetEui});

  @override
  State<_AssignSensorDialog> createState() => _AssignSensorDialogState();
}

class _AssignSensorDialogState extends State<_AssignSensorDialog> {
  String? _eui;
  String? _rackId;
  String? _unitId;
  String? _portId;

  @override
  void initState() {
    super.initState();
    _eui = widget.presetEui?.toLowerCase();
    // Ask the bridge for a fresh live-device list as the dialog opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BLEService>().requestNodes();
      }
    });
  }

  void _submit() {
    final ble = context.read<BLEService>();
    final topo = context.read<TopologyService>();

    final eui = _eui?.trim().toLowerCase();
    if (eui == null || eui.isEmpty) {
      _toast('Select a sensor');
      return;
    }

    final Port? target =
        widget.fixedPort ?? (_portId != null ? topo.portById(_portId!) : null);
    if (target == null) {
      _toast('Select a location (rack / unit / port)');
      return;
    }

    Navigator.pop(context);
    HapticFeedback.mediumImpact();
    topo.assignEui(target.id, eui);
    ble.setSensorMapping(
      eui64: eui,
      box: target.box,
      slot: target.slot,
      label: topo.labelForPort(target.id),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BLEService>();
    final topo = context.watch<TopologyService>();
    final nodes = ble.liveNodes;

    // Build the device option list, always including a preset/already-known eui.
    final deviceItems = <String>{...nodes};
    if (_eui != null) deviceItems.add(_eui!);

    final racks = topo.racks;
    final units =
        _rackId == null ? <RackUnit>[] : (_rackById(racks, _rackId!)?.units ?? []);
    final ports = _unitId == null
        ? <Port>[]
        : (_unitById(units, _unitId!)?.ports ?? []);

    return AlertDialog(
      title: const Text('Assign Sensor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- device dropdown -------------------------------------------
            Row(
              children: [
                const Expanded(child: Text('Sensor')),
                ActionChip(
                  avatar: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  onPressed: () => ble.requestNodes(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (deviceItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No live sensors yet. Tap Refresh once sensors are reporting.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              DropdownButton<String>(
                isExpanded: true,
                value: _eui,
                hint: const Text('Select a live sensor'),
                items: deviceItems
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _eui = v),
              ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 4),

            // ---- location ---------------------------------------------------
            if (widget.fixedPort != null)
              Text(
                topo.labelForPort(widget.fixedPort!.id),
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            else if (racks.isEmpty)
              const Text(
                'No racks configured. Add a layout in Rack Layout first.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              )
            else ...[
              const Text('Location'),
              const SizedBox(height: 4),
              DropdownButton<String>(
                isExpanded: true,
                value: _rackId,
                hint: const Text('Rack'),
                items: racks
                    .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _rackId = v;
                  _unitId = null;
                  _portId = null;
                }),
              ),
              DropdownButton<String>(
                isExpanded: true,
                value: _unitId,
                hint: const Text('Unit'),
                items: units
                    .map((u) => DropdownMenuItem(value: u.id, child: Text(u.name)))
                    .toList(),
                onChanged: _rackId == null
                    ? null
                    : (v) => setState(() {
                          _unitId = v;
                          _portId = null;
                        }),
              ),
              DropdownButton<String>(
                isExpanded: true,
                value: _portId,
                hint: const Text('Port'),
                items: ports
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                              '${p.label}${p.assignedEui != null ? "  (reassign)" : ""}'),
                        ))
                    .toList(),
                onChanged: _unitId == null
                    ? null
                    : (v) => setState(() => _portId = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Assign'),
        ),
      ],
    );
  }

  Rack? _rackById(List<Rack> racks, String id) {
    for (final r in racks) {
      if (r.id == id) return r;
    }
    return null;
  }

  RackUnit? _unitById(List<RackUnit> units, String id) {
    for (final u in units) {
      if (u.id == id) return u;
    }
    return null;
  }
}
