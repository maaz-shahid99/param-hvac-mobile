import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_api.dart';
import '../widgets/app_drawer.dart';
import '../widgets/monitoring_cards.dart';
import '../widgets/ota_update_banner.dart';

/// Cloud-only monitoring home for non-admin members: open alerts (with ACK),
/// live temperatures, and a device online/offline summary. No Bluetooth, no
/// commissioning — a member is a monitor / alert recipient.
class MemberHomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const MemberHomePage({super.key, required this.onToggleTheme});

  @override
  State<MemberHomePage> createState() => _MemberHomePageState();
}

class _MemberHomePageState extends State<MemberHomePage> {
  static const int _staleSeconds = 30; // online if a reading is newer than this (~3 report cycles)

  List<dynamic> _alerts = [];
  List<dynamic> _sensors = [];
  double _defHigh = 40;
  bool _loading = true;
  String? _error;
  Timer? _poll;

  CloudApi get _api => context.read<AuthService>().api;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.alerts(state: 'open'),
        _api.currentTemps(),
        _api.getThresholds(),
      ]);
      if (!mounted) return;
      final thr = results[2] as Map<String, dynamic>;
      final defaults = thr['defaults'] as Map<String, dynamic>;
      setState(() {
        _alerts = results[0] as List<dynamic>;
        _sensors = results[1] as List<dynamic>;
        _defHigh = (defaults['high_c'] as num).toDouble();
        _error = null;
        _loading = false;
      });
    } on CloudApiException catch (e) {
      _fail(e.message, silent);
    } catch (_) {
      _fail('Could not reach the cloud server.', silent);
    }
  }

  void _fail(String msg, bool silent) {
    if (!mounted) return;
    setState(() {
      _error = msg;
      _loading = false;
    });
  }

  Future<void> _ack(String id) async {
    try {
      await _api.ackAlert(id);
      _refresh(silent: true);
    } catch (_) {/* next poll reflects state */}
  }

  int get _onlineCount {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return _sensors.where((s) {
      final ts = ((s as Map)['ts'] as num?)?.toDouble() ?? 0;
      return now - ts < _staleSeconds;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HVAC Monitor'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _refresh()),
        ],
      ),
      drawer: AppDrawer(onToggleTheme: widget.onToggleTheme),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const OtaUpdateBanner(),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.cloud_off),
                        title: Text(_error!),
                      ),
                    ),
                  _summaryCard(),
                  const SizedBox(height: 12),
                  OpenAlertsCard(alerts: _alerts, onAck: _ack),
                  const SizedBox(height: 12),
                  LiveTempsCard(sensors: _sensors, highLimit: _defHigh),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard() {
    final openAlerts = _alerts.where((a) => (a as Map)['state'] != 'cleared').length;
    final total = _sensors.length;
    final online = _onlineCount;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _stat(
                icon: Icons.notifications_active_outlined,
                value: '$openAlerts',
                label: openAlerts == 1 ? 'open alert' : 'open alerts',
                color: openAlerts > 0 ? scheme.error : scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _stat(
                icon: Icons.sensors,
                value: '$online/$total',
                label: 'sensors online',
                color: (total > 0 && online < total) ? scheme.error : scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(
      {required IconData icon,
      required String value,
      required String label,
      required Color color}) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
