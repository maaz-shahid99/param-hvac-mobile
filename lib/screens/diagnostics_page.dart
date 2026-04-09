import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Diagnostics')),
      body: Consumer<BLEService>(
        builder: (context, bleService, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildInfoCard(
              context,
              'Connection Status',
              bleService.isConnected ? 'Connected' : 'Disconnected',
              Icons.bluetooth,
              bleService.isConnected ? Colors.green : Colors.red,
            ),
            _buildInfoCard(
              context,
              'Device Name',
              bleService.deviceName,
              Icons.devices,
              Colors.blue,
            ),
            _buildInfoCard(
              context,
              'Signal Strength (RSSI)',
              '${bleService.rssi} dBm',
              Icons.signal_cellular_alt,
              _getRssiColor(bleService.rssi),
            ),
            _buildInfoCard(
              context,
              'Service UUID',
              BLEService.serviceUuid,
              Icons.settings_input_component,
              Colors.purple,
            ),
            _buildInfoCard(
              context,
              'Characteristic UUID',
              BLEService.charUuid,
              Icons.settings_input_antenna,
              Colors.orange,
            ),
            _buildInfoCard(
              context,
              'Total Commissioned',
              '${bleService.commissionHistory.length} devices',
              Icons.history,
              Colors.teal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle:
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -75) return Colors.orange;
    return Colors.red;
  }
}