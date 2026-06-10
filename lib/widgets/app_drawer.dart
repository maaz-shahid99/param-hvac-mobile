import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../services/auth_service.dart';
import '../screens/diagnostics_page.dart';
import '../screens/devices_page.dart';
import '../screens/env_data_page.dart';
import '../screens/crash_reports_page.dart';
import '../screens/alerts_thresholds_page.dart';
import '../screens/rack_layout_page.dart';
import '../screens/members_page.dart';
import '../screens/system_page.dart';
import '../screens/console_page.dart';
import '../screens/settings_page.dart';

/// Shared navigation drawer used by both the admin installer home and the member
/// monitoring home. Role-aware: installer/Bluetooth entries (Diagnostics,
/// Console, System/Manage) are admin-only; everything else is visible to all,
/// with the destination screens enforcing their own read-only behaviour for
/// members.
class AppDrawer extends StatelessWidget {
  final VoidCallback onToggleTheme;
  const AppDrawer({super.key, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header: app + signed-in user.
            Consumer<AuthService>(
              builder: (context, auth, _) => DrawerHeader(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(color: scheme.primaryContainer),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.thermostat, size: 36, color: scheme.onPrimaryContainer),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('HVAC Monitor',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (auth.email.isNotEmpty)
                          Text('${auth.email}  ·  ${auth.role}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Consumer<AuthService>(
                builder: (context, auth, _) => ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Diagnostics (Bluetooth) — admin/installer only, mobile only.
                    if (auth.isAdmin && !kIsWeb)
                      Consumer<BLEService>(
                        builder: (context, ble, _) => _item(
                          context,
                          icon: ble.isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth,
                          iconColor: ble.isConnected ? Colors.green : null,
                          label: 'Diagnostics',
                          page: const DiagnosticsPage(),
                        ),
                      ),
                    _item(context,
                        icon: Icons.devices_other,
                        label: 'Devices',
                        page: const DevicesPage()),
                    _item(context,
                        icon: Icons.notifications_active_outlined,
                        label: 'Alerts & Thresholds',
                        page: const AlertsThresholdsPage()),
                    _item(context,
                        icon: Icons.view_module,
                        label: 'Rack Layout',
                        page: const RackLayoutPage()),
                    _item(context,
                        icon: Icons.insights_outlined,
                        label: 'Environment & Logs',
                        page: const EnvDataPage()),
                    // Crash Reports = firmware diagnostics — admin only.
                    if (auth.isAdmin)
                      _item(context,
                          icon: Icons.bug_report_outlined,
                          label: 'Crash Reports',
                          page: const CrashReportsPage()),
                    _item(context,
                        icon: Icons.group_outlined,
                        label: 'Members',
                        page: const MembersPage()),
                    // Admin-only installer tools — need a connected bridge, so
                    // they're hidden on the web.
                    if (auth.isAdmin && !kIsWeb) ...[
                      _item(context,
                          icon: Icons.tune,
                          label: 'System / Manage',
                          page: const SystemPage()),
                      _item(context,
                          icon: Icons.terminal,
                          label: 'Console',
                          page: const ConsolePage()),
                    ],
                    _item(context,
                        icon: Icons.settings,
                        label: 'Settings',
                        page: SettingsPage(onToggleTheme: onToggleTheme)),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.pop(context); // close the drawer
                context.read<AuthService>().signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  ListTile _item(BuildContext context,
      {required IconData icon,
      required String label,
      required Widget page,
      Color? iconColor}) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(label),
      onTap: () {
        Navigator.pop(context); // close the drawer first
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      },
    );
  }
}
