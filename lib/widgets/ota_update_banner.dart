import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_api.dart';

/// In-app prompt for OPTIONAL firmware updates the manufacturer published. Polls
/// the cloud every 60s; if a newer optional build is available (and not yet
/// approved), shows a banner. An admin can tap "Update now" to approve it — the
/// gateway then applies it on its next OTA poll. Mandatory updates don't appear
/// here (the fleet auto-applies them). Self-hides when not signed in or nothing's
/// available, so it's safe to drop at the top of any screen.
class OtaUpdateBanner extends StatefulWidget {
  const OtaUpdateBanner({super.key});

  @override
  State<OtaUpdateBanner> createState() => _OtaUpdateBannerState();
}

class _OtaUpdateBannerState extends State<OtaUpdateBanner> {
  List<Map<String, dynamic>> _updates = [];
  final Set<String> _approving = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final auth = context.read<AuthService>();
    if (auth.status != AuthStatus.signedIn || !auth.api.isConfigured) {
      if (_updates.isNotEmpty && mounted) setState(() => _updates = []);
      return;
    }
    try {
      final list = await auth.api.otaAvailable();
      final pending = list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((u) => u['approved'] != true)
          .toList();
      if (mounted) setState(() => _updates = pending);
    } catch (_) {
      // best-effort; keep the last state on a transient failure
    }
  }

  Future<void> _approve(Map<String, dynamic> u) async {
    final auth = context.read<AuthService>();
    final kind = (u['kind'] ?? '').toString();
    final version = (u['version'] as num?)?.toInt() ?? 0;
    setState(() => _approving.add(kind));
    try {
      await auth.api.approveOta(kind, version);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Update approved — it will install on the next device check-in.'),
      ));
      await _poll();
    } on CloudApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: ${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _approving.remove(kind));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_updates.isEmpty) return const SizedBox.shrink();
    final auth = context.watch<AuthService>();
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: _updates.map((u) {
        final kind = (u['kind'] ?? '').toString().toUpperCase();
        final version = (u['version'] as num?)?.toInt() ?? 0;
        final notes = (u['notes'] ?? '').toString();
        final busy = _approving.contains((u['kind'] ?? '').toString());
        return Card(
          color: cs.secondaryContainer,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.system_update, color: cs.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Firmware update available · $kind v$version',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: cs.onSecondaryContainer)),
                      if (notes.isNotEmpty)
                        Text(notes,
                            style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (auth.isAdmin)
                  FilledButton(
                    onPressed: busy ? null : () => _approve(u),
                    child: busy
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Update now'),
                  )
                else
                  Text('Ask an admin',
                      style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
