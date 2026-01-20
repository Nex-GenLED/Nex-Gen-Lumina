import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for communicating with the Lumina backend server.
/// Handles authentication, device management, and remote command relay.
class LuminaBackendService {
  static const String _baseUrlKey = 'lumina_backend_url';
  static const String _tokenKey = 'lumina_backend_token';
  static const String _userIdKey = 'lumina_backend_user_id';

  // Default to localhost for development, user can configure production URL
  static const String _defaultBaseUrl = 'http://localhost:3000';

  String _baseUrl = _defaultBaseUrl;
  String? _authToken;
  String? _userId;

  final http.Client _client;

  LuminaBackendService({http.Client? client}) : _client = client ?? http.Client();

  /// Initialize the service by loading saved credentials.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    _authToken = prefs.getString(_tokenKey);
    _userId = prefs.getString(_userIdKey);
    debugPrint('LuminaBackendService: Initialized with baseUrl=$_baseUrl, hasToken=${_authToken != null}');
  }

  /// Check if the user is authenticated with the backend.
  bool get isAuthenticated => _authToken != null;

  /// Get the current user ID.
  String? get userId => _userId;

  /// Get the configured backend URL.
  String get baseUrl => _baseUrl;

  /// Set the backend URL (for configuration).
  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, _baseUrl);
  }

  /// Common headers for authenticated requests.
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// Check if the backend server is reachable.
  Future<BackendHealthStatus> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BackendHealthStatus(
          isOnline: true,
          mqttConnected: data['mqtt'] == 'connected',
          timestamp: DateTime.tryParse(data['timestamp'] ?? ''),
        );
      }
      return const BackendHealthStatus(isOnline: false, mqttConnected: false);
    } catch (e) {
      debugPrint('LuminaBackendService: Health check failed: $e');
      return const BackendHealthStatus(isOnline: false, mqttConnected: false);
    }
  }

  /// Register a new user account.
  Future<AuthResult> register(String email, String password) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        await _saveAuthData(data['token'], data['user']['id']);
        return AuthResult(
          success: true,
          userId: data['user']['id'],
          email: data['user']['email'],
        );
      }
      return AuthResult(
        success: false,
        error: data['message'] ?? 'Registration failed',
      );
    } catch (e) {
      return AuthResult(success: false, error: 'Network error: $e');
    }
  }

  /// Login with existing credentials.
  Future<AuthResult> login(String email, String password) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _saveAuthData(data['token'], data['user']['id']);
        return AuthResult(
          success: true,
          userId: data['user']['id'],
          email: data['user']['email'],
        );
      }
      return AuthResult(
        success: false,
        error: data['message'] ?? 'Login failed',
      );
    } catch (e) {
      return AuthResult(success: false, error: 'Network error: $e');
    }
  }

  /// Logout and clear saved credentials.
  Future<void> logout() async {
    _authToken = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
  }

  Future<void> _saveAuthData(String token, String userId) async {
    _authToken = token;
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
  }

  /// Provision a new device (get MQTT credentials for the device).
  Future<DeviceProvisionResult> provisionDevice(String deviceSerial) async {
    if (!isAuthenticated) {
      return const DeviceProvisionResult(
        success: false,
        error: 'Not authenticated',
      );
    }

    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/devices/provision'),
        headers: _headers,
        body: jsonEncode({'device_serial': deviceSerial}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return DeviceProvisionResult(
          success: true,
          deviceId: data['device_id'],
          deviceSerial: data['device_serial'],
          mqttBroker: data['mqtt_broker'],
          mqttPort: data['mqtt_port'],
          mqttUsername: data['mqtt_username'],
          mqttPassword: data['mqtt_password'],
        );
      }
      return DeviceProvisionResult(
        success: false,
        error: data['message'] ?? 'Provisioning failed',
      );
    } catch (e) {
      return DeviceProvisionResult(success: false, error: 'Network error: $e');
    }
  }

  /// Claim a device for the authenticated user.
  Future<DeviceClaimResult> claimDevice(
    String deviceSerial, {
    String? friendlyName,
  }) async {
    if (!isAuthenticated) {
      return const DeviceClaimResult(success: false, error: 'Not authenticated');
    }

    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/devices/claim'),
        headers: _headers,
        body: jsonEncode({
          'device_serial': deviceSerial,
          if (friendlyName != null) 'friendly_name': friendlyName,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final device = data['device'];
        return DeviceClaimResult(
          success: true,
          device: BackendDevice.fromJson(device),
        );
      }
      return DeviceClaimResult(
        success: false,
        error: data['message'] ?? 'Claim failed',
      );
    } catch (e) {
      return DeviceClaimResult(success: false, error: 'Network error: $e');
    }
  }

  /// Get all devices owned by the authenticated user.
  Future<DeviceListResult> listDevices() async {
    if (!isAuthenticated) {
      return const DeviceListResult(success: false, error: 'Not authenticated');
    }

    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/devices'),
        headers: _headers,
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final devices = (data['devices'] as List)
            .map((d) => BackendDevice.fromJson(d))
            .toList();
        return DeviceListResult(success: true, devices: devices);
      }
      return DeviceListResult(
        success: false,
        error: data['message'] ?? 'Failed to list devices',
      );
    } catch (e) {
      return DeviceListResult(success: false, error: 'Network error: $e');
    }
  }

  /// Send a command to a device via MQTT (for remote control).
  Future<CommandResult> sendCommand(
    String deviceId, {
    required String action,
    Map<String, dynamic>? payload,
  }) async {
    if (!isAuthenticated) {
      return const CommandResult(success: false, error: 'Not authenticated');
    }

    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/devices/$deviceId/command'),
        headers: _headers,
        body: jsonEncode({
          'action': action,
          if (payload != null) 'payload': payload,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return CommandResult(
          success: true,
          command: data['command'],
        );
      }
      return CommandResult(
        success: false,
        error: data['message'] ?? 'Command failed',
      );
    } catch (e) {
      return CommandResult(success: false, error: 'Network error: $e');
    }
  }

  /// Send a WLED state update via the backend.
  /// This is the primary method for remote control.
  Future<CommandResult> sendWledState(
    String deviceId,
    Map<String, dynamic> state,
  ) async {
    return sendCommand(deviceId, action: 'setState', payload: state);
  }

  /// Turn device on/off via backend.
  Future<CommandResult> setPower(String deviceId, bool on) async {
    return sendWledState(deviceId, {'on': on});
  }

  /// Set brightness via backend (0-255).
  Future<CommandResult> setBrightness(String deviceId, int brightness) async {
    return sendWledState(deviceId, {'bri': brightness.clamp(0, 255)});
  }

  /// Set color via backend.
  Future<CommandResult> setColor(
    String deviceId, {
    required int r,
    required int g,
    required int b,
    int? w,
  }) async {
    final color = w != null ? [r, g, b, w] : [r, g, b];
    return sendWledState(deviceId, {
      'seg': [
        {
          'col': [color]
        }
      ]
    });
  }

  /// Set effect via backend.
  Future<CommandResult> setEffect(
    String deviceId, {
    required int effectId,
    int? paletteId,
    int? speed,
    int? intensity,
  }) async {
    final seg = <String, dynamic>{'fx': effectId};
    if (paletteId != null) seg['pal'] = paletteId;
    if (speed != null) seg['sx'] = speed;
    if (intensity != null) seg['ix'] = intensity;
    return sendWledState(deviceId, {
      'seg': [seg]
    });
  }

  void dispose() {
    _client.close();
  }
}

