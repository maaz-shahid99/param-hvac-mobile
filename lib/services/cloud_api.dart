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
    String name = '',
    String phone = '',
  }) async {
    final r = await http.post(_u('/v1/auth/register'),
        headers: _headers(auth: false),
        body: jsonEncode({
          'bootstrap_token': bootstrapToken,
          'tenant_name': tenantName,
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
        }));
    final data = await _decode(r) as Map<String, dynamic>;
    token = data['token'] as String?;
    return data;
  }

  /// Join an existing org by its code — creates a pending member.
  Future<Map<String, dynamic>> join({
    required String orgCode,
    required String email,
    required String password,
    String name = '',
    String phone = '',
  }) async {
    final r = await http.post(_u('/v1/auth/join'),
        headers: _headers(auth: false),
        body: jsonEncode({
          'org_code': orgCode,
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
        }));
    final data = await _decode(r) as Map<String, dynamic>;
    token = data['token'] as String?;
    return data;
  }

  /// The caller's own profile (role/status/...). Used to poll for approval.
  Future<Map<String, dynamic>> me() async {
    final r = await http.get(_u('/v1/me'), headers: _headers());
    return await _decode(r) as Map<String, dynamic>;
  }

  // ---- members (admin) ------------------------------------------------------
  Future<List<Map<String, dynamic>>> listMembers({String state = 'all'}) async {
    final r = await http.get(_u('/v1/members?state=$state'), headers: _headers());
    final data = await _decode(r) as Map<String, dynamic>;
    return (data['members'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> approveMember(String id) async {
    await _decode(await http.post(_u('/v1/members/$id/approve'), headers: _headers()));
  }

  Future<void> rejectMember(String id) async {
    await _decode(await http.post(_u('/v1/members/$id/reject'), headers: _headers()));
  }

  Future<void> setMemberNotifications(String id,
      {bool? emailEnabled, bool? smsEnabled, String? role}) async {
    final body = <String, dynamic>{};
    if (emailEnabled != null) body['email_enabled'] = emailEnabled;
    if (smsEnabled != null) body['sms_enabled'] = smsEnabled;
    if (role != null) body['role'] = role;
    await _decode(await http.put(_u('/v1/members/$id/notifications'),
        headers: _headers(), body: jsonEncode(body)));
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

  /// Mesh routers the gateway has reported, each with `online` + `last_seen`.
  Future<List<dynamic>> routers() async {
    final r = await http.get(_u('/v1/routers'), headers: _headers());
    return (await _decode(r) as Map<String, dynamic>)['routers'] as List<dynamic>;
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
