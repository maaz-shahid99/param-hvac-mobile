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

/// Fleet firmware crash reports (panics forwarded by devices to the cloud),
/// with backtrace detail + CSV export.
class CrashReportsPage extends StatefulWidget {
  const CrashReportsPage({super.key});
  @override
  State<CrashReportsPage> createState() => _CrashReportsPageState();
}

class _CrashReportsPageState extends State<CrashReportsPage> {
  CloudApi get _api => context.read<AuthService>().api;
  List<dynamic> _crashes = [];
  String? _err;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final c = await _api.crashes();
      if (!mounted) return;
      setState(() {
        _crashes = c;
        _err = null;
      });
    } on CloudApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (_) {
      if (mounted) setState(() => _err = 'Could not reach the cloud server.');
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final csv = await _api.fetchCsv('/v1/crashes/export.csv');
      if (kIsWeb) {
        await Share.share(csv, subject: 'crashes.csv');
      } else {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/crashes.csv');
        await f.writeAsString(csv);
        await Share.shareXFiles([XFile(f.path)], text: 'crashes.csv');
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

  @override
  Widget build(BuildContext context) {
    final reg = context.read<DeviceRegistry>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crash Reports'),
        actions: [
          IconButton(onPressed: _busy ? null : _export, icon: const Icon(Icons.download)),
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
            if (_crashes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No crashes reported.',
                    style: TextStyle(color: Theme.of(context).hintColor)),
              )
            else
              ..._crashes.map((c) {
                final eui = (c['eui'] ?? '').toString();
                final name = reg.displayNameForEui(eui);
                final reason = (c['reset_reason'] ?? 'crash').toString();
                final fw = (c['fw'] ?? '').toString();
                final pc = (c['pc'] ?? '').toString();
                final bt = (c['backtrace'] ?? '').toString();
                final detail = (c['detail'] ?? '').toString();
                return Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.redAccent),
                    title: Text('$name · $reason'),
                    subtitle: Text('$eui${fw.isNotEmpty ? ' · $fw' : ''}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          'PC: ${pc.isEmpty ? '—' : pc}\nbacktrace: ${bt.isEmpty ? '—' : bt}'
                          '${detail.isNotEmpty ? '\n$detail' : ''}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
