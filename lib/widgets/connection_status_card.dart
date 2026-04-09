import 'package:flutter/material.dart';
import '../ble_service.dart';

class ConnectionStatusCard extends StatelessWidget {
  final BLEService bleService;
  const ConnectionStatusCard({super.key, required this.bleService});

  @override
  Widget build(BuildContext context) {
    final isConnected = bleService.isConnected;
    final isLocked = isConnected && bleService.authState != BridgeAuthState.authenticated;

    Color statusColor = isConnected
        ? (isLocked ? Colors.orange : Colors.green)
        : Colors.redAccent;

    IconData statusIcon = isConnected
        ? (isLocked ? Icons.lock : Icons.check_circle)
        : Icons.warning;

    String statusText = isConnected
        ? (isLocked ? 'Connected (Locked)' : 'Connected & Secured')
        : 'Disconnected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: statusColor,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isConnected)
                  Text(
                    '${bleService.deviceName} • RSSI: ${bleService.rssi} dBm',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (isConnected) _buildSignalStrength(bleService.rssi),
        ],
      ),
    );
  }

  Widget _buildSignalStrength(int rssi) {
    if (rssi >= -60) return const Icon(Icons.signal_cellular_alt, color: Colors.green);
    if (rssi >= -75) return const Icon(Icons.signal_cellular_alt_2_bar, color: Colors.orange);
    return const Icon(Icons.signal_cellular_alt_1_bar, color: Colors.red);
  }
}