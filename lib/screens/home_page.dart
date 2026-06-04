import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ble_service.dart';
import 'onboarding_screen.dart';
import 'settings_page.dart';
import 'diagnostics_page.dart';
import 'system_page.dart';
import 'rack_layout_page.dart';
import 'alerts_thresholds_page.dart';
import 'members_page.dart';
import '../services/auth_service.dart';
import 'qr_scanner_page.dart';
import '../widgets/assign_sensor_dialog.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/disconnected_view.dart';
import '../widgets/quick_actions_card.dart';
import '../utils/auth_guard.dart';
import '../widgets/qr_scan_button.dart';
import '../widgets/commission_history_card.dart';
import 'console_page.dart';
import 'devices_page.dart';
import '../widgets/bridge_auth_card.dart';
import '../widgets/device_scanner_sheet.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;

  const HomePage({super.key, required this.onToggleTheme});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  bool _showOnboarding = true;
  bool _hasEverConnected = false;
  bool _hasAutoPromptedAuth = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    _requestPermissions();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
    setState(() {
      _showOnboarding = !hasSeenOnboarding;
    });
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    setState(() {
      _showOnboarding = false;
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.camera,
    ].request();
  }

  void _showQRScanner(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerPage()),
    );

    if (result == null || !mounted) return;

    if (result is Map<String, String>) {
      final eui64 = result['eui64']!;
      final pskd = result['pskd']!;
      final bleService = Provider.of<BLEService>(context, listen: false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Commissioning $eui64...'),
          duration: const Duration(seconds: 1),
        ),
      );

      await bleService.commissionDevice(eui64, pskd);

      if (!mounted) return;

      final last = bleService.commissionHistory.isNotEmpty
          ? bleService.commissionHistory.last
          : null;

      final success = (last != null && last.eui64 == eui64 && last.success);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '✅ Added successfully: $eui64'
              : '❌ Failed to add: $eui64'),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );

      // On success, let the installer assign the sensor's physical box/slot so
      // it maps to the right dashboard tile (sends MAP|eui|box|slot).
      if (success && mounted) {
        _promptSensorMapping(context, eui64);
      }
    }
  }

  // After a successful commission, let the installer pick this sensor's
  // physical location from the configured rack layout (device is pre-selected).
  void _promptSensorMapping(BuildContext context, String eui64) {
    showAssignSensorDialog(context, presetEui: eui64);
  }

  // Slide-out navigation drawer — replaces the old AppBar action icons.
  Widget _buildDrawer(BuildContext context) {
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
                        Text('Thread Commissioner',
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
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Diagnostics — icon reflects the live BLE connection.
                  Consumer<BLEService>(
                    builder: (context, ble, _) => _drawerItem(
                      context,
                      icon: ble.isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth,
                      iconColor: ble.isConnected ? Colors.green : null,
                      label: 'Diagnostics',
                      page: const DiagnosticsPage(),
                    ),
                  ),
                  _drawerItem(context,
                      icon: Icons.devices_other,
                      label: 'Devices',
                      page: const DevicesPage()),
                  _drawerItem(context,
                      icon: Icons.notifications_active_outlined,
                      label: 'Alerts & Thresholds',
                      page: const AlertsThresholdsPage()),
                  _drawerItem(context,
                      icon: Icons.view_module,
                      label: 'Rack Layout',
                      page: const RackLayoutPage()),
                  // Admin-only: members + who gets email/SMS alerts.
                  Consumer<AuthService>(
                    builder: (context, auth, _) => auth.isAdmin
                        ? _drawerItem(context,
                            icon: Icons.group_outlined,
                            label: 'Members',
                            page: const MembersPage())
                        : const SizedBox.shrink(),
                  ),
                  _drawerItem(context,
                      icon: Icons.tune,
                      label: 'System / Manage',
                      page: const SystemPage()),
                  _drawerItem(context,
                      icon: Icons.terminal,
                      label: 'Console',
                      page: const ConsolePage()),
                  _drawerItem(context,
                      icon: Icons.settings,
                      label: 'Settings',
                      page: SettingsPage(onToggleTheme: widget.onToggleTheme)),
                ],
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

  ListTile _drawerItem(BuildContext context,
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

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }

    return Scaffold(
      // The leading "hamburger" is added automatically because `drawer` is set.
      appBar: AppBar(
        title: const Text('Thread Commissioner'),
      ),
      drawer: _buildDrawer(context),
      body: Consumer<BLEService>(
        builder: (context, bleService, _) {

          if (bleService.isConnected && !_hasEverConnected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hasEverConnected = true);
            });
          }

          if ((bleService.authState == BridgeAuthState.authRequired ||
              bleService.authState == BridgeAuthState.setupRequired) &&
              !_hasAutoPromptedAuth) {

            _hasAutoPromptedAuth = true;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (dialogContext) => Dialog(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    child: BridgeAuthCard(
                      bleService: bleService,
                      onSuccess: () {
                        Navigator.pop(dialogContext);
                      },
                    ),
                  ),
                );
              }
            });
          }

          return Column(
            children: [
              ConnectionStatusCard(bleService: bleService),
              Expanded(
                child: (!bleService.isConnected && !_hasEverConnected)
                    ? DisconnectedView(bleService: bleService)
                    : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!bleService.isConnected)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Align(
                            alignment: Alignment.centerLeft, // Aligns it to the left like Quick Actions
                            child: ActionChip(
                              avatar: const Icon(Icons.bluetooth_searching, size: 18),
                              label: const Text('Reconnect to Bridge'),
                              padding: const EdgeInsets.all(8),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (context) => const DeviceScannerSheet(),
                                );
                              },
                            ),
                          ),
                        ),

                      QuickActionsCard(onScanQR: () => _showQRScanner(context)),
                      const SizedBox(height: 16),
                      QRScanButton(onTap: () {
                        runWithAuthGuard(context, () => _showQRScanner(context));
                      }),
                      const SizedBox(height: 16),
                      CommissionHistoryCard(bleService: bleService),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}