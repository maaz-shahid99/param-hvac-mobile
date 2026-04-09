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

              // Get MTU size
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