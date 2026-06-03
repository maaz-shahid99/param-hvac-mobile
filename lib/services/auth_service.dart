import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_api.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Owns the cloud session: the AWS base URL, the JWT (in secure storage), and
/// the signed-in user's tenant/role. Drives the splash -> login -> home gate.
class AuthService extends ChangeNotifier {
  static const _kBaseUrl = 'cloud_base_url';
  static const _kEmail = 'cloud_email';
  static const _kToken = 'cloud_jwt';

  final _secure = const FlutterSecureStorage();
  final CloudApi api = CloudApi();

  AuthStatus _status = AuthStatus.unknown;
  String _baseUrl = '';
  String _email = '';
  String _tenantId = '';
  String _role = 'viewer';
  String? _error;

  AuthStatus get status => _status;
  String get baseUrl => _baseUrl;
  String get email => _email;
  String get tenantId => _tenantId;
  String get role => _role;
  bool get isAdmin => _role == 'admin';
  String? get error => _error;

  /// Restore a persisted session on startup. Always ends in signedOut/signedIn.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? '';
    _email = prefs.getString(_kEmail) ?? '';
    api.baseUrl = _baseUrl;
    final token = await _secure.read(key: _kToken);
    if (token != null && token.isNotEmpty && _baseUrl.isNotEmpty) {
      api.token = token;
      _status = AuthStatus.signedIn;
    } else {
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim();
    api.baseUrl = _baseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, _baseUrl);
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    return _run(() => api.login(email, password), email);
  }

  Future<bool> register({
    required String bootstrapToken,
    required String tenantName,
    required String email,
    required String password,
  }) async {
    return _run(
      () => api.register(
        bootstrapToken: bootstrapToken,
        tenantName: tenantName,
        email: email,
        password: password,
      ),
      email,
    );
  }

  /// Ask the server to email a reset code. True = request accepted (note the
  /// server returns success even for unknown emails, by design).
  Future<bool> requestPasswordReset(String email) async {
    return _runVoid(() => api.forgotPassword(email.trim().toLowerCase()));
  }

  /// Set a new password using the emailed code.
  Future<bool> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    return _runVoid(() => api.resetPassword(
          email: email.trim().toLowerCase(),
          otp: otp.trim(),
          newPassword: newPassword,
        ));
  }

  /// Shared runner for endpoints that need a configured baseUrl but no session
  /// and return no auth payload (forgot/reset). Surfaces [error] on failure.
  Future<bool> _runVoid(Future<void> Function() call) async {
    _error = null;
    if (_baseUrl.isEmpty) {
      _error = 'Set the cloud server URL first.';
      notifyListeners();
      return false;
    }
    try {
      await call();
      return true;
    } on CloudApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not reach the server. Check the URL and your connection.';
    }
    notifyListeners();
    return false;
  }

  Future<bool> _run(Future<Map<String, dynamic>> Function() call, String email) async {
    _error = null;
    if (_baseUrl.isEmpty) {
      _error = 'Set the cloud server URL first.';
      notifyListeners();
      return false;
    }
    try {
      final data = await call();
      _tenantId = (data['tenant_id'] ?? '') as String;
      _role = (data['role'] ?? 'viewer') as String;
      _email = email;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEmail, email);
      await _secure.write(key: _kToken, value: api.token);
      _status = AuthStatus.signedIn;
      notifyListeners();
      return true;
    } on CloudApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not reach the server. Check the URL and your connection.';
    }
    notifyListeners();
    return false;
  }

  Future<void> signOut() async {
    api.token = null;
    _tenantId = '';
    _role = 'viewer';
    _status = AuthStatus.signedOut;
    await _secure.delete(key: _kToken);
    notifyListeners();
  }
}
