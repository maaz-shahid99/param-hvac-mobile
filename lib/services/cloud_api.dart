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

  // ---- commissioned-device roster (tenant-scoped) ---------------------------
  Future<List<dynamic>> getDevices() async {
    final r = await http.get(_u('/v1/devices'), headers: _headers());
    return (await _decode(r) as Map<String, dynamic>)['devices'] as List<dynamic>;
  }

  /// Additive merge — upserts each device, never removes ones not listed.
  Future<void> putDevices(List<Map<String, dynamic>> devices) async {
    final r = await http.put(_u('/v1/devices'),
        headers: _headers(), body: jsonEncode({'devices': devices}));
    await _decode(r);
  }

  Future<void> deleteDevice(String eui) async {
    final r = await http.delete(_u('/v1/devices/$eui'), headers: _headers());
    await _decode(r);
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

  // ---- tenant settings (alert granularity) ----------------------------------
  /// 'sensor' (one alert per sensor on its hottest probe) or 'probe' (each
  /// mapped probe alerts independently at its own exhaust).
  Future<String> getAlertGranularity() async {
    final r = await http.get(_u('/v1/settings'), headers: _headers());
    final data = await _decode(r) as Map<String, dynamic>;
    return (data['alert_granularity'] as String?) ?? 'sensor';
  }

  Future<void> setAlertGranularity(String value) async {
    final r = await http.put(_u('/v1/settings'),
        headers: _headers(), body: jsonEncode({'alert_granularity': value}));
    await _decode(r);
  }

  /// Full settings map (alert_granularity + collect_interval_s).
  Future<Map<String, dynamic>> getSettings() async {
    final r = await http.get(_u('/v1/settings'), headers: _headers());
    return await _decode(r) as Map<String, dynamic>;
  }

  /// How often (seconds) devices sample/forward data. Clamped 10..3600 server-side.
  Future<void> setCollectInterval(int seconds) async {
    final r = await http.put(_u('/v1/settings'),
        headers: _headers(), body: jsonEncode({'collect_interval_s': seconds}));
    await _decode(r);
  }

  // ---- environmental data (router/gateway BME) ------------------------------
  Future<List<dynamic>> envCurrent() async {
    final r = await http.get(_u('/v1/env/current'), headers: _headers());
    return (await _decode(r) as Map<String, dynamic>)['env'] as List<dynamic>;
  }

  /// Every probe of every mapped sensor (all probes, labeled by location or
  /// "Probe N"); excludes fully-unmapped sensors. For the Environment & Logs view.
  Future<List<dynamic>> envProbes() async {
    final r = await http.get(_u('/v1/env/probes'), headers: _headers());
    return (await _decode(r) as Map<String, dynamic>)['probes'] as List<dynamic>;
  }

  // ---- firmware OTA (optional-update prompt) --------------------------------
  /// OPTIONAL firmware updates newer than the fleet's current version, for the
  /// in-app "update available" prompt. Each: {kind, version, current, notes, approved}.
  /// (Mandatory updates aren't listed — the gateway auto-applies them.)
  Future<List<dynamic>> otaAvailable() async {
    final r = await http.get(_u('/v1/ota/available'), headers: _headers());
    return (await _decode(r) as Map<String, dynamic>)['updates'] as List<dynamic>;
  }

  /// Admin approves an optional update; the gateway applies it on its next poll.
  Future<void> approveOta(String kind, int version) async {
    final r = await http.post(_u('/v1/ota/approve'),
        headers: _headers(), body: jsonEncode({'kind': kind, 'version': version}));
    await _decode(r);
  }

  // ---- firmware crash reports -----------------------------------------------
  Future<List<dynamic>> crashes() async {
    final r = await http.get(_u('/v1/crashes'), headers: _headers());
    return (await _decode(r) as Map<String, dynamic>)['crashes'] as List<dynamic>;
  }

  /// Fetch a CSV export endpoint's body (raw text) for saving/sharing as a file.
  Future<String> fetchCsv(String path) async {
    final r = await http.get(_u(path), headers: _headers());
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw CloudApiException(r.statusCode, 'HTTP ${r.statusCode}');
    }
    return r.body;
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
