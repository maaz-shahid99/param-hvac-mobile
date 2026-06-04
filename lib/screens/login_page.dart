import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'forgot_password_page.dart';

enum _Mode { signIn, createOrg, joinOrg }

/// Sign in / create an organization (admin) / join an existing org by code
/// (member) against the Cloud Server, with a one-time cloud-URL setup.
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
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _orgCode = TextEditingController();
  _Mode _mode = _Mode.signIn;
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
    _name.dispose();
    _phone.dispose();
    _orgCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthService>();
    if (auth.baseUrl.isEmpty) {
      await _showServerUrlDialog();
      if (auth.baseUrl.isEmpty) return;
    }
    setState(() => _busy = true);
    bool ok;
    switch (_mode) {
      case _Mode.signIn:
        ok = await auth.login(_email.text.trim(), _password.text);
        break;
      case _Mode.createOrg:
        ok = await auth.register(
          bootstrapToken: _bootstrap.text.trim(),
          tenantName: _tenant.text.trim(),
          name: _name.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text,
        );
        break;
      case _Mode.joinOrg:
        ok = await auth.join(
          orgCode: _orgCode.text.trim().toUpperCase(),
          name: _name.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text,
        );
        break;
    }
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
            hintText: 'http://<server-ip>:8002',
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

  String get _title => switch (_mode) {
        _Mode.signIn => 'Sign in',
        _Mode.createOrg => 'Create organization',
        _Mode.joinOrg => 'Join organization',
      };

  String get _cta => switch (_mode) {
        _Mode.signIn => 'Sign in',
        _Mode.createOrg => 'Create & sign in',
        _Mode.joinOrg => 'Request to join',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
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

                    // --- org identity (create vs join) ---
                    if (_mode == _Mode.createOrg) ...[
                      _field(_tenant, 'Organization name', Icons.business_outlined),
                      const SizedBox(height: 14),
                      _field(_bootstrap, 'Bootstrap token', Icons.vpn_key_outlined),
                      const SizedBox(height: 14),
                    ],
                    if (_mode == _Mode.joinOrg) ...[
                      _field(_orgCode, 'Organization code', Icons.qr_code_2_outlined,
                          caps: true),
                      const SizedBox(height: 14),
                    ],

                    // --- person (register/join) ---
                    if (_mode != _Mode.signIn) ...[
                      _field(_name, 'Your name', Icons.person_outline),
                      const SizedBox(height: 14),
                      _field(_phone, 'Phone (for SMS alerts)', Icons.phone_outlined,
                          keyboard: TextInputType.phone),
                      const SizedBox(height: 14),
                    ],

                    // --- credentials ---
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
                            : Text(_cta),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // --- mode switches ---
                    if (_mode == _Mode.signIn) ...[
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _mode = _Mode.joinOrg),
                        child: const Text('Join an organization with a code'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _mode = _Mode.createOrg),
                        child: const Text('Set up a new organization (admin)'),
                      ),
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
                    ] else
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _mode = _Mode.signIn),
                        child: const Text('Have an account? Sign in'),
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

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? keyboard, bool caps = false}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}
