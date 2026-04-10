import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_providers.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StaffPinScreen
//
// Unified 4-digit PIN entry that handles all three staff roles:
//
//   • Corporate (Nex-Gen HQ)
//   • Sales (master sales PIN OR per-installer PIN reuse)
//   • Installer (master installer PIN OR per-installer PIN)
//
// Reachable only via the hidden 5-tap gesture on the Lumina logo on the
// login screen. No visible entry point exists. The screen's title is the
// generic "Staff Access" with no indication of which role is being
// requested.
//
// PIN validation is delegated entirely to the existing notifiers. This
// screen never reads from Firestore directly — it just calls the
// notifier methods in the right order and routes on the first one that
// returns true:
//
//   1. CorporateModeNotifier.authenticate(pin)
//        → app_config/master_corporate_pin
//        → routes to AppRoutes.corporateDashboard
//
//   2. InstallerModeNotifier.enterInstallerMode(pin)
//        → app_config/master_installer (master installer PIN)
//        → installers collection by fullPin (per-installer PIN)
//        → routes to AppRoutes.installerLanding
//
//   3. SalesModeNotifier.enterSalesMode(pin)
//        → app_config/master_sales_pin (master sales PIN)
//        → installers collection by fullPin (sales fallback)
//        → routes to AppRoutes.salesLanding
//
// Why this order resolves the per-installer PIN ambiguity: a per-installer
// PIN like "8801" matches BOTH enterInstallerMode's installer-collection
// fallback AND enterSalesMode's installer-collection fallback. By calling
// Installer before Sales, per-installer PINs always claim Installer mode
// first and Sales never sees them. The master sales PIN is the only
// thing that should reach Sales — it doesn't match any installer doc, so
// Installer rejects it and Sales gets the next try.
//
// Why Corporate is first: CorporateModeNotifier.authenticate has no
// installer-collection fallback at all, so it can never accidentally
// claim a per-installer PIN. Putting it first costs nothing and keeps
// the master corporate PIN authoritative.
//
// Lockout: after 5 failed PIN entries, the screen is locked for 30
// seconds with a visible countdown. After the timer elapses, the user
// can try again. The lockout state is local to this screen instance and
// resets if the user dismisses the screen and re-opens it.
//
// IMPORTANT — KNOWN ISSUE for the wizard flow:
//
// lib/features/installer/installer_setup_wizard.dart line 506 calls
// FirebaseAuth.instance.createUserWithEmailAndPassword(...) deep inside
// the customer-account-creation step, AND line 512 calls
// FirebaseAuth.instance.signInAnonymously() to re-establish the session
// after that side effect. Both calls require Anonymous Auth to be
// enabled in the Firebase Console. This screen establishes an anonymous
// session in initState so the notifier Firestore reads work even when
// the user has no Firebase Auth session, but the wizard's deeper auth
// calls have the same dependency and need Anonymous Auth enabled.
//
// Queued for a separate follow-up prompt that migrates the wizard's
// customer-account creation to use the createCustomerAccount Cloud
// Function (built in messaging Prompt 1) instead of the inline
// FirebaseAuth call.
// ─────────────────────────────────────────────────────────────────────────────

class StaffPinScreen extends ConsumerStatefulWidget {
  const StaffPinScreen({super.key});

  @override
  ConsumerState<StaffPinScreen> createState() => _StaffPinScreenState();
}

