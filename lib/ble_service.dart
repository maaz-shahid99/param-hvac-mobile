import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

// --- New: Authentication State Enum ---
enum BridgeAuthState {
  unknown,
  authenticating,
  setupRequired,
  authRequired,
  authenticated
}

class CommissionedDevice {
  final String eui64;
  final DateTime timestamp;
  final bool success;

  CommissionedDevice({
    required this.eui64,
    required this.timestamp,
    required this.success,
  });

  Map<String, dynamic> toJson() => {
    'eui64': eui64,
    'timestamp': timestamp.toIso8601String(),
    'success': success,
  };

  factory CommissionedDevice.fromJson(Map<String, dynamic> json) {
    return CommissionedDevice(
      eui64: json['eui64'],
      timestamp: DateTime.parse(json['timestamp']),
      success: json['success'],
    );
  }
}

/// Snapshot of a bridge unit's status, parsed from the firmware's `SYS|...` reply.
/// A Wi-Fi network from a bridge SCAN? reply (for the Router Setup picker).
class WifiNetwork {
  final String ssid;
  final int rssi;          // dBm
  final int enc;           // 0=open, 1=secured (PSK), 2=enterprise
  WifiNetwork({required this.ssid, required this.rssi, required this.enc});
  bool get isEnterprise => enc == 2;
  bool get isOpen => enc == 0;
}

class SystemStatus {
  final String role;       // LEADER / STANDBY
  final int c3Version;     // Bridge (C3) firmware version
  final int c6Version;     // Commissioner (C6) firmware version (-1 = unknown)
  final String commState;  // ACTIVE / DISABLED / ?
  final bool wifiUp;
  final bool uplinkUp;     // discovered display node reachable
  final DateTime updated;

  SystemStatus({
    required this.role,
    required this.c3Version,
    required this.c6Version,
    required this.commState,
    required this.wifiUp,
    required this.uplinkUp,
    required this.updated,
  });

  /// Parse "SYS|role=LEADER|c3=6|c6=7|comm=ACTIVE|wifi=1|node=1".
  static SystemStatus? parse(String line) {
    if (!line.startsWith('SYS|')) return null;
    final map = <String, String>{};
    for (final part in line.substring(4).split('|')) {
      final i = part.indexOf('=');
      if (i > 0) map[part.substring(0, i)] = part.substring(i + 1);
    }
    return SystemStatus(
      role: map['role'] ?? '?',
      c3Version: int.tryParse(map['c3'] ?? '') ?? -1,
      c6Version: int.tryParse(map['c6'] ?? '') ?? -1,
      commState: map['comm'] ?? '?',
      wifiUp: map['wifi'] == '1',
      uplinkUp: map['node'] == '1',
      updated: DateTime.now(),
    );
  }
}

class BLEService extends ChangeNotifier {
  // Constants
  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String charUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const String defaultSecretKey = 'PROD_SECRET_KEY_CHANGE_ME';
  static const String secureStorageKey = 'hmac_secret_key';
  static const String pinStorageKey = 'bridge_auth_pin'; // New: Secure PIN storage

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration scanTimeout = Duration(seconds: 30);
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration writeTimeout = Duration(seconds: 10);
  static const Duration commissionResultTimeout = Duration(seconds: 15);

  // State
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  bool _isScanning = false;
  bool _isConnected = false;
  int _rssi = 0;
  String _deviceName = 'Unknown';
  final List<String> _logs = [];
  final List<CommissionedDevice> _commissionHistory = [];
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _connectionTimer;
  bool _autoReconnect = true;

  // Pending commission state
  Completer<bool>? _pendingCommissionCompleter;
  String? _pendingEui64;
  Timer? _pendingTimer;

  // Authentication State
  BridgeAuthState _authState = BridgeAuthState.unknown;
  String? _lastTriedPin;

  // --- NEW: Scan Results State ---
  List<ScanResult> _scanResults = [];

  // --- Management state (System screen) ---
  SystemStatus? _systemStatus;
  String _otaStatus = '';   // latest OTA progress/result line from the bridge

  // --- Live sensor list (NODES? -> dropdown of currently-reporting EUIs) ---
  List<String> _liveNodes = [];
  final List<String> _nodesAccumulator = [];
  bool _collectingNodes = false;

  // --- Live mesh nodes (ROUTERS? -> C6 gateways+routers; eui -> role 'G'/'R') ---
  Map<String, String> _meshNodes = {};
  final Map<String, String> _meshAccumulator = {};
  bool _collectingMesh = false;

