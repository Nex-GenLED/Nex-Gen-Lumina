import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Dialog to obtain user consent for community pattern sharing
///
/// SECURITY & PRIVACY:
/// - Explains what data is shared (patterns, builder, floor plan)
/// - Requires explicit opt-in (default is OFF)
/// - Includes Terms of Service agreement
/// - Allows users to revoke consent at any time
class CommunitySharingConsentDialog extends ConsumerStatefulWidget {
  const CommunitySharingConsentDialog({super.key});

  @override
  ConsumerState<CommunitySharingConsentDialog> createState() =>
      _CommunitySharingConsentDialogState();
}

class _CommunitySharingConsentDialogState
    extends ConsumerState<CommunitySharingConsentDialog> {
  bool _acceptedTerms = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.share, color: Colors.cyan),
          SizedBox(width: 12),
          Text('Community Pattern Sharing'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share your custom lighting patterns with the Lumina community!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            const Text(
              'What we share:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.palette, 'Your custom pattern designs'),
            _buildInfoRow(Icons.home, 'Your home builder (e.g., "Summit Homes")'),
            _buildInfoRow(Icons.floor_plan, 'Your floor plan (e.g., "The Preston")'),
            const SizedBox(height: 16),
            const Text(
              'What we DON\'T share:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.location_off, 'Your address or location', color: Colors.green),
            _buildInfoRow(Icons.person_off, 'Your name or email', color: Colors.green),
            _buildInfoRow(Icons.phone_disabled, 'Your contact information', color: Colors.green),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyan.withOpacity(0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✨ Why share?',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Help homeowners with similar architecture find patterns that look great on their homes!',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _acceptedTerms,
              onChanged: (value) {
                setState(() {
                  _acceptedTerms = value ?? false;
                });
              },
              title: const Text(
                'I agree to the Community Sharing Terms',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'You can revoke consent at any time in Settings',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('No Thanks'),
        ),
        ElevatedButton(
          onPressed: _isLoading || !_acceptedTerms ? null : _enableSharing,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enable Sharing'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enableSharing() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProfile = ref.read(userProfileProvider).value;
      if (userProfile == null) {
        throw Exception('User profile not found');
      }

      // Update user profile with consent
      final updatedProfile = userProfile.copyWith(
        communityPatternSharing: true,
      );

      final userService = UserService();
      await userService.updateUser(updatedProfile);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Community sharing enabled! Thank you for contributing.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error enabling sharing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

/// Show the community sharing consent dialog
///
/// Returns true if user consented, false if declined
Future<bool?> showCommunitySharingConsentDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const CommunitySharingConsentDialog(),
  );
}
