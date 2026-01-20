import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Site operating modes
enum SiteMode { residential, commercial }

/// Property type for a PropertyArea; mirrors SiteMode but scoped to areas
enum PropertyType { residential, commercial }

/// Represents a user-defined Property Area (e.g., Main Home, Lake House)
class PropertyArea {
  final String name;
  final PropertyType type;
  final Set<String> linkedControllerIds; // controller document IDs linked to this area (Residential usage)

  const PropertyArea({required this.name, required this.type, this.linkedControllerIds = const {}});

  PropertyArea copyWith({String? name, PropertyType? type, Set<String>? linkedControllerIds}) => PropertyArea(
        name: name ?? this.name,
        type: type ?? this.type,
        linkedControllerIds: linkedControllerIds ?? this.linkedControllerIds,
      );

  @override
  String toString() => 'PropertyArea(name: '+name+', type: '+type.name+', linked: '+linkedControllerIds.length.toString()+')';
}

/// Represents a Zone in Commercial mode with a primary controller and secondaries
class ZoneModel {
  final String name;
  final String? primaryIp;
  final List<String> members; // includes primary if present
  final bool ddpSyncEnabled;
  final int ddpPort;

  const ZoneModel({
    required this.name,
    required this.primaryIp,
    required this.members,
    this.ddpSyncEnabled = false,
    this.ddpPort = 4048,
  });

  ZoneModel copyWith({String? name, String? primaryIp, List<String>? members, bool? ddpSyncEnabled, int? ddpPort}) => ZoneModel(
        name: name ?? this.name,
        primaryIp: primaryIp ?? this.primaryIp,
        members: members ?? this.members,
        ddpSyncEnabled: ddpSyncEnabled ?? this.ddpSyncEnabled,
        ddpPort: ddpPort ?? this.ddpPort,
      );

  @override
  String toString() => 'ZoneModel(name: '+name+', primaryIp: '+(primaryIp ?? '-')+', members: '+members.join(',')+', ddp: '+ddpSyncEnabled.toString()+')';
}

/// Represents a saved controller for a user
class ControllerInfo {
  final String id; // Firestore doc id
  final String ip;
  final String? name;
  final String? serial;
  final String? ssid;
  final bool? wifiConfigured;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ControllerInfo({
    required this.id,
    required this.ip,
    this.name,
    this.serial,
    this.ssid,
    this.wifiConfigured,
    this.createdAt,
    this.updatedAt,
  });

  ControllerInfo copyWith({
    String? id,
    String? ip,
    String? name,
    String? serial,
    String? ssid,
    bool? wifiConfigured,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ControllerInfo(
        id: id ?? this.id,
        ip: ip ?? this.ip,
        name: name ?? this.name,
        serial: serial ?? this.serial,
        ssid: ssid ?? this.ssid,
        wifiConfigured: wifiConfigured ?? this.wifiConfigured,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() => 'ControllerInfo(id: '+id+', ip: '+ip+', name: '+(name ?? '-')+', ssid: '+(ssid ?? '-')+')';
}
