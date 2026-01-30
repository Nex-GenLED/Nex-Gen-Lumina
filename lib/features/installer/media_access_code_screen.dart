import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';

/// Screen for entering a 6-character media access code.
///
/// Media codes are separate from installer PINs and grant view-only
/// access to customer systems for content creation purposes.
class MediaAccessCodeScreen extends ConsumerStatefulWidget {
  const MediaAccessCodeScreen({super.key});

  @override
  ConsumerState<MediaAccessCodeScreen> createState() => _MediaAccessCodeScreenState();
}

class _MediaAccessCodeScreenState extends ConsumerState<MediaAccessCodeScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  int _attemptCount = 0;
  static const int _maxAttempts = 5;

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
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Media Access', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NexGenPalette.gunmetal90,
                  border: Border.all(color: NexGenPalette.magenta.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: NexGenPalette.magenta.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          color: NexGenPalette.magenta,
                          strokeWidth: 3,
                        ),
                      )
                    : Icon(
                        Icons.videocam_outlined,
                        size: 48,
                        color: _errorMessage != null ? Colors.red : NexGenPalette.magenta,
                      ),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                'Enter Media Access Code',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Your 6-character code from Nex-Gen media team',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Code input field
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                enabled: !_isLoading && _attemptCount < _maxAttempts,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  _UpperCaseTextFormatter(),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '------',
                  hintStyle: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                    fontSize: 28,
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
                    borderSide: const BorderSide(color: NexGenPalette.magenta, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                ),
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

              // Error message
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

              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_isLoading || _codeController.text.length != 6 || _attemptCount >= _maxAttempts)
                      ? null
                      : _submitCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.magenta,
                    disabledBackgroundColor: NexGenPalette.magenta.withValues(alpha: 0.3),
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
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Verify Code',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const Spacer(),

              // Footer help text
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  "Don't have a code? Contact media@nexgenled.com",
                  style: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();

    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter a 6-character code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check for the code in Firestore media_codes collection
      final query = await FirebaseFirestore.instance
          .collection('media_codes')
          .where('code', isEqualTo: code)
          .where('is_active', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _attemptCount++;
          _errorMessage = 'Invalid access code. ${_maxAttempts - _attemptCount} attempts remaining.';
          _codeController.clear();
        });

        if (_attemptCount >= _maxAttempts) {
          _showLockoutDialog();
        }
        return;
      }

      final codeDoc = query.docs.first;
      final codeData = codeDoc.data();

      // Check expiration if set
      final expiresAt = codeData['expires_at'] as Timestamp?;
      if (expiresAt != null && DateTime.now().isAfter(expiresAt.toDate())) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'This access code has expired.';
          _codeController.clear();
        });
        return;
      }

      // Get media user info from the code
      final mediaUserName = codeData['name'] as String? ?? 'Media User';
      final mediaCompany = codeData['company'] as String? ?? 'Nex-Gen Media';
      final dealerCode = codeData['dealer_code'] as String? ?? '00';

      // Create a media session using the installer session provider
      // This allows reuse of existing "View As" infrastructure
      ref.read(installerSessionProvider.notifier).state = InstallerSession(
        installer: InstallerInfo(
          installerCode: code.substring(3, 6), // Last 3 chars as "installer" code
          dealerCode: dealerCode,
          name: mediaUserName,
        ),
        dealer: DealerInfo(
          dealerCode: dealerCode,
          name: 'Media Team',
          companyName: mediaCompany,
        ),
        authenticatedAt: DateTime.now(),
      );

      // Log media access for auditing
      await FirebaseFirestore.instance.collection('media_access_logs').add({
        'code': code,
        'code_id': codeDoc.id,
        'user_name': mediaUserName,
        'accessed_at': FieldValue.serverTimestamp(),
        'auth_user_id': FirebaseAuth.instance.currentUser?.uid,
      });

      // Navigate to media dashboard
      if (mounted) {
        HapticFeedback.mediumImpact();
        context.go(AppRoutes.mediaDashboard);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Verification failed: $e';
      });
    }
  }

  void _showLockoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Too Many Attempts', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You have exceeded the maximum number of attempts. Please try again later or contact support.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.pop();
            },
            child: const Text('OK', style: TextStyle(color: NexGenPalette.magenta)),
          ),
        ],
      ),
    );
  }
}

/// Text input formatter that converts text to uppercase.
class _UpperCaseTextFormatter extends TextInputFormatter {
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
