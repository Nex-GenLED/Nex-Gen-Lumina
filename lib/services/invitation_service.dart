import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/models/invitation_model.dart';
import 'package:nexgen_command/models/sub_user_permissions.dart';

/// Service for managing sub-user invitations.
///
/// Handles creating, accepting, revoking, and querying invitations
/// that allow sub-users to join an installation.
class InvitationService {
  final FirebaseFirestore _db;

  InvitationService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Create a new invitation for a sub-user.
  ///
  /// Returns the created [Invitation] with a unique 6-character token.
  /// Throws if the installation has reached its sub-user limit.
  Future<Invitation> createInvitation({
    required String installationId,
    required String primaryUserId,
    required String inviteeEmail,
    String? inviteeName,
    SubUserPermissions permissions = SubUserPermissions.basic,
    Duration validity = const Duration(days: 7),
  }) async {
    // Check installation exists and get limits
    final installDoc = await _db.collection('installations').doc(installationId).get();
    if (!installDoc.exists) {
      throw Exception('Installation not found');
    }

    final installData = installDoc.data()!;
    final maxSubUsers = installData['max_sub_users'] as int? ?? 5;

    // Check current sub-user count
    final subUsersSnapshot = await _db
        .collection('installations')
        .doc(installationId)
        .collection('subUsers')
        .count()
        .get();

    final currentCount = subUsersSnapshot.count ?? 0;
    if (currentCount >= maxSubUsers) {
      throw Exception('Maximum sub-users reached ($maxSubUsers). Cannot invite more users.');
    }

    // Check for existing pending invitation to same email
    final existingQuery = await _db
        .collection('invitations')
        .where('installation_id', isEqualTo: installationId)
        .where('invitee_email', isEqualTo: inviteeEmail.toLowerCase().trim())
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existingQuery.docs.isNotEmpty) {
      throw Exception('A pending invitation already exists for this email.');
    }

    // Generate unique 6-character token
    final token = _generateToken();

    // Create invitation
    final now = DateTime.now();
    final invitation = Invitation(
      id: '', // Will be set by Firestore
      installationId: installationId,
      primaryUserId: primaryUserId,
      inviteeEmail: inviteeEmail.toLowerCase().trim(),
      inviteeName: inviteeName,
      token: token,
      createdAt: now,
      expiresAt: now.add(validity),
      status: InvitationStatus.pending,
      permissions: permissions,
    );

    final docRef = await _db.collection('invitations').add(invitation.toJson());

    debugPrint('InvitationService: Created invitation ${docRef.id} for $inviteeEmail');

