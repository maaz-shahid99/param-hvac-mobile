import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

/// Two-step password reset against the Cloud Server:
///   1) enter email -> server emails a 6-digit code
///   2) enter code + new password -> password is changed, back to sign-in.
class ForgotPasswordPage extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordPage({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : null,
    ));
  }

  Future<void> _sendCode() async {
    final auth = context.read<AuthService>();
    if (_email.text.trim().isEmpty) {
      _toast('Enter your email', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await auth.requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _codeSent = true;
    });
    if (ok) {
      _toast('If that email has an account, a code is on its way.');
    } else {
      _toast(auth.error ?? 'Could not send the code', error: true);
    }
  }

  Future<void> _reset() async {
    final auth = context.read<AuthService>();
    if (_otp.text.trim().length < 4) {
      _toast('Enter the code from your email', error: true);
      return;
    }
    if (_password.text.length < 6) {
      _toast('Password must be at least 6 characters', error: true);
      return;
    }
    if (_password.text != _confirm.text) {
      _toast('Passwords do not match', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await auth.resetPassword(
      email: _email.text,
      otp: _otp.text,
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context);
      _toast('Password changed — sign in with your new password.');
    } else {
      _toast(auth.error ?? 'Reset failed', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'Enter the code we emailed you, then choose a new password.'
                  : 'Enter your account email and we\'ll send a 6-digit reset code.',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // ---- email (always shown; locked once the code is sent) ----------
            TextField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),

            if (!_codeSent) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _sendCode,
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send code'),
              ),
            ] else ...[
              const SizedBox(height: 14),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Reset code',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                onSubmitted: (_) => _reset(),
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _reset,
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Reset password'),
              ),
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: const Text('Resend code'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
