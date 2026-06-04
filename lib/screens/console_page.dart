import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../ble_service.dart';

/// Full-screen live console (BLE/log stream), opened from the navigation drawer.
/// Replaces the fixed panel that used to sit at the bottom of the home screen.
class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});

  Future<void> _export(BuildContext context, BLEService ble) async {
    try {
      final logs = ble.exportLogs();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/thread_commissioner_logs.txt');
      await file.writeAsString(logs);
      await Share.shareXFiles([XFile(file.path)], subject: 'Thread Commissioner Logs');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BLEService>();
    final logs = ble.logs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export logs',
            onPressed: () => _export(context, ble),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: ble.clearLogs,
          ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Text('No logs yet', style: Theme.of(context).textTheme.bodyMedium))
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    log,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                  ),
                );
              },
            ),
    );
  }
}