/// Health status of the backend server.
class BackendHealthStatus {
  final bool isOnline;
  final bool mqttConnected;
  final DateTime? timestamp;

  const BackendHealthStatus({
    required this.isOnline,
    required this.mqttConnected,
    this.timestamp,
  });
}

/// Result of authentication operations.
class AuthResult {
  final bool success;
  final String? userId;
  final String? email;
  final String? error;

  const AuthResult({
    required this.success,
    this.userId,
    this.email,
    this.error,
  });
}

/// Result of device provisioning.
class DeviceProvisionResult {
  final bool success;
  final String? deviceId;
  final String? deviceSerial;
  final String? mqttBroker;
  final int? mqttPort;
  final String? mqttUsername;
  final String? mqttPassword;
  final String? error;

  const DeviceProvisionResult({
    required this.success,
    this.deviceId,
    this.deviceSerial,
    this.mqttBroker,
    this.mqttPort,
    this.mqttUsername,
    this.mqttPassword,
    this.error,
  });
}

/// Result of device claim operation.
class DeviceClaimResult {
  final bool success;
  final BackendDevice? device;
  final String? error;

  const DeviceClaimResult({
    required this.success,
    this.device,
    this.error,
  });
}

/// Result of device list operation.
class DeviceListResult {
  final bool success;
  final List<BackendDevice>? devices;
  final String? error;

  const DeviceListResult({
    required this.success,
    this.devices,
    this.error,
  });
}

/// Result of command operation.
class CommandResult {
  final bool success;
  final Map<String, dynamic>? command;
  final String? error;

  const CommandResult({
    required this.success,
    this.command,
    this.error,
  });
}

/// Device as stored in the backend.
class BackendDevice {
  final String id;
  final String deviceSerial;
  final String? friendlyName;
  final bool isOnline;
  final DateTime? lastSeen;
  final Map<String, dynamic> currentState;
  final String? firmwareVersion;
  final DateTime? createdAt;

  const BackendDevice({
    required this.id,
    required this.deviceSerial,
    this.friendlyName,
    required this.isOnline,
    this.lastSeen,
    required this.currentState,
    this.firmwareVersion,
    this.createdAt,
  });

  factory BackendDevice.fromJson(Map<String, dynamic> json) {
    return BackendDevice(
      id: json['id'],
      deviceSerial: json['device_serial'],
      friendlyName: json['friendly_name'],
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'])
          : null,
      currentState: json['current_state'] ?? {},
      firmwareVersion: json['firmware_version'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
    );
  }
}
