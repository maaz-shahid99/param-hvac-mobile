import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'forgot_password_page.dart';

/// Email/password sign-in against the AWS Cloud Server, with a register mode
/// (bootstrap a tenant) and a one-time cloud-URL setup. Animated entrance.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _tenant = TextEditingController();
  final _bootstrap = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  bool _obscure = true;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _intro.dispose();
    _email.dispose();
    _password.dispose();
    _tenant.dispose();
    _bootstrap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthService>();
    if (auth.baseUrl.isEmpty) {
      await _showServerUrlDialog();
      if (auth.baseUrl.isEmpty) return;
    }
    setState(() => _busy = true);
    final ok = _registerMode
        ? await auth.register(
            bootstrapToken: _bootstrap.text.trim(),
            tenantName: _tenant.text.trim(),
            email: _email.text.trim(),
            password: _password.text)
        : await auth.login(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok && auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(auth.error!)));
    }
  }

  Future<void> _showServerUrlDialog() async {
    final auth = context.read<AuthService>();
    final controller = TextEditingController(text: auth.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud server URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://api.yourdomain.com',
            labelText: 'Base URL',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      await auth.setBaseUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_registerMode ? 'Create organization' : 'Sign in'),
        actions: [
          IconButton(
            tooltip: 'Cloud server URL',
            icon: const Icon(Icons.dns_outlined),
            onPressed: _showServerUrlDialog,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FadeTransition(
            opacity: _intro,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _intro, curve: Curves.easeOut)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.thermostat, size: 64, color: scheme.primary),
                    const SizedBox(height: 12),
                    Text('HVAC Monitor',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 28),
                    if (_registerMode) ...[
                      TextField(
                        controller: _tenant,
                        decoration: const InputDecoration(
                          labelText: 'Organization name',
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _bootstrap,
                        decoration: const InputDecoration(
                          labelText: 'Bootstrap token',
                          prefixIcon: Icon(Icons.vpn_key_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _busy
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_registerMode ? 'Create & sign in' : 'Sign in'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _registerMode = !_registerMode),
                      child: Text(_registerMode
                          ? 'Have an account? Sign in'
                          : 'Set up a new organization'),
                    ),
                    // Forgot password (sign-in mode only) — email-OTP reset flow.
                    if (!_registerMode)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ForgotPasswordPage(
                                        initialEmail: _email.text.trim()),
                                  ),
                                ),
                        child: const Text('Forgot password?'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
