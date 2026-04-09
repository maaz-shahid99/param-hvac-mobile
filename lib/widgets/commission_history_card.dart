import 'package:flutter/material.dart';
import '../ble_service.dart';
import '../screens/history_page.dart';

class CommissionHistoryCard extends StatelessWidget {
  final BLEService bleService;

  const CommissionHistoryCard({super.key, required this.bleService});

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (bleService.commissionHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    final recentDevices =
    bleService.commissionHistory.reversed.take(3).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Commissions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const HistoryPage()),
                    );
                  },
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...recentDevices.map((device) => ListTile(
              dense: true,
              leading: Icon(
                device.success ? Icons.check_circle : Icons.error,
                color: device.success ? Colors.green : Colors.red,
              ),
              title: Text(device.eui64),
              subtitle: Text(_formatTimestamp(device.timestamp)),
            )),
          ],
        ),
      ),
    );
  }
}