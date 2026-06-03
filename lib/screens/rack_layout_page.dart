import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/topology_service.dart';
import '../models/rack_topology.dart';
import '../utils/auth_guard.dart';
import '../widgets/assign_sensor_dialog.dart';

/// Operator-configurable rack → unit → port layout. The assignment targets
/// (ports) defined here feed the "Assign Sensor" dropdown flow.
class RackLayoutPage extends StatelessWidget {
  const RackLayoutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rack Layout')),
      body: Consumer<TopologyService>(
        builder: (context, topo, _) {
          if (topo.racks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.view_module, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text(
                      'No racks yet.\nAdd a rack, then units and ports (intake/exhaust).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Rack'),
                      onPressed: () => _addRackDialog(context, topo),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              ...topo.racks.map((r) => _RackCard(rack: r, topo: topo)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add Rack'),
                  onPressed: () => _addRackDialog(context, topo),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addRackDialog(BuildContext context, TopologyService topo) {
    _nameDialog(context, 'Add Rack', 'Rack name', (name) => topo.addRack(name));
  }
}

class _RackCard extends StatelessWidget {
  final Rack rack;
  final TopologyService topo;
  const _RackCard({required this.rack, required this.topo});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(rack.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Rename rack',
                  onPressed: () => _nameDialog(
                      context, 'Rename Rack', 'Rack name',
                      (n) => topo.renameRack(rack.id, n),
                      initial: rack.name),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete rack',
                  onPressed: () => _confirmDelete(
                      context, 'Delete ${rack.name}?',
                      () => topo.removeRack(rack.id)),
                ),
              ],
            ),
            const Divider(),
            ...rack.units.map((u) => _UnitTile(rack: rack, unit: u, topo: topo)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add Unit'),
                onPressed: () => topo.addUnit(rack.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  final Rack rack;
  final RackUnit unit;
  final TopologyService topo;
  const _UnitTile({required this.rack, required this.unit, required this.topo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dvr, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(unit.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Delete unit',
                onPressed: () => _confirmDelete(
                    context, 'Delete ${unit.name}?',
                    () => topo.removeUnit(rack.id, unit.id)),
              ),
            ],
          ),
          ...unit.ports.map((p) => _PortRow(port: p, topo: topo)),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.login, size: 16),
                  label: const Text('Add Intake'),
                  onPressed: () =>
                      topo.addPort(rack.id, unit.id, PortType.intake),
                ),
                ActionChip(
                  avatar: const Icon(Icons.logout, size: 16),
                  label: const Text('Add Exhaust'),
                  onPressed: () =>
                      topo.addPort(rack.id, unit.id, PortType.exhaust),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PortRow extends StatelessWidget {
  final Port port;
  final TopologyService topo;
  const _PortRow({required this.port, required this.topo});

  @override
  Widget build(BuildContext context) {
    final intake = port.type == PortType.intake;
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(intake ? Icons.login : Icons.logout,
              size: 16, color: intake ? Colors.blue : Colors.deepOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${port.label}  ·  box${port.box}-${port.slot}',
                    style: const TextStyle(fontSize: 13)),
                Text(
                  port.assignedEui ?? 'unassigned',
                  style: TextStyle(
                    fontSize: 11,
                    color: port.assignedEui != null
                        ? Colors.green
                        : Colors.grey,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.link, size: 16),
            label: Text(port.assignedEui != null ? 'Reassign' : 'Assign'),
            onPressed: () => runWithAuthGuard(
                context, () => showAssignSensorDialog(context, port: port)),
          ),
          if (port.assignedEui != null)
            IconButton(
              icon: const Icon(Icons.link_off, size: 16),
              tooltip: 'Unassign',
              onPressed: () => topo.assignEui(port.id, null),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Delete port',
            onPressed: () => topo.removePort(port.id),
          ),
        ],
      ),
    );
  }
}

// --- small shared dialog helpers ---------------------------------------------

void _nameDialog(BuildContext context, String title, String label,
    void Function(String) onSubmit,
    {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            onSubmit(controller.text);
            Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void _confirmDelete(BuildContext context, String message, VoidCallback onYes) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm'),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            onYes();
            Navigator.pop(ctx);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
