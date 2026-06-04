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
  static const _kRole = 'cloud_role';
  static const _kMemberStatus = 'cloud_member_status';
  static const _kName = 'cloud_name';
  static const _kPhone = 'cloud_phone';
  static const _kOrgCode = 'cloud_org_code';

  final _secure = const FlutterSecureStorage();
  final CloudApi api = CloudApi();

  AuthStatus _status = AuthStatus.unknown;
  String _baseUrl = '';
  String _email = '';
  String _tenantId = '';
  String _role = 'member';
  String _memberStatus = 'active';   // pending | active | rejected
  String _name = '';
  String _phone = '';
  String _orgCode = '';
  String? _error;

  AuthStatus get status => _status;
  String get baseUrl => _baseUrl;
  String get email => _email;
  String get tenantId => _tenantId;
  String get role => _role;
  bool get isAdmin => _role == 'admin';
  String get memberStatus => _memberStatus;
  bool get isPending => _memberStatus == 'pending';
  String get name => _name;
  String get phone => _phone;
  String get orgCode => _orgCode;
  String? get error => _error;

  /// Restore a persisted session on startup. Always ends in signedOut/signedIn.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? '';
    _email = prefs.getString(_kEmail) ?? '';
    _role = prefs.getString(_kRole) ?? 'member';
    _memberStatus = prefs.getString(_kMemberStatus) ?? 'active';
    _name = prefs.getString(_kName) ?? '';
    _phone = prefs.getString(_kPhone) ?? '';
    _orgCode = prefs.getString(_kOrgCode) ?? '';
    api.baseUrl = _baseUrl;
    final token = await _secure.read(key: _kToken);
    if (token != null && token.isNotEmpty && _baseUrl.isNotEmpty) {
      api.token = token;
      _status = AuthStatus.signedIn;
      notifyListeners();
      // Refresh role/status from the server (e.g. a pending member just got
      // approved). Best-effort — keep the cached state if offline.
      refreshMe();
      return;
    }
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  /// Pull the caller's current role/status (used on restore + by the pending
  /// screen to poll for approval). Signs out if the token is no longer valid.
  Future<void> refreshMe() async {
    if (_status != AuthStatus.signedIn) return;
    try {
      final me = await api.me();
      _role = (me['role'] ?? _role) as String;
      _memberStatus = (me['status'] ?? _memberStatus) as String;
      _name = (me['name'] ?? _name) as String;
      _phone = (me['phone'] ?? _phone) as String;
      await _persistProfile();
      notifyListeners();
    } on CloudApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await signOut();
      }
    } catch (_) {
      // offline — keep cached state
    }
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
    String name = '',
    String phone = '',
  }) async {
    return _run(
      () => api.register(
        bootstrapToken: bootstrapToken,
        tenantName: tenantName,
        email: email,
        password: password,
        name: name,
        phone: phone,
      ),
      email,
    );
  }

  /// Register as a member of an existing org (by org code). Ends in a pending
  /// session until an admin approves.
  Future<bool> join({
    required String orgCode,
    required String email,
    required String password,
    String name = '',
    String phone = '',
  }) async {
    return _run(
      () => api.join(
        orgCode: orgCode,
        email: email,
        password: password,
        name: name,
        phone: phone,
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
      _role = (data['role'] ?? 'member') as String;
      _memberStatus = (data['status'] ?? 'active') as String;
      _name = (data['name'] ?? '') as String;
      _phone = (data['phone'] ?? '') as String;
      _orgCode = (data['org_code'] ?? _orgCode) as String;
      _email = email;
      await _secure.write(key: _kToken, value: api.token);
      await _persistProfile();
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

  Future<void> _persistProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, _email);
    await prefs.setString(_kRole, _role);
    await prefs.setString(_kMemberStatus, _memberStatus);
    await prefs.setString(_kName, _name);
    await prefs.setString(_kPhone, _phone);
    await prefs.setString(_kOrgCode, _orgCode);
  }

  Future<void> signOut() async {
    api.token = null;
    _tenantId = '';
    _role = 'member';
    _memberStatus = 'active';
    _name = '';
    _phone = '';
    _orgCode = '';
    _status = AuthStatus.signedOut;
    await _secure.delete(key: _kToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMemberStatus);
    await prefs.remove(_kRole);
    notifyListeners();
  }
}
