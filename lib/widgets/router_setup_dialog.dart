import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';

class RouterSetupDialog extends StatefulWidget {
  const RouterSetupDialog({super.key});

  @override
  State<RouterSetupDialog> createState() => _RouterSetupDialogState();
}

class _RouterSetupDialogState extends State<RouterSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passController = TextEditingController();
  final _zoneController = TextEditingController(text: 'Default');
  final _netNameController = TextEditingController(text: 'ThreadNet');
  bool _isLoading = false;

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    _zoneController.dispose();
    _netNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final bleService = Provider.of<BLEService>(context, listen: false);

    try {
      await bleService.provisionWiFi(
        ssid: _ssidController.text.trim(),
        password: _passController.text.trim(),
        zone: _zoneController.text.trim(),
        netName: _netNameController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuration sent! Check logs for connection status.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Router Setup'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi SSID',
                  prefixIcon: Icon(Icons.wifi),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passController,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi Password',
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _zoneController,
                decoration: const InputDecoration(
                  labelText: 'Zone (Optional)',
                  prefixIcon: Icon(Icons.location_on),
                  hintText: 'e.g. ServerRoom',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _netNameController,
                decoration: const InputDecoration(
                  labelText: 'Thread Network Name',
                  prefixIcon: Icon(Icons.hub),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Provision'),
        ),
      ],
    );
  }
}