  // --- Probe discovery per sensor (PROBES?<eui> -> ROM list for the assign UI) ---
  final Map<String, List<ProbeReading>> _probesByEui = {};

  // --- Wi-Fi scan results (SCAN? -> Router Setup network picker) ---
  List<WifiNetwork> _wifiNetworks = [];

  // Getters
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  int get rssi => _rssi;
  String get deviceName => _deviceName;
  List<String> get logs => List.unmodifiable(_logs);
  List<CommissionedDevice> get commissionHistory => List.unmodifiable(_commissionHistory);
  bool get autoReconnect => _autoReconnect;
  BridgeAuthState get authState => _authState; // Expose auth state to UI
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults); // Expose scan results
  SystemStatus? get systemStatus => _systemStatus;
  String get otaStatus => _otaStatus;
  List<String> get liveNodes => List.unmodifiable(_liveNodes);
  Map<String, String> get meshNodes => Map.unmodifiable(_meshNodes);
  List<WifiNetwork> get wifiNetworks => List.unmodifiable(_wifiNetworks);

  /// The probes most recently reported for [eui] (from a PROBES?<eui> reply).
  List<ProbeReading> probesFor(String eui) =>
      List.unmodifiable(_probesByEui[eui.trim().toLowerCase()] ?? const <ProbeReading>[]);

  BLEService() {
    _initializeSecretKey();
    _startConnectionMonitoring();
  }

  Future<void> _initializeSecretKey() async {
    try {
      final existingKey = await _secureStorage.read(key: secureStorageKey);
      if (existingKey == null) {
        await _secureStorage.write(key: secureStorageKey, value: defaultSecretKey);
        _addLog('Initialized secure secret key');
      } else {
        _addLog('Loaded existing secret key from secure storage');
      }
    } catch (e) {
      _addLog('Error initializing secret key: $e', isError: true);
    }
  }

  Future<String> _getSecretKey() async {
    try {
      final key = await _secureStorage.read(key: secureStorageKey);
      return key ?? defaultSecretKey;
    } catch (e) {
      _addLog('Error reading secret key, using default: $e', isError: true);
      return defaultSecretKey;
    }
  }

  Future<void> updateSecretKey(String newKey) async {
    try {
      await _secureStorage.write(key: secureStorageKey, value: newKey);
      _addLog('Secret key updated successfully');
    } catch (e) {
      _addLog('Error updating secret key: $e', isError: true);
    }
  }

  void setAutoReconnect(bool value) {
    _autoReconnect = value;
    _addLog('Auto-reconnect ${value ? 'enabled' : 'disabled'}');
    notifyListeners();
  }

  void _addLog(String message, {bool isError = false}) {
    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final prefix = isError ? '❌' : '✓';
    _logs.add('[$timestamp] $prefix $message');
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    notifyListeners();
  }

  void _addCommissionedDevice(String eui64, bool success) {
    _commissionHistory.add(CommissionedDevice(
      eui64: eui64,
      timestamp: DateTime.now(),
      success: success,
    ));
    notifyListeners();
  }

  void _startConnectionMonitoring() {
    _connectionTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_connectedDevice != null && _autoReconnect) {
        try {
          final state = await _connectedDevice!.connectionState.first.timeout(
            const Duration(seconds: 2),
          );
          if (state != BluetoothConnectionState.connected && !_isScanning) {
            _addLog('Connection lost, attempting reconnect...');
            await reconnect();
          }
        } catch (e) {
          _addLog('Connection check failed: $e', isError: true);
        }
      }
    });
  }

  // --- UPDATED: Scan Logic (Now builds a list instead of auto-connecting) ---
  Future<void> startScan() async {
    if (_isScanning) {
      _addLog('Scan already in progress');
      return;
    }

    try {
      _isScanning = true;
      _scanResults = []; // Clear previous results
      _addLog('Starting BLE scan for bridges...');
      notifyListeners();

      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: scanTimeout,
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        _scanResults = results;
        notifyListeners();
      });

      Future.delayed(scanTimeout, () async {
        if (_isScanning) {
          _addLog('Scan timeout reached');
          await stopScan();
        }
      });
    } catch (e) {
      _addLog('Scan error: $e', isError: true);
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanning = false;
      _addLog('Scan stopped');
      notifyListeners();
    } catch (e) {
      _addLog('Error stopping scan: $e', isError: true);
    }
  }

  // --- NEW: Manual Connection Method ---
  Future<void> connectToTarget(BluetoothDevice device, int rssi) async {
    await stopScan(); // Stop scanning before we try to connect
    await _connectToDevice(device, rssi);
  }

  Future<void> _connectToDevice(BluetoothDevice device, int rssi) async {
    try {
      _addLog('Connecting to device...');

      await device.connect(timeout: connectTimeout);

      _connectedDevice = device;
      _rssi = rssi;
      _deviceName = device.platformName.isNotEmpty ? device.platformName : 'Bridge ESP';
      _isConnected = true;
      _authState = BridgeAuthState.unknown; // Reset auth state on connect

      _addLog('Connected to $_deviceName');
      notifyListeners();

      _connectionSubscription = device.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.disconnected) {
          _addLog('Device disconnected');
          _handleDisconnection();
        }
      });

      await _discoverServices();
      await _updateRssi();
    } catch (e) {
      _addLog('Connection error: $e', isError: true);
      _handleDisconnection();
      rethrow;
    }
  }

  Future<void> _discoverServices() async {
    try {
      _addLog('Discovering services...');
      final services = await _connectedDevice!.discoverServices();

      for (var service in services) {
        if (service.uuid.toString() == serviceUuid) {
          _addLog('Found target service');
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == charUuid) {
              _targetCharacteristic = characteristic;
              _addLog('Found target characteristic');

              // Enable Notifications
              _addLog("Enabling notifications...");
              await _targetCharacteristic!.setNotifyValue(true);

              _notifySub?.cancel();
              _notifySub = _targetCharacteristic!.lastValueStream.listen((value) {
                _handleNotification(value);
              });
              _addLog("Notifications enabled.");

              // Negotiate a larger MTU so a full PROBES?/NODES? reply (up to 10
              // probes with 16-hex ROMs ~255 B) fits in one notification. Android
              // honors this; iOS/others keep their fixed MTU (still fine for ≤8).
              try { await _connectedDevice!.requestMtu(512); } catch (_) {}
              final mtu = await _connectedDevice!.mtu.first;
              _addLog('MTU: $mtu bytes');

              // Initiate Authentication Handshake
              _authState = BridgeAuthState.authenticating;
              notifyListeners();
              await checkAuthStatus();

              return; // Success exit!
            }
          }
        }
      }

      // --- NEW: If we get here, it didn't find the ESP32 services! ---
      throw Exception('Target service or characteristic not found on device.');

    } catch (e) {
      _addLog('Service discovery error: $e', isError: true);
      rethrow; // --- NEW: Throw this back to the UI! ---
    }
  }

  // --- Authentication Methods ---

  Future<void> checkAuthStatus() async {
    if (_targetCharacteristic == null) return;
    _addLog('Checking bridge authentication status...');
    await _writeCommandWithRetry('STATUS?');
  }

  Future<void> authenticateBridge(String pin) async {
    if (_targetCharacteristic == null) return;
    _lastTriedPin = pin;
    _addLog('Sending authentication PIN...');
    await _writeCommandWithRetry('AUTH|$pin');
  }

  Future<void> setupBridgePin(String newPin, {String oldPin = '123456'}) async {
    if (_targetCharacteristic == null) return;
    _lastTriedPin = newPin;
    _addLog('Sending new PIN setup request...');
    await _writeCommandWithRetry('SETPIN|$oldPin|$newPin');
  }

  Future<void> _handleSecuredState() async {
    // Auto-login removed. Always require manual PIN entry on reconnection.
    _authState = BridgeAuthState.authRequired;
    _addLog('Bridge is secured. Manual PIN entry required.');
    notifyListeners();
  }

  // --- Notification Handler ---
  void _handleNotification(List<int> value) async {
    if (value.isEmpty) return;
    try {
      final line = utf8.decode(value, allowMalformed: true).trim();
      if (line.isEmpty) return;

      _addLog('[NOTIFY] $line');

      // 1. Authentication Status Updates
      if (line == 'STATUS|SETUP_PENDING') {
        _authState = BridgeAuthState.setupRequired;
        _addLog('Bridge requires initial PIN setup');
        notifyListeners();
        return;
      } else if (line == 'STATUS|SECURED') {
        _addLog('Bridge is secured.');
        await _handleSecuredState();
        return;
      } else if (line == 'ACK AUTH SUCCESS') {
        _authState = BridgeAuthState.authenticated;
        if (_lastTriedPin != null) {
          await _secureStorage.write(key: pinStorageKey, value: _lastTriedPin);
        }
        _addLog('✅ Authenticated successfully. Session unlocked.');
        notifyListeners();
        return;
      } else if (line == 'ERR AUTH FAILED') {
        _authState = BridgeAuthState.authRequired;
        _addLog('❌ Authentication failed. Invalid PIN.', isError: true);
        await _secureStorage.delete(key: pinStorageKey); // Clear invalid saved pin
        notifyListeners();
        return;
      } else if (line == 'ACK SETPIN SUCCESS') {
        _authState = BridgeAuthState.authenticated;
        if (_lastTriedPin != null) {
          await _secureStorage.write(key: pinStorageKey, value: _lastTriedPin);
        }
        _addLog('✅ PIN setup successfully. Session unlocked.');
        notifyListeners();
        return;
      } else if (line == 'ERR SETPIN FAILED' || line == 'ERR SETPIN FORMAT') {
        _addLog('❌ PIN setup failed', isError: true);
        return;
      } else if (line == 'ERR UNAUTHENTICATED') {
        _addLog('❌ Command rejected: Session not authenticated', isError: true);
        return;
      }

      // 1b. System status (SYS|...) — refresh the System screen.
      if (line.startsWith('SYS|')) {
        final st = SystemStatus.parse(line);
        if (st != null) {
          _systemStatus = st;
          notifyListeners();
        }
        return;
      }

      // 1c. Commissioner state (from explicit acks or the C6's state lines).
      if (line.contains('COMMISSIONER_STARTED') ||
          (line.contains('COMMISSIONER STATE UPDATE') && line.contains('ACTIVE'))) {
        _addLog('✅ Commissioner ACTIVE');
      } else if (line.contains('COMMISSIONER_STOPPED') ||
          (line.contains('COMMISSIONER STATE UPDATE') && line.contains('DISABLED'))) {
        _addLog('⏹ Commissioner stopped');
      }

      // 1d. OTA / firmware progress + results.
      if (line.startsWith('OTA') || line.startsWith('[FLEETOTA]') ||
          line.startsWith('OTAC6') || line.startsWith('ERR OTA') ||
          line.startsWith('RESET_FLEET')) {
        _otaStatus = line;
        _addLog('🛠 $line');
        notifyListeners();
        return;
      }

      // Wi-Fi scan reply (Router Setup picker): "WIFI|<ssid>:<rssi>:<enc>,..."
      // enc: 0=open, 1=secured(PSK), 2=enterprise.
      if (line.startsWith('WIFI|')) {
        final body = line.substring(5).trim();
        final nets = <WifiNetwork>[];
        if (body.isNotEmpty) {
          for (final tok in body.split(',')) {
            final p = tok.split(':');
            if (p.length >= 3) {
              nets.add(WifiNetwork(
                ssid: p[0],
                rssi: int.tryParse(p[1]) ?? -100,
                enc: int.tryParse(p[2]) ?? 1,
              ));
            }
          }
        }
        nets.sort((a, b) => b.rssi.compareTo(a.rssi));
        _wifiNetworks = nets;
        _addLog('📶 ${nets.length} Wi-Fi network(s)');
        notifyListeners();
        return;
      }

      // 1d-1. Single-line replies (firmware >= c3 v12): one BLE notification so
      // nothing is dropped. "NODES|<eui>,<eui>,..." and "ROUTERS|<eui>:<role>,...".
      if (line.startsWith('NODES|')) {
        final body = line.substring(6).trim();
        _liveNodes = body.isEmpty
            ? <String>[]
            : body.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
        _addLog('📡 ${_liveNodes.length} live sensor(s)');
        notifyListeners();
        return;
      }
      if (line.startsWith('ROUTERS|')) {
        final body = line.substring(8).trim();
        final m = <String, String>{};
        if (body.isNotEmpty) {
          for (final part in body.split(',')) {
            final kv = part.split(':');
            final eui = kv[0].trim().toLowerCase();
            if (eui.isNotEmpty) m[eui] = kv.length > 1 ? kv[1].trim() : 'R';
          }
        }
        _meshNodes = m;
        _addLog('🧭 ${_meshNodes.length} mesh node(s)');
        notifyListeners();
        return;
      }

      // 1d-1b. Per-sensor probe list (PROBES?<eui> reply, single notification):
      // "PROBES|<eui>|<rom>:<temp>,<rom>:<temp>,..." (empty -> "PROBES|<eui>|").
      if (line.startsWith('PROBES|')) {
        final rest = line.substring(7);
        final bar = rest.indexOf('|');
        if (bar >= 0) {
          final eui = rest.substring(0, bar).trim().toLowerCase();
          final body = rest.substring(bar + 1).trim();
          final list = <ProbeReading>[];
          if (body.isNotEmpty) {
            var idx = 0;
            for (final part in body.split(',')) {
              final kv = part.split(':');
              final rom = kv[0].trim().toLowerCase();
              if (rom.isEmpty) continue;
              double? temp;
              if (kv.length > 1) {
                final v = kv[1].trim();
                if (v.toLowerCase() != 'err') temp = double.tryParse(v);
              }
              list.add(ProbeReading(rom: rom, tempC: temp, index: idx));
              idx++;
            }
          }
          _probesByEui[eui] = list;
          _addLog('🌡️ ${list.length} probe(s) on $eui');
          notifyListeners();
        }
        return;
      }

      // 1d-2. Live device list (chunked, legacy c3 < v12): NODES_BEGIN / NODE|<eui> / NODES_END.
      if (line == 'NODES_BEGIN') {
        _collectingNodes = true;
        _nodesAccumulator.clear();
        return;
      }
      if (line == 'NODES_END') {
        _collectingNodes = false;
        _liveNodes = List<String>.from(_nodesAccumulator);
        _addLog('📡 ${_liveNodes.length} live sensor(s)');
        notifyListeners();
        return;
      }
      if (line.startsWith('NODE|')) {
        final eui = line.substring(5).trim().toLowerCase();
        if (eui.isNotEmpty && !_nodesAccumulator.contains(eui)) {
          _nodesAccumulator.add(eui);
        }
        if (!_collectingNodes) {
          // tolerate a stray NODE| without a BEGIN
          _liveNodes = List<String>.from(_nodesAccumulator);
          notifyListeners();
        }
        return;
      }

      // 1d-3. Mesh node list (chunked): ROUTERS_BEGIN / ROUTER|<eui>|<G|R> / ROUTERS_END.
      if (line == 'ROUTERS_BEGIN') {
        _collectingMesh = true;
        _meshAccumulator.clear();
        return;
      }
      if (line == 'ROUTERS_END') {
        _collectingMesh = false;
        _meshNodes = Map<String, String>.from(_meshAccumulator);
        _addLog('🧭 ${_meshNodes.length} mesh node(s)');
        notifyListeners();
        return;
      }
      if (line.startsWith('ROUTER|')) {
        final parts = line.substring(7).split('|');
        final eui = parts[0].trim().toLowerCase();
        final role = parts.length > 1 ? parts[1].trim() : 'R';
        if (eui.isNotEmpty) _meshAccumulator[eui] = role;
        if (!_collectingMesh) {
          _meshNodes = Map<String, String>.from(_meshAccumulator);
          notifyListeners();
        }
        return;
      }

      // 1e. Sensor → box/slot mapping result.
      if (line.startsWith('ACK MAP') || line.startsWith('ERR MAP')) {
        _addLog(line.startsWith('ACK') ? '✅ $line' : '❌ $line',
            isError: line.startsWith('ERR'));
        return;
      }

      // 2. Wi-Fi Status Handling
      if (line.contains('WIFI_CONNECTED')) {
        _addLog('✅ Bridge successfully connected to Wi-Fi');
      } else if (line.contains('ERR WIFI_AUTH')) {
        _addLog('❌ Wi-Fi Authentication Failed - Check Password', isError: true);
      } else if (line.contains('ERR JSON_INVALID')) {
        _addLog('❌ Bridge rejected Provisioning JSON', isError: true);
      } else if (line.contains('STATUS CONNECTING_WIFI')) {
        _addLog('⏳ Bridge connecting to Wi-Fi...');
      }

      // 3. Commissioning / ADD Status
      final parts = line.split(RegExp(r"\s+"));
      if (parts.length >= 3) {
        final type = parts[0]; // ACK or ERR
        final cmd = parts[1];  // ADD
        final eui = parts[2];  // EUI64

        if (cmd == "ADD" && (type == "ACK" || type == "ERR")) {
          if (_pendingCommissionCompleter != null && _pendingEui64 == eui) {
            final success = (type == "ACK");
            _pendingTimer?.cancel();
            _pendingTimer = null;
            if (!_pendingCommissionCompleter!.isCompleted) {
              _pendingCommissionCompleter!.complete(success);
            }
            _pendingCommissionCompleter = null;
            _pendingEui64 = null;
          }
        }
      }
    } catch (e) {
      _addLog('Error parsing notification: $e', isError: true);
    }
  }

  Future<void> _updateRssi() async {
    if (_connectedDevice == null) return;
    try {
      final newRssi = await _connectedDevice!.readRssi();
      _rssi = newRssi;
      notifyListeners();
    } catch (e) {
      // Silently fail RSSI updates
    }
  }

  String _generateHmac(String message, String key) {
    final keyBytes = utf8.encode(key);
    final messageBytes = utf8.encode(message);
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(messageBytes);
    return digest.toString();
  }

  // --- Gatekept Commands ---

  Future<void> provisionWiFi({
    required String ssid,
    required String password,
    String zone = 'Default',
    String netName = 'ThreadNetwork',
    String discoveryUrl = '',
    String cloudUrl = '',
    String cloudKey = '',
    String wifiAuth = 'psk',     // 'psk' | 'peap' (WPA2-Enterprise)
    String eapUser = '',         // enterprise username
    String eapId = '',           // enterprise outer identity (defaults to username)
  }) async {
    if (_targetCharacteristic == null) {
      throw Exception('Not connected');
    }
    if (_authState != BridgeAuthState.authenticated) {
      throw Exception('Bridge session is locked. Authenticate first.');
    }

    final Map<String, dynamic> payload = {
      'ssid': ssid,
      'pass': password,
      'zone': zone,
      'netName': netName,
    };
    if (wifiAuth == 'peap') {
      payload['wauth'] = 'peap';
      payload['euser'] = eapUser;
      if (eapId.isNotEmpty) payload['eid'] = eapId;
    }
    if (discoveryUrl.isNotEmpty) payload['disc'] = discoveryUrl;
    // Cloud alerting service (AWS): the gateway posts readings here so the
    // threshold engine can alert the customer. Bridge.ino reads cloud/cloudKey.
    if (cloudUrl.isNotEmpty) payload['cloud'] = cloudUrl;
    if (cloudKey.isNotEmpty) payload['cloudKey'] = cloudKey;

    final jsonString = jsonEncode(payload);
    final command = 'PROVISION|$jsonString';

    _addLog('Provisioning Wi-Fi: $ssid...');

    try {
      await _writeCommandWithRetry(command);
      _addLog('Provisioning payload sent. Waiting for bridge to connect...');
    } catch (e) {
      _addLog('Failed to send provisioning command: $e', isError: true);
      rethrow;
    }
  }

  // --- Management commands (System screen) ---
  // All are handled locally on the C3 (or relayed to the C6) and gated by the
  // authenticated session, so they go over the UNSIGNED write path.

  bool get _ready =>
      _targetCharacteristic != null && _authState == BridgeAuthState.authenticated;

  Future<void> requestSystemStatus() async {
    if (!_ready) return; // polled silently; needs an unlocked session
    await _writeCommandWithRetry('SYS?');
  }

  /// Ask the bridge for the list of currently-live sensor EUIs (NODES?).
  /// The reply arrives async as NODES_BEGIN / NODE|<eui> / NODES_END and
  /// populates [liveNodes].
  Future<void> requestNodes() async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    _addLog('Requesting live sensor list...');
    await _writeCommandWithRetry('NODES?');
  }

  /// Ask the bridge to scan nearby Wi-Fi networks (SCAN?). The reply arrives
  /// async as "WIFI|<ssid>:<rssi>:<enc>,..." and populates [wifiNetworks].
  Future<void> requestWifiScan() async {
    if (_targetCharacteristic == null) { _addLog('Not connected', isError: true); return; }
    _wifiNetworks = [];
    notifyListeners();
    _addLog('Scanning Wi-Fi networks...');
    await _writeCommandWithRetry('SCAN?');   // read-only query (allowed pre-auth)
  }

  /// Ask the bridge for the routers the C6 leader currently sees in the mesh
  /// (ROUTERS?). The reply arrives async as ROUTERS_BEGIN / ROUTER|<eui> /
  /// ROUTERS_END and populates [liveRouters].
  Future<void> requestRouters() async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    await _writeCommandWithRetry('ROUTERS?');
  }

  /// Ask the bridge for the live probe list of one sensor (PROBES?<eui>). The
  /// reply arrives async as PROBES|<eui>|<rom>:<temp>,... and populates
  /// [probesFor] — used by the assign dialog's probe dropdown.
  Future<void> requestProbes(String eui) async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    final e = eui.trim().toLowerCase();
    if (e.isEmpty) return;
    _addLog('Requesting probes for $e...');
    await _writeCommandWithRetry('PROBES?$e');
  }

  /// Send a raw command to the bridge exactly as typed (unsigned), for the
  /// manual console. Most operational commands (SYS?, NODES?, commissioner_start,
  /// FORM_NET, OTA_SELF, …) are unsigned; use commissionDevice/sendCustomCommand
  /// for HMAC-signed ones like `add`.
  Future<void> sendRawCommand(String command) async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    final cmd = command.trim();
    if (cmd.isEmpty) return;
    _addLog('» $cmd');
    await _writeCommandWithRetry(cmd);
  }

  Future<void> setCommissioner(bool enable) async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    _addLog(enable ? 'Enabling commissioner...' : 'Disabling commissioner...');
    await _writeCommandWithRetry(enable ? 'commissioner_start' : 'commissioner_stop');
  }

  Future<void> updateThisGateway() async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    _otaStatus = 'Starting gateway update...';
    notifyListeners();
    _addLog('Firmware: updating this gateway (C6 + C3)...');
    await _writeCommandWithRetry('OTA_SELF');
  }

  Future<void> updateWholeFleet() async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    _otaStatus = 'Broadcasting fleet update...';
    notifyListeners();
    _addLog('Firmware: rolling OTA out to the whole fleet...');
    await _writeCommandWithRetry('OTA_FLEET');
  }

  /// Assign a sensor's EUI to a physical location. box/slot keep the legacy
  /// box-grid dashboard working; [label] is the rich "Rack / Unit / Port"
  /// location shown elsewhere. Wire format: MAP|<eui>|<box>|<slot>|<label>.
  Future<void> setSensorMapping({
    required String eui64,
    required int box,
    required String slot,
    String label = '',
  }) async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    _addLog('Assigning $eui64 -> ${label.isEmpty ? "box$box-$slot" : label}');
    final cmd = label.isEmpty
        ? 'MAP|$eui64|$box|$slot'
        : 'MAP|$eui64|$box|$slot|$label';
    await _writeCommandWithRetry(cmd);
  }

  Future<void> factoryResetUnit() async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    _addLog('Factory resetting THIS unit...');
    await _writeCommandWithRetry('FACTORY_RESET');
  }

  Future<void> factoryResetFleet() async {
    if (!_ready) { _addLog('Locked — authenticate first', isError: true); return; }
    _addLog('Factory resetting the WHOLE fleet...');
    await _writeCommandWithRetry('RESET_FLEET');
  }

  Future<void> commissionDevice(String eui64, String pskd) async {
    if (_targetCharacteristic == null) {
      _addLog('Not connected to device', isError: true);
      _addCommissionedDevice(eui64, false);
      return;
    }
    if (_authState != BridgeAuthState.authenticated) {
      _addLog('Bridge session is locked. Authenticate first.', isError: true);
      _addCommissionedDevice(eui64, false);
      return;
    }

    if (_pendingCommissionCompleter != null) {
      _addLog('Commission already in progress for $_pendingEui64', isError: true);
      _addCommissionedDevice(eui64, false);
      return;
    }

    final command = 'add $eui64 $pskd';
    _addLog('Preparing command: $command');

    try {
      final secretKey = await _getSecretKey();
      final signature = _generateHmac(command, secretKey);
      final signedCommand = '$command|$signature';

      _pendingEui64 = eui64;
      _pendingCommissionCompleter = Completer<bool>();

      _pendingTimer?.cancel();
      _pendingTimer = Timer(commissionResultTimeout, () {
        if (_pendingCommissionCompleter != null && !_pendingCommissionCompleter!.isCompleted) {
          _addLog('Commission timeout waiting for Bridge ACK', isError: true);
          _pendingCommissionCompleter!.complete(false);
          _pendingCommissionCompleter = null;
          _pendingEui64 = null;
        }
      });

      _addLog('Generated HMAC signature');
      await _writeCommandWithRetry(signedCommand);

      _addLog('Command sent. Waiting for Bridge confirmation...');

      final success = await _pendingCommissionCompleter!.future;

      if (success) {
        _addCommissionedDevice(eui64, true);
        _addLog('✅ Device $eui64 commissioned successfully');
      } else {
        _addCommissionedDevice(eui64, false);
        _addLog('❌ Device $eui64 failed to add', isError: true);
      }
    } catch (e) {
      _pendingTimer?.cancel();
      _pendingTimer = null;
      _pendingCommissionCompleter = null;
      _pendingEui64 = null;

      _addLog('Commission error: $e', isError: true);
      _addCommissionedDevice(eui64, false);
    }
  }

  Future<void> _writeCommandWithRetry(String command) async {
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        _addLog('Writing command (attempt ${attempt + 1}/$maxRetries)...');

        final commandBytes = utf8.encode(command);
        await _targetCharacteristic!.write(
          commandBytes,
          withoutResponse: false,
          timeout: writeTimeout.inSeconds,
        );

        _addLog('Command written successfully');
        return;
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) {
          throw Exception('Failed after $maxRetries attempts: $e');
        }

        _addLog('Write failed, retrying in ${retryDelay.inSeconds}s...', isError: true);
        await Future.delayed(retryDelay);
      }
    }
  }

  Future<void> sendCustomCommand(String command) async {
    if (_targetCharacteristic == null) {
      _addLog('Not connected to device', isError: true);
      return;
    }
    if (_authState != BridgeAuthState.authenticated) {
      _addLog('Bridge session is locked. Authenticate first.', isError: true);
      return;
    }

    try {
      final secretKey = await _getSecretKey();
      final signature = _generateHmac(command, secretKey);
      final signedCommand = '$command|$signature';

      await _writeCommandWithRetry(signedCommand);
      _addLog('Custom command sent: $command');
    } catch (e) {
      _addLog('Custom command error: $e', isError: true);
    }
  }

  Future<void> reconnect() async {
    if (_connectedDevice != null) {
      _addLog('Attempting reconnection...');
      try {
        await _connectedDevice!.connect(timeout: connectTimeout);
        _isConnected = true;
        _authState = BridgeAuthState.unknown;
        _addLog('Reconnected successfully');
        await _discoverServices();
        notifyListeners();
      } catch (e) {
        _addLog('Reconnection failed: $e', isError: true);
        _handleDisconnection();
      }
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _authState = BridgeAuthState.unknown; // Reset state on disconnect
    _targetCharacteristic = null;
    _notifySub?.cancel();
    _notifySub = null;
    _rssi = 0;

    _pendingTimer?.cancel();
    if (_pendingCommissionCompleter != null && !_pendingCommissionCompleter!.isCompleted) {
      _pendingCommissionCompleter!.complete(false);
    }
    _pendingCommissionCompleter = null;
    _pendingEui64 = null;

    notifyListeners();

    if (_autoReconnect && _connectedDevice != null) {
      Future.delayed(retryDelay, () => reconnect());
    }
  }

  Future<void> disconnect() async {
    try {
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;

      await _notifySub?.cancel();
      _notifySub = null;

      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _addLog('Disconnected from device');
      }

      _connectedDevice = null;
      _targetCharacteristic = null;
      _isConnected = false;
      _authState = BridgeAuthState.unknown;
      _rssi = 0;
      _deviceName = 'Unknown';
      notifyListeners();
    } catch (e) {
      _addLog('Disconnect error: $e', isError: true);
    }
  }

  void clearLogs() {
    _logs.clear();
    _addLog('Logs cleared');
    notifyListeners();
  }

  void clearHistory() {
    _commissionHistory.clear();
    _addLog('Commission history cleared');
    notifyListeners();
  }

  String exportLogs() {
    return _logs.join('\n');
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _notifySub?.cancel();
    _pendingTimer?.cancel();
    disconnect();
    super.dispose();
  }
}

/// One DS18B20 probe of a sensor, as reported by a `PROBES?<eui>` reply.
///
/// [rom] is the probe's 64-bit ROM serial (lower-hex) — its stable identity used
/// for mapping (survives unplug/reorder). [index] is the current discovery order,
/// only used for the friendly "Probe N" label in the dropdown.
class ProbeReading {
  final String rom;
  final double? tempC; // latest reading, null if 'err'/disconnected
  final int index;
  ProbeReading({required this.rom, required this.tempC, required this.index});

  String get label => 'Probe ${index + 1}';
  String get shortRom => rom.length >= 6 ? rom.substring(rom.length - 6) : rom;
}