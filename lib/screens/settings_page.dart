import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../services/auth_service.dart';
import '../app_version.dart';

class SettingsPage extends StatelessWidget {
  final VoidCallback onToggleTheme;

  const SettingsPage({super.key, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer<BLEService>(
        builder: (context, bleService, _) {
          final isAdmin = context.watch<AuthService>().isAdmin;
          return ListView(
          children: [
            SwitchListTile(
              title: const Text('Auto-Reconnect'),
              subtitle: const Text('Automatically reconnect when connection is lost'),
              value: bleService.autoReconnect,
              onChanged: bleService.setAutoReconnect,
            ),
            ListTile(
              title: const Text('Toggle Theme'),
              subtitle: const Text('Switch between light and dark mode'),
              leading: const Icon(Icons.brightness_6),
              onTap: onToggleTheme,
            ),
            // Bridge PIN + HMAC key are admin-only hardware controls.
            if (isAdmin) ...[
              ListTile(
                title: const Text('Change Bridge PIN'),
                subtitle: const Text('Update the access PIN for the ESP32 Bridge'),
                leading: const Icon(Icons.password),
                onTap: () {
                  if (!bleService.isConnected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Must be connected to change PIN')),
                    );
                    return;
                  }
                  if (bleService.authState != BridgeAuthState.authenticated) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please unlock the bridge first')),
                    );
                    return;
                  }
                  _showChangeBridgePinDialog(context, bleService);
                },
              ),
              ListTile(
                title: const Text('Update Secret Key'),
                subtitle: const Text('Change HMAC signing key'),
                leading: const Icon(Icons.key),
                onTap: () => _showUpdateKeyDialog(context, bleService),
              ),
            ],
            ListTile(
              title: const Text('Clear History'),
              subtitle: const Text('Remove all commissioned device records'),
              leading: const Icon(Icons.delete_sweep),
              onTap: () {
                bleService.clearHistory();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('History cleared')),
                );
              },
            ),
            // Cloud alert granularity (admin + signed-in only).
            if (isAdmin && context.watch<AuthService>().status == AuthStatus.signedIn)
              const _AlertGranularityTile(),
            const Divider(),
            Consumer<AuthService>(
              builder: (context, auth, _) => ListTile(
                title: const Text('Sign out'),
                subtitle: Text(auth.email.isEmpty
                    ? 'Signed in to the cloud'
                    : '${auth.email} • ${auth.role}'),
                leading: const Icon(Icons.logout),
                onTap: () async {
                  await auth.signOut();
                  if (context.mounted) Navigator.of(context).maybePop();
                },
              ),
            ),
            const Divider(),
            const ListTile(
              title: Text('About'),
              subtitle: Text('Thread Commissioner v$kAppVersion'),
              leading: Icon(Icons.info_outline),
            ),
            // Build tag — tap to copy. Bump kAppBuild on every change so you can
            // confirm the installed build matches the latest code.
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Build'),
              subtitle: const Text(kAppBuild),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () {
                Clipboard.setData(const ClipboardData(text: kAppBuild));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Build copied')),
                );
              },
            ),
          ],
        );
        },
      ),
    );
  }

  // --- NEW: Change Bridge PIN Dialog ---
  void _showChangeBridgePinDialog(BuildContext context, BLEService bleService) {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Bridge PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPinController,
              decoration: const InputDecoration(
                labelText: 'Current PIN',
                hintText: 'Enter current PIN',
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newPinController,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                hintText: 'Enter new PIN (min 4 digits)',
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final currentPin = currentPinController.text.trim();
              final newPin = newPinController.text.trim();

              if (currentPin.isEmpty || newPin.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid input. New PIN must be at least 4 digits.')),
                );
                return;
              }

              // Send the SETPIN command with the old PIN
              await bleService.setupBridgePin(newPin, oldPin: currentPin);

              if (!context.mounted) return;
              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN update request sent. Check logs for confirmation.')),
              );
            },
            child: const Text('Update PIN'),
          ),
        ],
      ),
    );
  }

  void _showUpdateKeyDialog(BuildContext context, BLEService bleService) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Secret Key'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New Secret Key',
            hintText: 'Enter new HMAC key',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await bleService.updateSecretKey(controller.text);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Secret key updated')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}

/// Admin toggle for how the cloud opens alerts: per-sensor (hottest probe) or
/// per-probe (each mapped probe alerts at its own exhaust). Cloud setting.
class _AlertGranularityTile extends StatefulWidget {
  const _AlertGranularityTile();

  @override
  State<_AlertGranularityTile> createState() => _AlertGranularityTileState();
}

class _AlertGranularityTileState extends State<_AlertGranularityTile> {
  String? _value; // null while loading
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<AuthService>().api.getAlertGranularity();
      if (mounted) setState(() => _value = v);
    } catch (_) {
      if (mounted) setState(() => _value = 'sensor');
    }
  }

  Future<void> _set(String v) async {
    if (v == _value || _busy) return;
    final prev = _value;
    setState(() {
      _value = v;
      _busy = true;
    });
    try {
      await context.read<AuthService>().api.setAlertGranularity(v);
    } catch (e) {
      if (mounted) {
        setState(() => _value = prev);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: const Text('Alert granularity'),
      subtitle: Text(_value == 'probe'
          ? 'Each probe alerts at its own exhaust'
          : 'One alert per sensor (hottest probe)'),
      trailing: _value == null
          ? const SizedBox(
              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'sensor', label: Text('Sensor')),
                ButtonSegment(value: 'probe', label: Text('Probe')),
              ],
              selected: {_value!},
              onSelectionChanged: _busy ? null : (s) => _set(s.first),
            ),
    );
  }
}