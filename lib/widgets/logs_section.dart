import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../ble_service.dart';

class LogsSection extends StatelessWidget {
  final BLEService bleService;
  const LogsSection({super.key, required this.bleService});

  Future<void> _exportLogs(BuildContext context) async {
    try {
      final logs = bleService.exportLogs();
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/thread_commissioner_logs.txt');
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
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Console Logs', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(icon: const Icon(Icons.share, size: 18), onPressed: () => _exportLogs(context)),
                IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: bleService.clearLogs),
              ],
            ),
          ),
          Expanded(
            child: bleService.logs.isEmpty
                ? Center(child: Text('No logs yet', style: Theme.of(context).textTheme.bodySmall))
                : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: bleService.logs.length,
              itemBuilder: (context, index) {
                final log = bleService.logs[bleService.logs.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(log,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace', fontSize: 11,
                      )),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}