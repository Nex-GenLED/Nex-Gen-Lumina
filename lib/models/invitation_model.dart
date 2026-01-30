import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/sub_user_permissions.dart';

/// Status of a sub-user invitation.
enum InvitationStatus {
  /// Invitation sent, waiting for recipient to accept.
  pending,

  /// Recipient has accepted and is now a sub-user.
  accepted,

  /// Invitation expired without being accepted.
  expired,

  /// Primary user revoked the invitation before it was accepted.
  revoked,
}

extension InvitationStatusExtension on InvitationStatus {
  String toJson() => name;

  static InvitationStatus fromJson(String? value) {
    if (value == null) return InvitationStatus.pending;
    return InvitationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => InvitationStatus.pending,
    );
  }

  String get displayName {
    switch (this) {
      case InvitationStatus.pending:
        return 'Pending';
      case InvitationStatus.accepted:
        return 'Accepted';
      case InvitationStatus.expired:
        return 'Expired';
      case InvitationStatus.revoked:
        return 'Revoked';
    }
  }
}

/// Represents an invitation for a sub-user to join an installation.
///
/// Created by primary users to invite family members or staff.
/// Contains a 6-character code that the invitee enters to link their account.
class Invitation {
  /// Firestore document ID.
  final String id;

  /// The installation being shared.
  final String installationId;

  /// The primary user who sent the invitation.
  final String primaryUserId;

  /// Email address of the invitee.
  final String inviteeEmail;

  /// Optional display name for the invitee.
  final String? inviteeName;

  /// 6-character alphanumeric code (e.g., "ABC123").
  final String token;

  /// When the invitation was created.
  final DateTime createdAt;

  /// When the invitation expires (default: 7 days from creation).
  final DateTime expiresAt;

  /// Current status of the invitation.
  final InvitationStatus status;

  /// Permissions granted to the sub-user when they accept.
  final SubUserPermissions permissions;

  /// When the invitation was accepted (if accepted).
  final DateTime? acceptedAt;

  /// The user ID of who accepted (if accepted).
  final String? acceptedByUserId;

  const Invitation({
    required this.id,
    required this.installationId,
    required this.primaryUserId,
    required this.inviteeEmail,
    this.inviteeName,
    required this.token,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.permissions,
    this.acceptedAt,
    this.acceptedByUserId,
  });

  /// Whether this invitation can still be accepted.
  bool get isValid =>
      status == InvitationStatus.pending &&
      DateTime.now().isBefore(expiresAt);

  /// Whether this invitation has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Days remaining until expiration.
  int get daysRemaining => expiresAt.difference(DateTime.now()).inDays;

  Map<String, dynamic> toJson() => {
        'id': id,
        'installation_id': installationId,
        'primary_user_id': primaryUserId,
        'invitee_email': inviteeEmail,
        if (inviteeName != null) 'invitee_name': inviteeName,
        'token': token,
        'created_at': Timestamp.fromDate(createdAt),
        'expires_at': Timestamp.fromDate(expiresAt),
        'status': status.toJson(),
        'permissions': permissions.toJson(),
        if (acceptedAt != null) 'accepted_at': Timestamp.fromDate(acceptedAt!),
        if (acceptedByUserId != null) 'accepted_by_user_id': acceptedByUserId,
      };

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'] as String? ?? '',
      installationId: json['installation_id'] as String? ?? '',
      primaryUserId: json['primary_user_id'] as String? ?? '',
      inviteeEmail: json['invitee_email'] as String? ?? '',
      inviteeName: json['invitee_name'] as String?,
      token: json['token'] as String? ?? '',
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (json['expires_at'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 7)),
      status: InvitationStatusExtension.fromJson(json['status'] as String?),
      permissions: SubUserPermissions.fromJson(
          json['permissions'] as Map<String, dynamic>?),
      acceptedAt: (json['accepted_at'] as Timestamp?)?.toDate(),
      acceptedByUserId: json['accepted_by_user_id'] as String?,
    );
  }

  factory Invitation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Invitation.fromJson({...data, 'id': doc.id});
  }

  Invitation copyWith({
    String? id,
    String? installationId,
    String? primaryUserId,
    String? inviteeEmail,
    String? inviteeName,
    String? token,
    DateTime? createdAt,
    DateTime? expiresAt,
    InvitationStatus? status,
    SubUserPermissions? permissions,
    DateTime? acceptedAt,
    String? acceptedByUserId,
  }) =>
      Invitation(
        id: id ?? this.id,
        installationId: installationId ?? this.installationId,
        primaryUserId: primaryUserId ?? this.primaryUserId,
        inviteeEmail: inviteeEmail ?? this.inviteeEmail,
        inviteeName: inviteeName ?? this.inviteeName,
        token: token ?? this.token,
        createdAt: createdAt ?? this.createdAt,
        expiresAt: expiresAt ?? this.expiresAt,
        status: status ?? this.status,
        permissions: permissions ?? this.permissions,
        acceptedAt: acceptedAt ?? this.acceptedAt,
        acceptedByUserId: acceptedByUserId ?? this.acceptedByUserId,
      );
}
