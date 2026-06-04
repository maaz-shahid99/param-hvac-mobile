import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ble_service.dart';
import 'onboarding_screen.dart';
import 'qr_scanner_page.dart';
import '../widgets/app_drawer.dart';
import '../widgets/assign_sensor_dialog.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/disconnected_view.dart';
import '../widgets/quick_actions_card.dart';
import '../utils/auth_guard.dart';
import '../widgets/qr_scan_button.dart';
import '../widgets/commission_history_card.dart';
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

      // On success, figure out WHAT we just added: a sensor gets the rack
      // assignment dialog; a router just joins the mesh and needs nothing.
      if (success && mounted) {
        _classifyAndAssign(context, eui64);
      }
    }
  }

  // Auto-detect device type from the mesh role (the user's chosen flow): a
  // sensor starts reporting (shows up in NODES?), a router appears in the C6
  // leader's neighbour roster (ROUTERS?). Only sensors get rack assignment.
  Future<void> _classifyAndAssign(BuildContext context, String eui64) async {
    final ble = Provider.of<BLEService>(context, listen: false);
    final target = eui64.toLowerCase();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Expanded(child: Text('Identifying device on the mesh…')),
        ]),
      ),
    );

    String? kind; // 'sensor' | 'router'
    for (int i = 0; i < 10 && mounted; i++) {
      if (ble.isConnected) {
        ble.requestNodes();
        ble.requestRouters();
      }
      await Future.delayed(const Duration(seconds: 3));
      if (ble.liveRouters.map((e) => e.toLowerCase()).contains(target)) { kind = 'router'; break; }
      if (ble.liveNodes.map((e) => e.toLowerCase()).contains(target)) { kind = 'sensor'; break; }
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close the "identifying" dialog

    if (kind == 'router') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🧭 Router joined the mesh — no rack assignment needed.')));
      return;
    }
    if (kind == 'sensor') {
      showAssignSensorDialog(context, presetEui: eui64);
      return;
    }

    // Couldn't classify in time — ask, so we never wrongly force a router into
    // rack assignment.
    final isRouter = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('What did you add?'),
        content: const Text("Couldn't auto-detect the device type yet. Is this a sensor or a router?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Sensor')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Router')),
        ],
      ),
    );
    if (!mounted || isRouter == null) return;
    if (isRouter) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Router added.')));
    } else {
      showAssignSensorDialog(context, presetEui: eui64);
    }
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
      drawer: AppDrawer(onToggleTheme: widget.onToggleTheme),
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