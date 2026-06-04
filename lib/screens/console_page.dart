import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../ble_service.dart';

/// Full-screen live console, opened from the navigation drawer.
/// Logs read top -> bottom (oldest first); the view follows the newest line and
/// scrolls when it overflows. When connected to a bridge, a manual command bar
/// lets you send raw commands to the hardware.
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final _scroll = ScrollController();
  final _cmd = TextEditingController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _cmd.dispose();
    super.dispose();
  }

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

  void _send(BLEService ble) {
    final text = _cmd.text.trim();
    if (text.isEmpty) return;
    ble.sendRawCommand(text);
    _cmd.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BLEService>();
    final logs = ble.logs;
    final canSend =
        ble.isConnected && ble.authState == BridgeAuthState.authenticated;

    // Follow the newest line — but only if the user is already near the bottom,
    // so scrolling up to read history isn't yanked away on each new log.
    if (logs.length != _lastCount) {
      _lastCount = logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        if (pos.pixels >= pos.maxScrollExtent - 120) {
          _scroll.jumpTo(pos.maxScrollExtent);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.vertical_align_bottom),
            tooltip: 'Jump to latest',
            onPressed: () {
              if (_scroll.hasClients) {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              }
            },
          ),
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
      body: Column(
        children: [
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text('No logs yet',
                        style: Theme.of(context).textTheme.bodyMedium))
                : ListView.builder(
                    controller: _scroll,
                    // chronological: oldest at the top, newest at the bottom
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: logs.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        logs[index],
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                      ),
                    ),
                  ),
          ),
          // Manual command bar — only usable on an authenticated bridge session.
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cmd,
                      enabled: canSend,
                      style: const TextStyle(fontFamily: 'monospace'),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => canSend ? _send(ble) : null,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.chevron_right),
                        hintText: canSend
                            ? 'Manual command (e.g. SYS?, NODES?, commissioner_start)'
                            : 'Connect + authenticate a bridge to send commands',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    tooltip: 'Send',
                    onPressed: canSend ? () => _send(ble) : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
