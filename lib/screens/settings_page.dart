import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';

class SettingsPage extends StatelessWidget {
  final VoidCallback onToggleTheme;

  const SettingsPage({super.key, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer<BLEService>(
        builder: (context, bleService, _) => ListView(
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
            // --- NEW: Change Bridge PIN ---
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
            const Divider(),
            ListTile(
              title: const Text('About'),
              subtitle: const Text('Thread Commissioner v1.0.0'),
              leading: const Icon(Icons.info_outline),
            ),
          ],
        ),
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