import 'package:flutter/material.dart';
import '../ble_service.dart';
import 'device_scanner_sheet.dart'; // Safely imported and used here!

class DisconnectedView extends StatelessWidget {
  final BLEService bleService;

  const DisconnectedView({super.key, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 80,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Bridge Disconnected',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ensure your Thread Bridge is powered on and within Bluetooth range.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
        // --- REPLACED: Now uses ActionChip to match Quick Actions ---
        ActionChip(
          avatar: const Icon(Icons.bluetooth_searching, size: 18),
          label: const Text('Scan for Bridge'),
          padding: const EdgeInsets.all(8),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (context) => const DeviceScannerSheet(),
            );
          },
        ),
          ],
        ),
      ),
    );
  }
}