import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:nexgen_command/models/sub_user_permissions.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

/// Upper bound on each server round trip while joining.
const Duration _kJoinTimeout = Duration(seconds: 15);

/// Screen for entering a 6-character invitation code to join an installation.
///
/// When a valid code is entered, the user's account is linked to the
/// installation as a sub-user with the permissions defined in the invitation.
class JoinWithCodeScreen extends ConsumerStatefulWidget {
  const JoinWithCodeScreen({super.key});

  @override
  ConsumerState<JoinWithCodeScreen> createState() => _JoinWithCodeScreenState();
}

class _JoinWithCodeScreenState extends ConsumerState<JoinWithCodeScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Join with Code', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                const Text(
                  'Enter Invitation Code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Enter the 6-character code you received from the system owner.',
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),
                // Code input
                TextFormField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    UpperCaseTextFormatter(),
                  ],
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '------',
                    hintStyle: TextStyle(
                      color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                      fontSize: 32,
                      letterSpacing: 8,
                    ),
                    filled: true,
                    fillColor: NexGenPalette.gunmetal90,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: NexGenPalette.cyan, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length != 6) {
                      return 'Please enter a 6-character code';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    if (_errorMessage != null) {
                      setState(() => _errorMessage = null);
                    }
                    // Auto-submit when 6 characters entered
                    if (value.length == 6) {
                      _submitCode();
                    }
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Join',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                // Help text
                Center(
                  child: Text(
                    "Don't have a code? Ask the system owner to invite you.",
                    style: TextStyle(
                      color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
  }

  /// Joins the home the code belongs to.
  ///
  /// Row 17 (+110): the invitation used to be marked accepted FIRST, then the
  /// profile updated, then the roster written — three separate writes. When
  /// the second one failed the customer saw "Failed to join" while the code
  /// was already spent, and every retry said "Invalid or expired". The
  /// profile link and the acceptance are now ONE batch, profile first and
  /// invitation last: they land together or not at all, so a failed join
  /// never consumes the code.
  Future<void> _submitCode() async {
    // The field auto-submits at six characters and the button can be tapped
    // too; only one join runs at a time.
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    final code = _codeController.text.trim().toUpperCase();
    final session = ref.read(accountSessionProvider);
    final uid = session.uid;

    if (!session.isSignedIn || uid == null) {
      setState(() => _errorMessage = 'You must be signed in to join.');
      return;
    }
    final email = session.email?.trim().toLowerCase() ?? '';
    if (email.isEmpty) {
      setState(() => _errorMessage =
          'Sign in with the email address your invitation was sent to, '
          'then enter the code again.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final db = ref.read(accountFirestoreProvider);
    final QueryDocumentSnapshot<Map<String, dynamic>> inviteDoc;
    try {
      // The security rules let an invitee read an invitation only when it is
      // addressed to their own email. A query by code alone cannot show that,
      // so Firestore refused it outright; saying which email makes it a query
      // the rules can allow. (Invitations store the email lower-cased.)
      final query = await db
          .collection('invitations')
          .where('token', isEqualTo: code)
          .where('invitee_email', isEqualTo: email)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get()
          .timeout(_kJoinTimeout);
      if (query.docs.isEmpty) {
        _fail("That code isn't valid for $email. Check the code, and make "
            "sure you're signed in with the email address the invitation "
            'was sent to.');
        return;
      }
      inviteDoc = query.docs.first;
    } on TimeoutException {
      _fail("Couldn't reach the server. Check your connection and try "
          'again.');
      return;
    } catch (e) {
      _fail("Couldn't look up that code: $e");
      return;
    }

    final inviteData = inviteDoc.data();
    final expiresAt = inviteData['expires_at'];
    if (expiresAt is Timestamp && DateTime.now().isAfter(expiresAt.toDate())) {
      try {
        await inviteDoc.reference
            .update({'status': 'expired'}).timeout(_kJoinTimeout);
      } catch (e) {
        debugPrint('JoinWithCode: could not mark invitation expired: $e');
      }
      _fail('This invitation has expired. Ask the system owner for a new '
          'code.');
      return;
    }

    final installationId = inviteData['installation_id'] as String?;
    final primaryUserId = inviteData['primary_user_id'] as String?;
    if (installationId == null || primaryUserId == null) {
      _fail('This invitation is incomplete. Ask the system owner for a new '
          'code.');
      return;
    }
    final permissions = SubUserPermissions.fromJson(
      inviteData['permissions'] as Map<String, dynamic>?,
    );

    try {
      final batch = db.batch()
        ..update(db.collection('users').doc(uid), {
          'installation_role': InstallationRole.subUser.name,
          'installation_id': installationId,
          'primary_user_id': primaryUserId,
          'invitation_token': code,
          'linked_at': FieldValue.serverTimestamp(),
          'sub_user_permissions': permissions.toJson(),
        })
        ..update(inviteDoc.reference, {
          'status': 'accepted',
          'accepted_at': FieldValue.serverTimestamp(),
          'accepted_by_user_id': uid,
        });
      await batch.commit().timeout(_kJoinTimeout);
    } on TimeoutException {
      // The batch may still land when the connection returns — and if it
      // does, both halves land together.
      _fail("We couldn't confirm your join. Check your connection and tap "
          'Join again.');
      return;
    } catch (e) {
      _fail('Failed to join: $e\nYour code has not been used — you can try '
          'again.');
      return;
    }

    // The owner's "Manage Users" roster. Best effort, after the join has
    // committed: the rules allow only the owner to write this collection
    // today, so a refusal here must not undo or misreport a join that
    // succeeded.
    try {
      await db
          .collection('installations')
          .doc(installationId)
          .collection('subUsers')
          .doc(uid)
          .set({
        'linked_at': FieldValue.serverTimestamp(),
        'permissions': permissions.toJson(),
        'invited_by': primaryUserId,
        'invitation_token': code,
        'user_email': email,
        'user_name': session.displayName ?? email.split('@').first,
      }).timeout(_kJoinTimeout);
    } catch (e) {
      debugPrint('JoinWithCode: roster entry not written ($e); the join '
          'itself succeeded.');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully joined! Welcome to the system.'),
          backgroundColor: Colors.green,
        ),
      );
      context.go(AppRoutes.dashboard);
    }
  }
}

/// Text input formatter that converts text to uppercase.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