class _StaffPinScreenState extends ConsumerState<StaffPinScreen>
    with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  bool _isValidating = false;
  int _failedAttempts = 0;
  String? _errorMessage;
  late AnimationController _shakeController;

  // ── Lockout timer state ─────────────────────────────────────────────────
  Timer? _lockoutTimer;
  int _lockoutSecondsRemaining = 0;

  static const int _pinLength = 4;
  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    // Establish a Firebase Auth session before any Firestore reads.
    // The PIN validation paths (app_config/master_*, installers,
    // dealers) all require `request.auth != null` per firestore.rules,
    // and the PINs themselves are short enough that the rule is the
    // actual security boundary — we cannot loosen it. If the user is
    // already signed in (e.g. opened the staff PIN screen from a
    // logged-in session), we leave that session alone. Otherwise we
    // create an anonymous session that will be discarded when the
    // user is bumped to Corporate / Sales / Installer mode.
    //
    // REQUIRES Anonymous Auth to be enabled in the Firebase Console
    // (Authentication → Sign-in method → Anonymous). If it isn't,
    // signInAnonymously() throws admin-restricted-operation and PIN
    // validation will fail with "Invalid PIN".
    _ensureAuthSession();
  }

  Future<void> _ensureAuthSession() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    try {
      await FirebaseAuth.instance.signInAnonymously();
      debugPrint('StaffPinScreen: anonymous auth session established');
    } catch (e) {
      debugPrint('StaffPinScreen: signInAnonymously failed: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Auth unavailable. Enable Anonymous sign-in in Firebase.';
        });
      }
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  bool get _isLockedOut => _lockoutSecondsRemaining > 0;

  void _onDigit(String digit) {
    if (_isValidating || _isLockedOut) return;
    if (_enteredPin.length >= _pinLength) return;

    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });

    if (_enteredPin.length == _pinLength) {
      _validatePin();
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty || _isValidating || _isLockedOut) return;
    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  // ── PIN validation pipeline ────────────────────────────────────────────
  //
  // Delegates entirely to the existing notifiers — no direct Firestore
  // reads, no hashing, no field-name assumptions. Each notifier handles
  // its own master-PIN + fallback logic internally. We just call them
  // in the right order and route on the first one that returns true.
  //
  // Order: Corporate → Installer → Sales. See the header comment for
  // why this ordering resolves the per-installer PIN ambiguity.

  Future<void> _validatePin() async {
    setState(() => _isValidating = true);

    final pin = _enteredPin;

    // ── 1. Corporate ──
    final corporateOk = await ref
        .read(corporateModeProvider.notifier)
        .authenticate(pin);
    if (!mounted) return;
    if (corporateOk) {
      _onSuccess(AppRoutes.corporateDashboard);
      return;
    }

    // ── 2. Installer ──
    final installerOk = await ref
        .read(installerModeActiveProvider.notifier)
        .enterInstallerMode(pin);
    if (!mounted) return;
    if (installerOk) {
      _onSuccess(AppRoutes.installerLanding);
      return;
    }

    // ── 3. Sales ──
    final salesOk = await ref
        .read(salesModeProvider.notifier)
        .enterSalesMode(pin);
    if (!mounted) return;
    if (salesOk) {
      _onSuccess(AppRoutes.salesLanding);
      return;
    }

    // ── No match anywhere ──
    _onFailure();
  }

  void _onSuccess(String route) {
    HapticFeedback.mediumImpact();
    _failedAttempts = 0;
    context.go(route);
  }

  void _onFailure() {
    _failedAttempts++;
    _shakeController.forward(from: 0);
    HapticFeedback.heavyImpact();

    if (_failedAttempts >= _maxAttempts) {
      _startLockout();
      return;
    }

    setState(() {
      _enteredPin = '';
      _isValidating = false;
      _errorMessage =
          'Invalid PIN. ${_maxAttempts - _failedAttempts} attempts remaining.';
    });
  }

  // ── Lockout countdown ──────────────────────────────────────────────────

  void _startLockout() {
    setState(() {
      _enteredPin = '';
      _isValidating = false;
      _lockoutSecondsRemaining = _lockoutDuration.inSeconds;
      _errorMessage =
          'Too many attempts. Locked for ${_lockoutSecondsRemaining}s.';
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _lockoutSecondsRemaining--;
        if (_lockoutSecondsRemaining <= 0) {
          timer.cancel();
          _failedAttempts = 0;
          _errorMessage = null;
          _lockoutSecondsRemaining = 0;
        } else {
          _errorMessage =
              'Too many attempts. Locked for ${_lockoutSecondsRemaining}s.';
        }
      });
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Subtle title — no role indication
            Text(
              'Staff Access',
              style: GoogleFonts.montserrat(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter 4-digit PIN',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 32),

            // PIN dots — solid cyan, no role hint
            AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final offset = _shakeController.isAnimating
                    ? 10.0 *
                        (0.5 - _shakeController.value).abs() *
                        (_shakeController.value < 0.5 ? -1 : 1)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (i) {
                  final isFilled = i < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? NexGenPalette.cyan
                          : Colors.transparent,
                      border: Border.all(
                        color: isFilled
                            ? NexGenPalette.cyan
                            : Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Status row — error message OR validating spinner
            const SizedBox(height: 16),
            SizedBox(
              height: 20,
              child: _errorMessage != null
                  ? Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: _isLockedOut
                            ? NexGenPalette.amber
                            : Colors.red,
                        fontSize: 13,
                      ),
                    )
                  : _isValidating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NexGenPalette.cyan,
                          ),
                        )
                      : null,
            ),

            const Spacer(flex: 1),

            // Numeric keypad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                children: [
                  _buildKeypadRow(['1', '2', '3']),
                  const SizedBox(height: 12),
                  _buildKeypadRow(['4', '5', '6']),
                  const SizedBox(height: 12),
                  _buildKeypadRow(['7', '8', '9']),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 72, height: 72),
                      _buildKeypadButton('0'),
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: IconButton(
                          onPressed:
                              _isLockedOut || _isValidating ? null : _onBackspace,
                          icon: Icon(
                            Icons.backspace_outlined,
                            color: _isLockedOut || _isValidating
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map(_buildKeypadButton).toList(),
    );
  }

  Widget _buildKeypadButton(String digit) {
    final disabled = _isLockedOut || _isValidating;
    return SizedBox(
      width: 72,
      height: 72,
      child: TextButton(
        onPressed: disabled ? null : () => _onDigit(digit),
        style: TextButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: Colors.white.withValues(alpha: 0.06),
        ),
        child: Text(
          digit,
          style: GoogleFonts.montserrat(
            fontSize: 28,
            fontWeight: FontWeight.w400,
            color: disabled
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white,
          ),
        ),
      ),
    );
  }
}