    return invitation.copyWith(id: docRef.id);
  }

  /// Accept an invitation using its token.
  ///
  /// Links the user to the installation and updates their profile.
  Future<void> acceptInvitation({
    required String token,
    required String userId,
    required String userEmail,
    String? userName,
  }) async {
    // Find invitation by token
    final query = await _db
        .collection('invitations')
        .where('token', isEqualTo: token.toUpperCase())
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Invalid or expired invitation code.');
    }

    final inviteDoc = query.docs.first;
    final invitation = Invitation.fromFirestore(inviteDoc);

    // Check expiration
    if (DateTime.now().isAfter(invitation.expiresAt)) {
      await inviteDoc.reference.update({'status': 'expired'});
      throw Exception('This invitation has expired.');
    }

    // Run transaction to ensure atomicity
    await _db.runTransaction((transaction) async {
      // Update invitation status
      transaction.update(inviteDoc.reference, {
        'status': 'accepted',
        'accepted_at': FieldValue.serverTimestamp(),
        'accepted_by_user_id': userId,
      });

      // Update user profile
      final userRef = _db.collection('users').doc(userId);
      transaction.update(userRef, {
        'installation_role': 'subUser',
        'installation_id': invitation.installationId,
        'primary_user_id': invitation.primaryUserId,
        'invitation_token': invitation.token,
        'linked_at': FieldValue.serverTimestamp(),
        'sub_user_permissions': invitation.permissions.toJson(),
      });

      // Add to installation's subUsers collection
      final subUserRef = _db
          .collection('installations')
          .doc(invitation.installationId)
          .collection('subUsers')
          .doc(userId);

      transaction.set(subUserRef, {
        'linked_at': FieldValue.serverTimestamp(),
        'permissions': invitation.permissions.toJson(),
        'invited_by': invitation.primaryUserId,
        'invitation_token': invitation.token,
        'user_email': userEmail,
        'user_name': userName ?? userEmail.split('@').first,
      });
    });

    debugPrint('InvitationService: User $userId accepted invitation ${invitation.id}');
  }

  /// Revoke an invitation or remove a sub-user's access.
  Future<void> revokeAccess({
    required String installationId,
    required String userId,
  }) async {
    await _db.runTransaction((transaction) async {
      // Remove from subUsers collection
      final subUserRef = _db
          .collection('installations')
          .doc(installationId)
          .collection('subUsers')
          .doc(userId);

      transaction.delete(subUserRef);

      // Update user profile to unlinked
      final userRef = _db.collection('users').doc(userId);
      transaction.update(userRef, {
        'installation_role': 'unlinked',
        'installation_id': FieldValue.delete(),
        'primary_user_id': FieldValue.delete(),
        'sub_user_permissions': FieldValue.delete(),
        'linked_at': FieldValue.delete(),
      });
    });

    debugPrint('InvitationService: Revoked access for user $userId');
  }

  /// Revoke a pending invitation before it's accepted.
  Future<void> revokeInvitation(String invitationId) async {
    await _db.collection('invitations').doc(invitationId).update({
      'status': 'revoked',
    });

    debugPrint('InvitationService: Revoked invitation $invitationId');
  }

  /// Resend an invitation (creates a new one and revokes the old).
  Future<Invitation> resendInvitation(String invitationId) async {
    final inviteDoc = await _db.collection('invitations').doc(invitationId).get();
    if (!inviteDoc.exists) {
      throw Exception('Invitation not found');
    }

    final oldInvite = Invitation.fromFirestore(inviteDoc);

    // Revoke old invitation
    await revokeInvitation(invitationId);

    // Create new invitation with same details
    return createInvitation(
      installationId: oldInvite.installationId,
      primaryUserId: oldInvite.primaryUserId,
      inviteeEmail: oldInvite.inviteeEmail,
      inviteeName: oldInvite.inviteeName,
      permissions: oldInvite.permissions,
    );
  }

  /// Update a sub-user's permissions.
  Future<void> updatePermissions({
    required String installationId,
    required String userId,
    required SubUserPermissions permissions,
  }) async {
    await _db.runTransaction((transaction) async {
      // Update subUsers collection
      final subUserRef = _db
          .collection('installations')
          .doc(installationId)
          .collection('subUsers')
          .doc(userId);

      transaction.update(subUserRef, {
        'permissions': permissions.toJson(),
      });

      // Update user profile
      final userRef = _db.collection('users').doc(userId);
      transaction.update(userRef, {
        'sub_user_permissions': permissions.toJson(),
      });
    });

    debugPrint('InvitationService: Updated permissions for user $userId');
  }

  /// Stream pending invitations for an installation.
  Stream<List<Invitation>> streamPendingInvitations(String installationId) {
    return _db
        .collection('invitations')
        .where('installation_id', isEqualTo: installationId)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Invitation.fromFirestore(doc)).toList());
  }

  /// Stream all invitations for an installation (including accepted/expired).
  Stream<List<Invitation>> streamAllInvitations(String installationId) {
    return _db
        .collection('invitations')
        .where('installation_id', isEqualTo: installationId)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Invitation.fromFirestore(doc)).toList());
  }

  /// Get sub-user count for an installation.
  Future<int> getSubUserCount(String installationId) async {
    final snapshot = await _db
        .collection('installations')
        .doc(installationId)
        .collection('subUsers')
        .count()
        .get();

    return snapshot.count ?? 0;
  }

  /// Generate a unique 6-character alphanumeric token.
  String _generateToken() {
    // Use characters that are unambiguous (no 0/O, 1/I/l confusion)
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

/// Provider for the invitation service.
final invitationServiceProvider = Provider<InvitationService>((ref) {
  return InvitationService();
});

/// Provider for streaming pending invitations for the current user's installation.
final pendingInvitationsProvider =
    StreamProvider.family<List<Invitation>, String>((ref, installationId) {
  return ref.watch(invitationServiceProvider).streamPendingInvitations(installationId);
});

/// SubUser model for display purposes.
class SubUser {
  final String id;
  final String email;
  final String name;
  final DateTime linkedAt;
  final SubUserPermissions permissions;

  const SubUser({
    required this.id,
    required this.email,
    required this.name,
    required this.linkedAt,
    required this.permissions,
  });

  factory SubUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SubUser(
      id: doc.id,
      email: data['user_email'] as String? ?? '',
      name: data['user_name'] as String? ?? 'Unknown',
      linkedAt: (data['linked_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      permissions: SubUserPermissions.fromJson(data['permissions'] as Map<String, dynamic>?),
    );
  }
}

/// Provider for streaming sub-users for an installation.
final subUsersProvider = StreamProvider.family<List<SubUser>, String>((ref, installationId) {
  return FirebaseFirestore.instance
      .collection('installations')
      .doc(installationId)
      .collection('subUsers')
      .orderBy('linked_at', descending: true)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map((doc) => SubUser.fromFirestore(doc)).toList());
});
