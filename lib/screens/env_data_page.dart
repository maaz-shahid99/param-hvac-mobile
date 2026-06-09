import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/auth_service.dart';
import '../services/cloud_api.dart';
import '../services/device_registry.dart';

/// Fleet environmental data: router/gateway BME readings + sensor temperatures,
/// polled every minute from the cloud, with CSV export (routers + sensors).
class EnvDataPage extends StatefulWidget {
  const EnvDataPage({super.key});
  @override
  State<EnvDataPage> createState() => _EnvDataPageState();
}

class _EnvDataPageState extends State<EnvDataPage> {
  CloudApi get _api => context.read<AuthService>().api;
  List<dynamic> _env = [];
  List<dynamic> _sensors = [];
  String? _err;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final res = await Future.wait([_api.envCurrent(), _api.envProbes()]);
      if (!mounted) return;
      setState(() {
        _env = res[0];
        _sensors = res[1];
        _err = null;
      });
    } on CloudApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (_) {
      if (mounted) setState(() => _err = 'Could not reach the cloud server.');
    }
  }

  Future<void> _export(String path, String filename) async {
    setState(() => _busy = true);
    try {
      final csv = await _api.fetchCsv(path);
      if (kIsWeb) {
        await Share.share(csv, subject: filename);
      } else {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/$filename');
        await f.writeAsString(csv);
        await Share.shareXFiles([XFile(f.path)], text: filename);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(String eui, String cloudName, DeviceKind kind) {
    if (cloudName.isNotEmpty) return cloudName;
    return context.read<DeviceRegistry>().displayNameForEui(eui, fallbackKind: kind);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Environment & Logs'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_err != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_err!)),
              ),
            _sectionHeader('Routers — environment', Icons.hub, _env.length,
                () => _export('/v1/env/export.csv', 'routers_env.csv')),
            if (_env.isEmpty)
              const _Empty('No router environment data yet.')
            else
              ..._env.map((e) {
                final eui = (e['eui'] ?? '').toString();
                final name = _name(eui, (e['name'] ?? '').toString(), DeviceKind.router);
                final t = (e['temp'] as num?)?.toDouble() ?? 0;
                final h = (e['hum'] as num?)?.toDouble() ?? 0;
                final p = (e['pres'] as num?)?.toDouble() ?? 0;
                final v = (e['voc'] as num?)?.toDouble() ?? 0;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.thermostat),
                    title: Text(name),
                    subtitle: Text(eui, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    trailing: Text(
                      '${t.toStringAsFixed(1)}°C\n${h.toStringAsFixed(0)}% · ${p.toStringAsFixed(0)}hPa · VOC ${v.round()}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            _sectionHeader('Sensors — temperatures', Icons.device_thermostat, _sensors.length,
                () => _export('/v1/readings/export.csv', 'sensors.csv')),
            if (_sensors.isEmpty)
              const _Empty('No sensor data yet.')
            else
              ..._sensors.map((s) {
                final eui = (s['eui'] ?? '').toString();
                final label = (s['label'] ?? '').toString();
                final name = _name(eui, (s['name'] ?? '').toString(), DeviceKind.sensor);
                final temp = (s['temp'] as num?)?.toDouble();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.thermostat),
                    title: Text(label.isNotEmpty ? label : eui),
                    subtitle: Text(name, style: const TextStyle(fontSize: 11)),
                    trailing: Text(temp != null ? '${temp.toStringAsFixed(1)}°' : '—',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, int count, VoidCallback onExport) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('$title ($count)', style: Theme.of(context).textTheme.titleMedium)),
          TextButton.icon(
            onPressed: _busy ? null : onExport,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('CSV'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: Theme.of(context).hintColor)),
      );
}
