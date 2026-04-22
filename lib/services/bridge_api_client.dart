import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Data returned by GET /api/info on the bridge.
class BridgeInfo {
  final String name;
  final String version;
  final String type;
  final String ip;
  final String mdns;
  final String ap;
  final String savedSSID;

  const BridgeInfo({
    required this.name,
    required this.version,
    required this.type,
    required this.ip,
    required this.mdns,
    required this.ap,
    required this.savedSSID,
  });

  factory BridgeInfo.fromJson(Map<String, dynamic> json) => BridgeInfo(
        name: json['name'] as String? ?? '',
        version: json['version'] as String? ?? '',
        type: json['type'] as String? ?? '',
        ip: json['ip'] as String? ?? '',
        mdns: json['mdns'] as String? ?? '',
        ap: json['ap'] as String? ?? '',
        savedSSID: json['savedSSID'] as String? ?? '',
      );
}

/// Data returned by GET /api/bridge/status on the bridge.
class BridgeStatus {
  final bool paired;
  final bool authenticated;
  final bool wifi;
  final String userId;
  final String wledIp;
  final int commands;
  final int errors;
  final int uptime;
  final String version;

  const BridgeStatus({
    required this.paired,
    required this.authenticated,
    required this.wifi,
    required this.userId,
    required this.wledIp,
    required this.commands,
    required this.errors,
    required this.uptime,
    required this.version,
  });

  factory BridgeStatus.fromJson(Map<String, dynamic> json) => BridgeStatus(
        paired: json['paired'] as bool? ?? false,
        authenticated: json['authenticated'] as bool? ?? false,
        wifi: json['wifi'] as bool? ?? false,
        userId: json['userId'] as String? ?? '',
        wledIp: json['wledIp'] as String? ?? '',
        commands: (json['commands'] as num?)?.toInt() ?? 0,
        errors: (json['errors'] as num?)?.toInt() ?? 0,
        uptime: (json['uptime'] as num?)?.toInt() ?? 0,
        version: json['version'] as String? ?? '',
      );
}

/// HTTP client for the Lumina Bridge's local REST API.
///
/// Used during setup/pairing only — requires the phone to be on the same
/// WiFi network as the bridge.
class BridgeApiClient {
  final String baseUrl;

  BridgeApiClient(this.baseUrl);

  factory BridgeApiClient.fromIp(String ip, {int port = 80}) {
    final base = port == 80 ? 'http://$ip' : 'http://$ip:$port';
    return BridgeApiClient(base);
  }

  static const _timeout = Duration(seconds: 5);

  /// GET /api/info — device identity and network info.
  Future<BridgeInfo?> getInfo() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/info'),
              headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return BridgeInfo.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[BridgeApiClient] getInfo failed: $e');
    }
    return null;
  }

  /// GET /api/bridge/status — pairing and operational state.
  Future<BridgeStatus?> getStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/bridge/status'),
              headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return BridgeStatus.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[BridgeApiClient] getStatus failed: $e');
    }
    return null;
  }

  /// POST /api/bridge/pair — register this bridge with a user and WLED target.
  Future<bool> pair({
    required String userId,
    required String wledIp,
    int wledPort = 80,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/bridge/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'wledIp': wledIp,
              'wledPort': wledPort,
            }),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[BridgeApiClient] pair failed: $e');
      return false;
    }
  }

  /// POST /api/bridge/auth — provide Firebase service account credentials.
  Future<bool> authenticate({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/bridge/auth'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[BridgeApiClient] authenticate failed: $e');
      return false;
    }
  }

  /// POST /api/reboot — restart the bridge.
  Future<bool> reboot() async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/api/reboot')).timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[BridgeApiClient] reboot failed: $e');
      return false;
    }
  }

  /// POST /api/bridge/reset — factory reset the bridge (clears NVS).
  Future<bool> reset() async {
    try {
      final response =
          await http.post(Uri.parse('$baseUrl/api/bridge/reset')).timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[BridgeApiClient] reset failed: $e');
      return false;
    }
  }
}
