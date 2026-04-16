import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/controller_type.dart';

/// Represents a saved WLED controller in Firestore.
///
/// Firestore path: `/users/{uid}/controllers/{docId}`
class ControllerModel {
  /// Firestore document ID.
  final String id;

  /// IP address on the local network.
  final String ip;

  /// User-assigned display name.
  final String? name;

  /// MAC / serial identifier.
  final String? serial;

  /// Wi-Fi SSID the controller is connected to.
  final String? ssid;

  /// Whether Wi-Fi has been configured on this controller.
  final bool? wifiConfigured;

  /// Hardware variant of this controller.
  final ControllerType controllerType;

  /// When this document was first created.
  final DateTime? createdAt;

  /// When this document was last updated.
  final DateTime? updatedAt;

  const ControllerModel({
    required this.id,
    required this.ip,
    this.name,
    this.serial,
    this.ssid,
    this.wifiConfigured,
    this.controllerType = ControllerType.genericWled,
    this.createdAt,
    this.updatedAt,
  });

  /// Deserialise a Firestore document snapshot.
  ///
  /// Missing fields fall back to safe defaults — existing production documents
  /// predate [controllerType] and must not fail to load.
  factory ControllerModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ControllerModel.fromJson({...data, 'id': doc.id});
  }

  /// Deserialise from a raw JSON/Map (also used by [fromFirestore]).
  factory ControllerModel.fromJson(Map<String, dynamic> json) {
    final createdTs = json['created_at'] ?? json['createdAt'];
    final updatedTs = json['updated_at'] ?? json['updatedAt'];

    return ControllerModel(
      id: json['id'] as String? ?? '',
      ip: (json['ip'] ?? '') as String,
      name: json['name'] as String?,
      serial: json['serial'] as String?,
      ssid: json['ssid'] as String?,
      wifiConfigured: json['wifiConfigured'] as bool? ??
          json['wifi_configured'] as bool?,
      controllerType: json['controller_type'] is String
          ? ControllerType.fromFirestore(json['controller_type'] as String)
          : ControllerType.genericWled,
      createdAt: createdTs is Timestamp ? createdTs.toDate() : null,
      updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : null,
    );
  }

  /// Serialise for Firestore writes.
  Map<String, dynamic> toFirestore() => {
        'ip': ip,
        if (name != null) 'name': name,
        if (serial != null) 'serial': serial,
        if (ssid != null && ssid!.isNotEmpty) 'ssid': ssid,
        if (wifiConfigured != null) 'wifiConfigured': wifiConfigured,
        'controller_type': controllerType.toFirestore(),
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  ControllerModel copyWith({
    String? id,
    String? ip,
    String? name,
    String? serial,
    String? ssid,
    bool? wifiConfigured,
    ControllerType? controllerType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ControllerModel(
        id: id ?? this.id,
        ip: ip ?? this.ip,
        name: name ?? this.name,
        serial: serial ?? this.serial,
        ssid: ssid ?? this.ssid,
        wifiConfigured: wifiConfigured ?? this.wifiConfigured,
        controllerType: controllerType ?? this.controllerType,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() =>
      'ControllerModel(id: $id, ip: $ip, name: ${name ?? '-'}, '
      'type: ${controllerType.toFirestore()})';
}
