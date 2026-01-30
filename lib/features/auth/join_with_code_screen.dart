import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:nexgen_command/models/sub_user_permissions.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

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
        child: Padding(
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

  Future<void> _submitCode() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _codeController.text.trim().toUpperCase();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => _errorMessage = 'You must be signed in to join.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Find invitation by token
      final query = await FirebaseFirestore.instance
          .collection('invitations')
          .where('token', isEqualTo: code)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid or expired invitation code.';
        });
        return;
      }

      final inviteDoc = query.docs.first;
      final inviteData = inviteDoc.data();

      // Check expiration
      final expiresAt = (inviteData['expires_at'] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        await inviteDoc.reference.update({'status': 'expired'});
        setState(() {
          _isLoading = false;
          _errorMessage = 'This invitation has expired.';
        });
        return;
      }

      final installationId = inviteData['installation_id'] as String;
      final primaryUserId = inviteData['primary_user_id'] as String;
      final permissions = SubUserPermissions.fromJson(
        inviteData['permissions'] as Map<String, dynamic>?,
      );

      // Update invitation status
      await inviteDoc.reference.update({
        'status': 'accepted',
        'accepted_at': FieldValue.serverTimestamp(),
        'accepted_by_user_id': user.uid,
      });

      // Update user profile
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'installation_role': InstallationRole.subUser.name,
        'installation_id': installationId,
        'primary_user_id': primaryUserId,
        'invitation_token': code,
        'linked_at': FieldValue.serverTimestamp(),
        'sub_user_permissions': permissions.toJson(),
      });

      // Add to installation's subUsers collection
      await FirebaseFirestore.instance
          .collection('installations')
          .doc(installationId)
          .collection('subUsers')
          .doc(user.uid)
          .set({
        'linked_at': FieldValue.serverTimestamp(),
        'permissions': permissions.toJson(),
        'invited_by': primaryUserId,
        'invitation_token': code,
        'user_email': user.email,
        'user_name': user.displayName ?? user.email?.split('@').first ?? 'User',
      });

      // Success! Navigate to dashboard
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully joined! Welcome to the system.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go(AppRoutes.dashboard);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to join: $e';
      });
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
