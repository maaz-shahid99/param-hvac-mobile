import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../widgets/bridge_auth_card.dart';

void runWithAuthGuard(BuildContext context, VoidCallback action) {
  final bleService = Provider.of<BLEService>(context, listen: false);

  if (!bleService.isConnected) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bridge is disconnected. Please wait for reconnection.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  if (bleService.authState == BridgeAuthState.authenticated) {
    // Already unlocked, run the action immediately
    action();
  } else {
    // Connected but locked. Pop up the Auth Dialog.
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: BridgeAuthCard(
          bleService: bleService,
          onSuccess: () {
            Navigator.pop(dialogContext); // Close the PIN dialog
            action(); // Run the intended action (e.g. Scan QR)
          },
        ),
      ),
    );
  }
}