import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

/// Admin-only: approve/reject join requests and control who receives email /
/// SMS alerts. Reachable from the home AppBar when the signed-in user is admin.
class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final m = await context.read<AuthService>().api.listMembers();
      if (!mounted) return;
      setState(() { _members = m; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final pending = _members.where((m) => m['status'] == 'pending').toList();
    final active = _members.where((m) => m['status'] == 'active').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load members.\n$_error',
                      textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _orgCodeCard(auth.orgCode),
                      if (pending.isNotEmpty) ...[
                        _sectionTitle('Join requests (${pending.length})'),
                        ...pending.map(_pendingTile),
                      ],
                      _sectionTitle('Members (${active.length})'),
                      if (active.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No active members yet.',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ...active.map(_activeTile),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _orgCodeCard(String code) => Card(
        child: ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: const Text('Organization code'),
          subtitle: Text(code.isEmpty ? '—' : code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 2)),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
            onPressed: code.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: code));
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied — share it with members to join')));
                  },
          ),
        ),
      );

  Widget _pendingTile(Map<String, dynamic> m) {
    final label = (m['name'] as String?)?.isNotEmpty == true ? m['name'] : m['email'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${m['email']}${(m['phone'] ?? '').isNotEmpty ? '  ·  ${m['phone']}' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _guard(() =>
                      context.read<AuthService>().api.rejectMember(m['id'] as String)),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _guard(() =>
                      context.read<AuthService>().api.approveMember(m['id'] as String)),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeTile(Map<String, dynamic> m) {
    final api = context.read<AuthService>().api;
    final id = m['id'] as String;
    final phone = (m['phone'] ?? '') as String;
    final isAdmin = m['role'] == 'admin';
    final label = (m['name'] as String?)?.isNotEmpty == true ? m['name'] : m['email'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text('$label',
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (isAdmin) ...[
                          const SizedBox(width: 6),
                          const Chip(
                            label: Text('admin'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ]),
                      Text('${m['email']}${phone.isNotEmpty ? '  ·  $phone' : ''}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),
            // Admin chooses who receives which alerts.
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.email_outlined),
              title: const Text('Email alerts'),
              value: m['email_enabled'] == true,
              onChanged: (v) => _guard(() => api.setMemberNotifications(id, emailEnabled: v)),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.sms_outlined),
              title: const Text('SMS alerts'),
              subtitle: phone.isEmpty ? const Text('No phone number on file') : null,
              value: m['sms_enabled'] == true,
              onChanged: phone.isEmpty
                  ? null
                  : (v) => _guard(() => api.setMemberNotifications(id, smsEnabled: v)),
            ),
          ],
        ),
      ),
    );
  }
}
