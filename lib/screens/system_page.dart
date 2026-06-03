import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../utils/auth_guard.dart';

/// System / Manage screen: live status, commissioner control, firmware update,
/// and factory reset. Reuses the app's existing Card / ActionChip / dialog
/// styling; only the layout is new.
class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final ble = Provider.of<BLEService>(context, listen: false);
    ble.requestSystemStatus();
    // Refresh status while this screen is open.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      Provider.of<BLEService>(context, listen: false).requestSystemStatus();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
    Color? confirmColor,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: confirmColor == null
                ? null
                : ElevatedButton.styleFrom(
                    backgroundColor: confirmColor, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.mediumImpact();
              onConfirm();
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System / Manage')),
      body: Consumer<BLEService>(
        builder: (context, ble, _) {
          final st = ble.systemStatus;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusCard(context, st),
              _commissionerCard(context, ble, st),
              _firmwareCard(context, ble, st),
              _dangerCard(context, ble),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionCard(BuildContext context, String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, SystemStatus? st) {
    if (st == null) {
      return _sectionCard(context, 'Status', const [
        Text('Waiting for status… (connect and unlock the session)'),
      ]);
    }
    return _sectionCard(context, 'Status', [
      _kv('Role', st.role,
          color: st.role == 'LEADER' ? Colors.green : Colors.blueGrey),
      _kv('Bridge (C3) fw', 'v${st.c3Version}'),
      _kv('Commissioner (C6) fw', st.c6Version < 0 ? '—' : 'v${st.c6Version}'),
      _kv('Commissioner', st.commState,
          color: st.commState == 'ACTIVE' ? Colors.green : Colors.orange),
      _kv('Wi-Fi', st.wifiUp ? 'connected' : 'down',
          color: st.wifiUp ? Colors.green : Colors.red),
      _kv('Uplink (display node)', st.uplinkUp ? 'reachable' : 'no',
          color: st.uplinkUp ? Colors.green : Colors.red),
    ]);
  }

  Widget _commissionerCard(BuildContext context, BLEService ble, SystemStatus? st) {
    final active = st?.commState == 'ACTIVE';
    return _sectionCard(context, 'Commissioner', [
      Text(active
          ? 'Currently ACTIVE — ready for joiners.'
          : 'Currently ${st?.commState ?? 'unknown'}.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ActionChip(
          avatar: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Enable'),
          onPressed: () => runWithAuthGuard(context, () => ble.setCommissioner(true)),
        ),
        ActionChip(
          avatar: const Icon(Icons.stop, size: 18),
          label: const Text('Disable'),
          onPressed: () => runWithAuthGuard(context, () => ble.setCommissioner(false)),
        ),
      ]),
    ]);
  }

  Widget _firmwareCard(BuildContext context, BLEService ble, SystemStatus? st) {
    return _sectionCard(context, 'Firmware Update', [
      if (st != null)
        Text('Running: C3 v${st.c3Version}'
            ', C6 ${st.c6Version < 0 ? '—' : 'v${st.c6Version}'}'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ActionChip(
          avatar: const Icon(Icons.system_update, size: 18),
          label: const Text('Update This Gateway'),
          onPressed: () => runWithAuthGuard(
            context,
            () => _confirm(context,
                title: 'Update this gateway?',
                message:
                    'Downloads and applies the latest firmware to this unit (C6 then C3). The unit will reboot.',
                confirmLabel: 'Update',
                confirmColor: Theme.of(context).colorScheme.primary,
                onConfirm: () => ble.updateThisGateway()),
          ),
        ),
        ActionChip(
          avatar: const Icon(Icons.cloud_sync, size: 18),
          label: const Text('Update Whole Fleet'),
          onPressed: () => runWithAuthGuard(
            context,
            () => _confirm(context,
                title: 'Update the whole fleet?',
                message:
                    'Broadcasts an OTA to every unit on the mesh. Each unit updates itself (staggered); the fleet stays online during the rollout.',
                confirmLabel: 'Update Fleet',
                confirmColor: Theme.of(context).colorScheme.primary,
                onConfirm: () => ble.updateWholeFleet()),
          ),
        ),
      ]),
      if (ble.otaStatus.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(ble.otaStatus,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
      ],
    ]);
  }

  Widget _dangerCard(BuildContext context, BLEService ble) {
    return _sectionCard(context, 'Danger Zone', [
      const Text(
          'Factory reset wipes credentials and the Thread network. Devices must be re-commissioned afterward.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ActionChip(
          avatar: const Icon(Icons.restart_alt, size: 18, color: Colors.red),
          label: const Text('Reset This Unit'),
          onPressed: () => runWithAuthGuard(
            context,
            () => _confirm(context,
                title: 'Factory reset THIS unit?',
                message:
                    'Wipes this unit (C3 + C6) and reboots into setup mode. Cannot be undone.',
                confirmLabel: 'Reset Unit',
                onConfirm: () => ble.factoryResetUnit()),
          ),
        ),
        ActionChip(
          avatar: const Icon(Icons.delete_forever, size: 18, color: Colors.red),
          label: const Text('Reset Whole Fleet'),
          onPressed: () => runWithAuthGuard(
            context,
            () => _confirm(context,
                title: 'Factory reset the WHOLE fleet?',
                message:
                    'Wipes EVERY unit on the mesh and reboots them. The entire fleet must be re-provisioned and re-commissioned. Cannot be undone.',
                confirmLabel: 'Reset Fleet',
                onConfirm: () => ble.factoryResetFleet()),
          ),
        ),
      ]),
    ]);
  }
}
