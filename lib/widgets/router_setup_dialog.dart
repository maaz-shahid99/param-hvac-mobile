import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_service.dart';
import '../services/auth_service.dart';
import '../services/cloud_api.dart';

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
  final _discController = TextEditingController();
  final _cloudController = TextEditingController();
  final _cloudKeyController = TextEditingController();
  bool _isLoading = false;
  bool _mintingKey = false;

  @override
  void initState() {
    super.initState();
    // Prefill the cloud URL from the signed-in session so the operator only
    // needs to mint/paste the per-site gateway key.
    _cloudController.text = context.read<AuthService>().baseUrl;
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    _zoneController.dispose();
    _netNameController.dispose();
    _discController.dispose();
    _cloudController.dispose();
    _cloudKeyController.dispose();
    super.dispose();
  }

  Future<void> _mintKey() async {
    setState(() => _mintingKey = true);
    try {
      final key = await context.read<AuthService>().api.createApiKey('gateway');
      _cloudKeyController.text = key;
    } on CloudApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not reach the cloud server.')));
      }
    } finally {
      if (mounted) setState(() => _mintingKey = false);
    }
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
        discoveryUrl: _discController.text.trim(),
        cloudUrl: _cloudController.text.trim(),
        cloudKey: _cloudKeyController.text.trim(),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _discController,
                decoration: const InputDecoration(
                  labelText: 'Discovery Server URL (Optional)',
                  prefixIcon: Icon(Icons.dns),
                  hintText: 'http://10.14.98.109:8000',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cloudController,
                decoration: const InputDecoration(
                  labelText: 'Cloud Alerting URL (Optional)',
                  prefixIcon: Icon(Icons.cloud),
                  hintText: 'https://api.yourdomain.com',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cloudKeyController,
                decoration: InputDecoration(
                  labelText: 'Gateway API Key (Optional)',
                  prefixIcon: const Icon(Icons.vpn_key),
                  suffixIcon: _mintingKey
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          tooltip: 'Generate key',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: _mintKey,
                        ),
                ),
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