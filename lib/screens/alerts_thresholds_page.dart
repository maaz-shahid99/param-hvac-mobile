import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_api.dart';
import '../widgets/monitoring_cards.dart';

/// The customer-facing product surface: open overheat alerts, live temperatures,
/// and the threshold controls — all served by the AWS Cloud Server.
class AlertsThresholdsPage extends StatefulWidget {
  const AlertsThresholdsPage({super.key});

  @override
  State<AlertsThresholdsPage> createState() => _AlertsThresholdsPageState();
}

class _AlertsThresholdsPageState extends State<AlertsThresholdsPage> {
  List<dynamic> _alerts = [];
  List<dynamic> _sensors = [];
  final _high = TextEditingController();
  final _delta = TextEditingController();
  double _defHigh = 40, _defDelta = 20;
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
    _high.dispose();
    _delta.dispose();
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
      final tenant = (thr['thresholds'] as List)
          .cast<Map<String, dynamic>>()
          .where((t) => t['scope'] == 'tenant')
          .toList();
      setState(() {
        _alerts = results[0] as List<dynamic>;
        _sensors = results[1] as List<dynamic>;
        _defHigh = (defaults['high_c'] as num).toDouble();
        _defDelta = (defaults['delta_c'] as num).toDouble();
        if (_high.text.isEmpty) {
          _high.text = (tenant.isNotEmpty ? tenant.first['high_c'] : _defHigh).toString();
        }
        if (_delta.text.isEmpty) {
          _delta.text = (tenant.isNotEmpty ? tenant.first['delta_c'] : _defDelta).toString();
        }
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
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _saveThreshold() async {
    final high = double.tryParse(_high.text.trim());
    final delta = double.tryParse(_delta.text.trim());
    if (high == null || delta == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter valid numbers')));
      return;
    }
    try {
      await _api.putThreshold(scope: 'tenant', highC: high, deltaC: delta);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Thresholds saved')));
    } on CloudApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _ack(String id) async {
    try {
      await _api.ackAlert(id);
      _refresh(silent: true);
    } catch (_) {/* ignored; next poll reflects state */}
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthService>().isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts & Thresholds'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(),
          ),
          if (isAdmin)
            PopupMenuButton<String>(
              onSelected: _onAdminAction,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'key', child: Text('Generate gateway API key')),
                PopupMenuItem(value: 'recipients', child: Text('Set alert recipients')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.cloud_off),
                        title: Text(_error!),
                      ),
                    ),
                  OpenAlertsCard(alerts: _alerts, onAck: _ack),
                  const SizedBox(height: 12),
                  _thresholdsCard(isAdmin),
                  const SizedBox(height: 12),
                  LiveTempsCard(sensors: _sensors, highLimit: _defHigh),
                ],
              ),
            ),
    );
  }

  Widget _thresholdsCard(bool isAdmin) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alert thresholds', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Applied to every rack unless overridden. Defaults: '
                '${_defHigh.toStringAsFixed(0)}°C / Δ${_defDelta.toStringAsFixed(0)}°C.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _high,
                    enabled: isAdmin,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'High temp °C',
                      prefixIcon: Icon(Icons.thermostat),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _delta,
                    enabled: isAdmin,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Max ΔT °C',
                      prefixIcon: Icon(Icons.compare_arrows),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: isAdmin ? _saveThreshold : null,
                icon: const Icon(Icons.save),
                label: Text(isAdmin ? 'Save' : 'Admins only'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAdminAction(String action) async {
    if (action == 'key') {
      try {
        final key = await _api.createApiKey('gateway');
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Gateway API key'),
            content: SelectableText(
                'Provision this into the gateway (PROVISION cloudKey). '
                'It is shown only once:\n\n$key'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ],
          ),
        );
      } on CloudApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } else if (action == 'recipients') {
      await _recipientsDialog();
    }
  }

  Future<void> _recipientsDialog() async {
    final emails = TextEditingController();
    final phones = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Alert recipients'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emails,
              decoration: const InputDecoration(
                  labelText: 'Emails (comma-separated)', prefixIcon: Icon(Icons.email)),
            ),
            TextField(
              controller: phones,
              decoration: const InputDecoration(
                  labelText: 'Phones (comma-separated)', prefixIcon: Icon(Icons.sms)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api.setRecipients(emails: emails.text.trim(), phones: phones.text.trim());
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Recipients saved')));
      } on CloudApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
