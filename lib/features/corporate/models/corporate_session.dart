import 'package:cloud_firestore/cloud_firestore.dart';

/// Role of a Nex-Gen corporate user.
///
/// - [owner]: full access — can modify pricing, PINs, dealers, announcements
/// - [officer]: full read + most writes (announcements, dealer status), no PIN management
/// - [warehouse]: read-only on Network/Pipeline; full read + reorder triggers on Warehouse
/// - [readonly]: read-only across all corporate tabs
enum CorporateRole {
  owner,
  officer,
  warehouse,
  readonly,
}

extension CorporateRoleX on CorporateRole {
  String get label {
    switch (this) {
      case CorporateRole.owner:
        return 'Owner';
      case CorporateRole.officer:
        return 'Officer';
      case CorporateRole.warehouse:
        return 'Warehouse';
      case CorporateRole.readonly:
        return 'Read-only';
    }
  }

  static CorporateRole fromString(String? s) =>
      CorporateRole.values.firstWhere(
        (e) => e.name == s,
        orElse: () => CorporateRole.readonly,
      );
}

/// Active session for an authenticated Nex-Gen corporate employee.
///
/// Created by [CorporateModeNotifier.authenticate] on successful PIN entry,
/// stored in [corporateSessionProvider], cleared on sign-out or timeout.
class CorporateSession {
  /// Firebase Auth UID of the Nex-Gen employee. May be empty when the
  /// session was created via the master corporate PIN (no auth user).
  final String uid;

  /// Display name shown in the corporate dashboard header.
  final String displayName;

  final CorporateRole role;

  final DateTime authenticatedAt;

  const CorporateSession({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.authenticatedAt,
  });

  CorporateSession copyWith({
    String? uid,
    String? displayName,
    CorporateRole? role,
    DateTime? authenticatedAt,
  }) {
    return CorporateSession(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      authenticatedAt: authenticatedAt ?? this.authenticatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'role': role.name,
        'authenticatedAt': Timestamp.fromDate(authenticatedAt),
      };

  factory CorporateSession.fromJson(Map<String, dynamic> j) => CorporateSession(
        uid: j['uid'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
        role: CorporateRoleX.fromString(j['role'] as String?),
        authenticatedAt:
            (j['authenticatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}
