import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commission History')),
      body: Consumer<BLEService>(
        builder: (context, bleService, _) {
          if (bleService.commissionHistory.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No devices commissioned yet'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: bleService.commissionHistory.length,
            itemBuilder: (context, index) {
              final device = bleService.commissionHistory.reversed.toList()[index];
              return ListTile(
                leading: Icon(
                  device.success ? Icons.check_circle : Icons.error,
                  color: device.success ? Colors.green : Colors.red,
                ),
                title: Text(device.eui64),
                subtitle: Text(device.timestamp.toString()),
                trailing: Chip(
                  label: Text(device.success ? 'Success' : 'Failed'),
                  backgroundColor: device.success
                      ? Colors.green.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
                ),
              );
            },
          );
        },
      ),
    );
  }
}