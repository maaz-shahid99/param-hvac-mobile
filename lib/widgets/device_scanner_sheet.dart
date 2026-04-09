import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';

class DeviceScannerSheet extends StatefulWidget {
  const DeviceScannerSheet({super.key});

  @override
  State<DeviceScannerSheet> createState() => _DeviceScannerSheetState();
}

class _DeviceScannerSheetState extends State<DeviceScannerSheet> {
  bool _isConnecting = false;
  String? _connectingDeviceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BLEService>(context, listen: false).startScan();
    });
  }

  // --- CHANGED: Removed BuildContext passing. Uses the State's native context ---
  void _showConnectionError(BLEService bleService, BluetoothDevice device, int rssi) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Connection Failed'),
          ],
        ),
        content: const Text(
            'Cannot connect to device. The Bluetooth pairing cache might be corrupted, or the device is out of range.'),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          // 1. FORGET BUTTON
          ActionChip(
            avatar: const Icon(Icons.bluetooth_disabled, size: 18),
            label: const Text('Forget'),
            backgroundColor: Colors.red.withOpacity(0.1),
            side: const BorderSide(color: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext); // Close error dialog
              try {
                await device.removeBond();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Device forgotten from Bluetooth cache. Please try scanning again.')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not remove bond. You may need to unpair from phone settings.')),
                  );
                }
              }
            },
          ),

          // 2. RECONNECT BUTTON
          ActionChip(
            avatar: const Icon(Icons.refresh, size: 18),
            label: const Text('Reconnect'),
            backgroundColor: Colors.blue.withOpacity(0.1),
            side: const BorderSide(color: Colors.blue),
            onPressed: () {
              Navigator.pop(dialogContext); // Close error dialog
              _attemptConnection(bleService, device, rssi); // Try again using native context
            },
          ),
        ],
      ),
    );
  }

  // --- CHANGED: Removed BuildContext passing. Uses the State's native context ---
  Future<void> _attemptConnection(BLEService bleService, BluetoothDevice device, int rssi) async {
    if (_isConnecting) return; // Prevent double-taps

    setState(() {
      _isConnecting = true;
      _connectingDeviceId = device.remoteId.str;
    });

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connecting to ${device.platformName.isEmpty ? "Device" : device.platformName}...'), duration: const Duration(seconds: 2)),
      );

      await bleService.connectToTarget(device, rssi);

      if (!bleService.isConnected) {
        throw Exception("Connection was terminated immediately by Android.");
      }

      // --- SUCCESS! ---
      if (mounted) {
        // Stop the spinner just to be clean
        setState(() {
          _isConnecting = false;
          _connectingDeviceId = null;
        });
        // Safely close the sheet using the main State context
        Navigator.of(context).pop();
      }

    } catch (e) {
      // --- FAILURE! ---
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectingDeviceId = null;
        });
        _showConnectionError(bleService, device, rssi);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BLEService>(
        builder: (context, bleService, _) {
          return Container(
            padding: const EdgeInsets.all(16),
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Available Devices', style: Theme.of(context).textTheme.titleLarge),
                    if (bleService.isScanning)
                      const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _isConnecting ? null : () => bleService.startScan(),
                      ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: bleService.scanResults.isEmpty
                      ? Center(
                    child: Text(
                      bleService.isScanning ? 'Scanning for devices...' : 'No devices found.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                      : ListView.builder(
                    itemCount: bleService.scanResults.length,
                    itemBuilder: (context, index) {
                      final result = bleService.scanResults[index];
                      final deviceName = result.device.platformName.isNotEmpty
                          ? result.device.platformName
                          : 'Unknown Bridge';

                      return Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.bluetooth, color: Colors.blue),
                          title: Text(deviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(result.device.remoteId.str),
                          trailing: _connectingDeviceId == result.device.remoteId.str
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text('${result.rssi} dBm'),
                          onTap: _isConnecting
                              ? null
                          // --- CHANGED: Passed only the strictly required variables ---
                              : () => _attemptConnection(bleService, result.device, result.rssi),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
    );
  }
}