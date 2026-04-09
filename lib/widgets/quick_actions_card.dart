import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../ble_service.dart';
import '../screens/history_page.dart';
import 'router_setup_dialog.dart';
import '../utils/auth_guard.dart'; // NEW: Import the auth guard

class QuickActionsCard extends StatelessWidget {
  final VoidCallback onScanQR;

  const QuickActionsCard({super.key, required this.onScanQR});

  void _showRouterSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const RouterSetupDialog(),
    );
  }

  void _showManualCommandDialog(BuildContext context) {
    final controller = TextEditingController();
    final bleService = Provider.of<BLEService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Manual Command'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Command',
            hintText: 'e.g., add 1234567890abcdef mypassword',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                bleService.sendCustomCommand(controller.text);
                HapticFeedback.mediumImpact();
                Navigator.pop(context);
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 1. Scan QR (Guarded)
                ActionChip(
                  avatar: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan QR'),
                  onPressed: () => runWithAuthGuard(context, onScanQR),
                ),
                // 2. Router Setup (Guarded)
                ActionChip(
                  avatar: const Icon(Icons.router, size: 18),
                  label: const Text('Router Setup'),
                  onPressed: () => runWithAuthGuard(context, () => _showRouterSetupDialog(context)),
                ),
                // 3. Manual Command (Guarded)
                ActionChip(
                  avatar: const Icon(Icons.code, size: 18),
                  label: const Text('Manual Command'),
                  onPressed: () => runWithAuthGuard(context, () => _showManualCommandDialog(context)),
                ),
                // 4. View History (Not Guarded - User can always view local history)
                ActionChip(
                  avatar: const Icon(Icons.history, size: 18),
                  label: const Text('View History'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HistoryPage()),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}