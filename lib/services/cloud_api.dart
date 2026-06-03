import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thrown for any non-2xx response so the UI can show a message.
class CloudApiException implements Exception {
  final int statusCode;
  final String message;
  CloudApiException(this.statusCode, this.message);
  @override
  String toString() => 'CloudApiException($statusCode): $message';
}

/// Thin REST client for the AWS Cloud Server (the alerting product).
///
/// Stateless except for [baseUrl] and the bearer [token]; [AuthService] owns
/// the lifecycle and injects the token after login.
class CloudApi {
  String baseUrl; // e.g. https://api.yourdomain.com
  String? token;

  CloudApi({this.baseUrl = '', this.token});

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Uri _u(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json',
        if (auth && token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _decode(http.Response r) async {
    final body = r.body.isEmpty ? {} : jsonDecode(r.body);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = body is Map && body['detail'] != null
          ? body['detail'].toString()
          : 'HTTP ${r.statusCode}';
      throw CloudApiException(r.statusCode, detail);
    }
    return body;
  }

  // ---- auth -----------------------------------------------------------------
  /// Returns the issued JWT (also stored on this client for subsequent calls).
  Future<Map<String, dynamic>> login(String email, String password) async {
    final r = await http.post(_u('/v1/auth/login'),
        headers: _headers(auth: false),
        body: jsonEncode({'email': email, 'password': password}));
    final data = await _decode(r) as Map<String, dynamic>;
    token = data['token'] as String?;
    return data;
  }

  Future<Map<String, dynamic>> register({
    required String bootstrapToken,
    required String tenantName,
    required String email,
    required String password,
  }) async {
    final r = await http.post(_u('/v1/auth/register'),
        headers: _headers(auth: false),
        body: jsonEncode({
          'bootstrap_token': bootstrapToken,
          'tenant_name': tenantName,
          'email': email,
          'password': password,
        }));
    final data = await _decode(r) as Map<String, dynamic>;
    token = data['token'] as String?;
    return data;
  }

  /// Request an emailed reset code. Returns normally even for an unknown email
  /// (the server never reveals whether an account exists).
  Future<void> forgotPassword(String email) async {
    final r = await http.post(_u('/v1/auth/forgot'),
        headers: _headers(auth: false), body: jsonEncode({'email': email}));
    await _decode(r);
  }

  /// Set a new password using the emailed code.
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final r = await http.post(_u('/v1/auth/reset'),
        headers: _headers(auth: false),
        body: jsonEncode({'email': email, 'otp': otp, 'new_password': newPassword}));
    await _decode(r);
  }

  // ---- topology sync --------------------------------------------------------
  Future<Map<String, dynamic>> getTopology() async {
    final r = await http.get(_u('/v1/topology'), headers: _headers());
    return await _decode(r) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> putTopology(Map<String, dynamic> topology) async {
    final r = await http.put(_u('/v1/topology'),
        headers: _headers(), body: jsonEncode({'topology': topology}));
    return await _decode(r) as Map<String, dynamic>;
  }

  // ---- thresholds -----------------------------------------------------------
  Future<Map<String, dynamic>> getThresholds() async {
    final r = await http.get(_u('/v1/thresholds'), headers: _headers());
    return await _decode(r) as Map<String, dynamic>;
  }

  Future<void> putThreshold({
    String scope = 'tenant',
    String scopeId = '',
    required double highC,
    required double deltaC,
    bool enabled = true,
  }) async {
    final r = await http.put(_u('/v1/thresholds'),
        headers: _headers(),
        body: jsonEncode({
          'scope': scope,
          'scope_id': scopeId,
          'high_c': highC,
          'delta_c': deltaC,
          'enabled': enabled,
        }));
    await _decode(r);
  }

  // ---- live temps + alerts --------------------------------------------------
  Future<List<dynamic>> currentTemps() async {
    final r = await http.get(_u('/v1/current'), headers: _headers());
    return (await _decode(r) as Map<String, dynamic>)['sensors'] as List<dynamic>;
  }

  Future<List<dynamic>> alerts({String state = 'open'}) async {
    final r = await http.get(_u('/v1/alerts?state=$state'), headers: _headers());
    return (await _decode(r) as Map<String, dynamic>)['alerts'] as List<dynamic>;
  }

  Future<void> ackAlert(String id) async {
    final r = await http.post(_u('/v1/alerts/$id/ack'), headers: _headers());
    await _decode(r);
  }

  // ---- recipients + gateway key (admin) -------------------------------------
  Future<void> setRecipients({String emails = '', String phones = ''}) async {
    final r = await http.put(_u('/v1/recipients'),
        headers: _headers(),
        body: jsonEncode({'alert_emails': emails, 'alert_phones': phones}));
    await _decode(r);
  }

  /// Returns the raw API key (shown to the operator once) to provision the gateway.
  Future<String> createApiKey(String label) async {
    final r = await http.post(_u('/v1/apikeys'),
        headers: _headers(), body: jsonEncode({'label': label}));
    return (await _decode(r) as Map<String, dynamic>)['api_key'] as String;
  }
}
