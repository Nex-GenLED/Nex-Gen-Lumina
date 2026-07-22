import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/installer/admin/admin_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Admin PIN entry screen.
///
/// Authenticates via mintStaffToken({mode: 'admin'}) through
/// AdminModeNotifier, then routes to the corporate dashboard. Admin
/// sessions share the corporate dashboard with owner sessions; the
/// privilege boundary (e.g. owner-only writes) is enforced by
/// firestore.rules `hasOwnerClaim()` (commit 004cb9b), not by routing
/// to a different screen.
///
/// This is the dedicated PIN entry point reachable from the Settings
/// page tile. The unified staff-pin screen at /staff/pin (5-tap on
/// the Lumina logo) is the alternate entry — both lead through the
/// same notifier and same Cloud Function call.
class AdminPinScreen extends ConsumerStatefulWidget {
  const AdminPinScreen({super.key});

  @override
  ConsumerState<AdminPinScreen> createState() => _AdminPinScreenState();
}

class _AdminPinScreenState extends ConsumerState<AdminPinScreen> {
  String _enteredPin = '';
  bool _showError = false;
  bool _isValidating = false;
  String _errorMessage = 'Incorrect PIN';
  static const int _pinLength = 4;

  void _onKeyPressed(String key) {
    if (_isValidating) return;
    if (_enteredPin.length < _pinLength) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin += key;
        _showError = false;
      });

      if (_enteredPin.length == _pinLength) {
        _submitPin();
      }
    }
  }

  void _onBackspace() {
    if (_isValidating) return;
    if (_enteredPin.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _showError = false;
      });
    }
  }

  Future<void> _submitPin() async {
    setState(() => _isValidating = true);

    final ok = await ref
        .read(adminModeProvider.notifier)
        .authenticate(_enteredPin);

    if (!mounted) return;

    if (ok) {
      HapticFeedback.mediumImpact();
      // Admin sessions land on the corporate dashboard. Owner-only
      // affordances inside that dashboard are gated by claim checks
      // at the rule layer (and optionally at the UI layer for visual
      // hiding); admins see the same screen with the rule layer
      // enforcing what they can read/write.
      context.go(AppRoutes.corporateDashboard);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _showError = true;
        _errorMessage = 'Incorrect PIN';
        _enteredPin = '';
        _isValidating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Admin Access', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Admin icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NexGenPalette.gunmetal90,
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 48,
                  color: _showError ? Colors.red : Colors.amber,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Enter Admin PIN',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage dealers and installers',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
              ),
              const SizedBox(height: 32),
              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (index) {
                  final isFilled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? (_showError ? Colors.red : Colors.amber)
                          : Colors.transparent,
                      border: Border.all(
                        color: _showError ? Colors.red : Colors.amber.withValues(alpha: 0.7),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              // Error message
              AnimatedOpacity(
                opacity: _showError ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              // Keypad
              _buildKeypad(),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        _buildKeypadRow(['1', '2', '3']),
        const SizedBox(height: 16),
        _buildKeypadRow(['4', '5', '6']),
        const SizedBox(height: 16),
        _buildKeypadRow(['7', '8', '9']),
        const SizedBox(height: 16),
        _buildKeypadRow(['', '0', 'backspace']),
      ],
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.map((key) {
        if (key.isEmpty) {
          return const SizedBox(width: 80, height: 80);
        }
        if (key == 'backspace') {
          return _buildKeypadButton(
            onPressed: _onBackspace,
            child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 28),
          );
        }
        return _buildKeypadButton(
          onPressed: () => _onKeyPressed(key),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeypadButton({required VoidCallback onPressed, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(40),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NexGenPalette.gunmetal90,
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
