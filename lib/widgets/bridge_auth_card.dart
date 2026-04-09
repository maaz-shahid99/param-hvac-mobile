import 'package:flutter/material.dart';
import '../ble_service.dart';

class BridgeAuthCard extends StatefulWidget {
  final BLEService bleService;
  final VoidCallback? onSuccess;

  const BridgeAuthCard({super.key, required this.bleService, this.onSuccess});

  @override
  State<BridgeAuthCard> createState() => _BridgeAuthCardState();
}

class _BridgeAuthCardState extends State<BridgeAuthCard> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  bool _hasTriggeredSuccess = false; // NEW: The safety lock

  @override
  void initState() {
    super.initState();
    // Listen to BLE state changes to close dialog on success
    widget.bleService.addListener(_checkAuthState);
  }

  @override
  void dispose() {
    widget.bleService.removeListener(_checkAuthState);
    _pinController.dispose();
    super.dispose();
  }

  void _checkAuthState() {
    if (widget.bleService.authState == BridgeAuthState.authenticated) {
      // NEW: Check the lock before doing anything
      if (mounted && !_hasTriggeredSuccess) {
        _hasTriggeredSuccess = true; // Lock it immediately
        setState(() => _isLoading = false);
        if (widget.onSuccess != null) {
          widget.onSuccess!(); // This fires the Navigator.pop safely
        }
      }
    } else if (widget.bleService.authState == BridgeAuthState.authRequired ||
        widget.bleService.authState == BridgeAuthState.setupRequired) {
      // If auth failed, stop the loading spinner
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
        _pinController.clear();
      }
    }
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN must be at least 4 characters')),
      );
      return;
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      if (widget.bleService.authState == BridgeAuthState.setupRequired) {
        await widget.bleService.setupBridgePin(pin);
      } else {
        await widget.bleService.authenticateBridge(pin);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSetup = widget.bleService.authState == BridgeAuthState.setupRequired;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSetup ? Icons.lock_person : Icons.lock_outline,
              size: 64,
              color: isSetup ? Colors.purple : Colors.orange,
            ),
            const SizedBox(height: 16),
            Text(
              isSetup ? 'First-Time Setup' : 'Bridge Locked',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSetup
                  ? 'Create a new PIN to secure this Thread Bridge.'
                  : 'Enter your PIN to unlock the session.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: isSetup ? 'New PIN' : 'Enter PIN',
                prefixIcon: const Icon(Icons.password),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSetup ? Colors.purple : Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : Text(isSetup ? 'Set PIN & Unlock' : 'Unlock Session', style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}