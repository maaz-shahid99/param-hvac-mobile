import 'package:flutter/material.dart';

/// Shared read-only monitoring cards used by both the Alerts & Thresholds screen
/// and the member monitoring home. Pure presentation — data + the ACK callback
/// are supplied by the parent (which owns the cloud polling).

class OpenAlertsCard extends StatelessWidget {
  final List<dynamic> alerts;
  final void Function(String id) onAck;
  const OpenAlertsCard({super.key, required this.alerts, required this.onAck});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Icons.notifications_active_outlined),
            title: Text('Open alerts'),
          ),
          if (alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('No open alerts. All racks within limits.'),
            )
          else
            ...alerts.map((a) => _alertTile(context, a as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _alertTile(BuildContext context, Map<String, dynamic> a) {
    final kind = a['kind'] as String;
    final icon = kind == 'stale'
        ? Icons.sensors_off
        : (kind == 'delta' ? Icons.compare_arrows : Icons.local_fire_department);
    final scheme = Theme.of(context).colorScheme;
    final acked = a['state'] == 'acked';
    final value = (a['value'] as num).toDouble();
    final thr = (a['threshold'] as num).toDouble();
    final subtitle = kind == 'stale'
        ? 'Sensor stopped reporting'
        : '${value.toStringAsFixed(1)}°C (limit ${thr.toStringAsFixed(1)}°C)';
    return ListTile(
      leading: Icon(icon, color: acked ? scheme.outline : scheme.error),
      title: Text(a['location'] as String? ?? ''),
      subtitle: Text(subtitle),
      trailing: acked
          ? const Chip(label: Text('acked'))
          : TextButton(onPressed: () => onAck(a['id'] as String), child: const Text('ACK')),
    );
  }
}

class LiveTempsCard extends StatelessWidget {
  final List<dynamic> sensors;
  final double highLimit; // colour a reading red at/above this
  const LiveTempsCard({super.key, required this.sensors, required this.highLimit});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Icons.thermostat_auto),
            title: Text('Live temperatures'),
          ),
          if (sensors.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('No readings yet. Once the gateway posts, sensors appear here.'),
            )
          else
            ...sensors.map((s) {
              final m = s as Map<String, dynamic>;
              final maxc = (m['max_c'] as num).toDouble();
              final ago = (now - (m['ts'] as num).toDouble()).clamp(0, 1e9).round();
              final loc = (m['location'] as String?)?.isNotEmpty == true
                  ? m['location'] as String
                  : (m['eui'] as String);
              return ListTile(
                dense: true,
                leading: Text('${maxc.toStringAsFixed(1)}°',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: maxc >= highLimit
                            ? Theme.of(context).colorScheme.error
                            : null)),
                title: Text(loc),
                subtitle: Text('${ago}s ago • slot ${m['slot']}'),
              );
            }),
        ],
      ),
    );
  }
}
