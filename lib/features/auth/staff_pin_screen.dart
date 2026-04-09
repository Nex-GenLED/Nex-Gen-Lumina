import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
//   • Corporate (Nex-Gen HQ)        — app_config/master_corporate_pin
//   • Sales (master sales PIN)      — app_config/master_sales_pin
//   • Installer (master + per-installer)
//                                   — app_config/master_installer
//                                   — installers/{auto}.fullPin
//
// Reachable only via the hidden 5-tap gesture on the Lumina logo on the
// login screen. No visible entry point exists. The screen's title is the
// generic "Staff Access" with no indication of which role is being
// requested.
//
// PIN routing logic (Option C — explicit hash checks before fallback):
//
//   1. Compute SHA-256 of the entered PIN once.
//   2. Read app_config/master_corporate_pin. If pin_hash matches →
//      call CorporateModeNotifier.authenticate(pin) → route to
//      AppRoutes.corporateDashboard.
//   3. Read app_config/master_sales_pin. If pin_hash matches →
//      call SalesModeNotifier.enterSalesMode(pin) → route to
//      AppRoutes.salesLanding.
//   4. Read app_config/master_installer. If pin_hash matches →
//      call InstallerModeNotifier.enterInstallerMode(pin) → route to
//      AppRoutes.installerLanding.
//   5. Fall through: call InstallerModeNotifier.enterInstallerMode(pin)
//      which checks the installers collection for individual installer
//      PINs. If it returns true → route to AppRoutes.installerLanding.
//   6. Otherwise: "Invalid PIN", clear, increment failed-attempts counter.
//
// Why this order resolves the master/installer overlap: master Corporate
// and master Sales PINs are explicit hash matches, so they take priority
// over the installer collection fallback. An individual installer PIN
// (e.g. dealer 88 + installer 01 = "8801") doesn't match any of the
// master hashes and falls through to enterInstallerMode's collection
// lookup, landing the user in Installer mode — not Sales mode, even
// though SalesModeNotifier.enterSalesMode also has a fallback to the
// installers collection.
//
// Lockout: after 5 failed PIN entries, the screen is locked for 30
// seconds with a visible countdown. After the timer elapses, the user
// can try again. The lockout state is local to this screen instance and
// resets if the user dismisses the screen and re-opens it.
//
// IMPORTANT — KNOWN ISSUE for the wizard flow:
//
// This screen does NOT call FirebaseAuth.signInAnonymously(). The PIN
// validation only does Firestore reads, which work without auth as
// long as the security rules allow unauthenticated reads on
// app_config/* and installers/* (they currently do for these specific
// docs).
//
// HOWEVER, lib/features/installer/installer_setup_wizard.dart line 506
// calls FirebaseAuth.instance.createUserWithEmailAndPassword(...) deep
// inside the customer-account-creation step, AND line 512 calls
// FirebaseAuth.instance.signInAnonymously() to re-establish the session
// after that side effect. Both calls fail when Anonymous Auth is
// disabled in the Firebase Console. The previous login-screen behavior
// hid this by establishing an anonymous session up front; with that
// removed, an installer entering the wizard via this PIN screen will
// hit the same auth failure deeper in the flow.
//
// This is queued for a separate follow-up prompt that migrates the
// wizard's customer-account creation to use the createCustomerAccount
// Cloud Function (built in messaging Prompt 1) instead of the inline
// FirebaseAuth call. For now: the staff PIN screen works end-to-end
// for Corporate, Sales, and Installer mode entry; the install wizard's
// customer-account step still requires Anonymous Auth to be enabled in
// the Firebase Console.
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

  // ── Hash + master-PIN check helpers ────────────────────────────────────

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  /// Read [docName] under app_config and compare its `pin_hash` field
  /// against [enteredHash]. Returns false on missing doc, missing field,
  /// or any read error — never throws. Used to gate the three master-PIN
  /// check stages before falling through to enterInstallerMode().
  Future<bool> _checkMasterHash({
    required String docName,
    required String enteredHash,
  }) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_config')
          .doc(docName)
          .get();
      if (!snap.exists) return false;
      final stored = snap.data()?['pin_hash'] as String?;
      if (stored == null || stored.isEmpty) return false;
      return stored == enteredHash;
    } catch (_) {
      return false;
    }
  }

  // ── PIN validation pipeline ────────────────────────────────────────────

  Future<void> _validatePin() async {
    setState(() => _isValidating = true);

    final pin = _enteredPin;
    final hash = _hashPin(pin);

    // ── Stage 1: Corporate master PIN ──
    if (await _checkMasterHash(
      docName: 'master_corporate_pin',
      enteredHash: hash,
    )) {
      final ok = await ref
          .read(corporateModeProvider.notifier)
          .authenticate(pin);
      if (!mounted) return;
      if (ok) {
        _onSuccess(AppRoutes.corporateDashboard);
        return;
      }
      // Hash matched but the notifier rejected — fall through to the
      // failure path. Should be impossible in practice but handled
      // defensively so we don't show success UI on a failed authenticate.
    }

    // ── Stage 2: Sales master PIN ──
    if (await _checkMasterHash(
      docName: 'master_sales_pin',
      enteredHash: hash,
    )) {
      final ok = await ref
          .read(salesModeProvider.notifier)
          .enterSalesMode(pin);
      if (!mounted) return;
      if (ok) {
        _onSuccess(AppRoutes.salesLanding);
        return;
      }
    }

    // ── Stage 3: Installer master PIN ──
    //
    // Note: the doc name is 'master_installer' (not 'master_installer_pin'
    // — the installer notifier diverges from the corporate/sales naming).
    if (await _checkMasterHash(
      docName: 'master_installer',
      enteredHash: hash,
    )) {
      final ok = await ref
          .read(installerModeActiveProvider.notifier)
          .enterInstallerMode(pin);
      if (!mounted) return;
      if (ok) {
        _onSuccess(AppRoutes.installerLanding);
        return;
      }
    }

    // ── Stage 4: Fall through to per-installer PIN lookup ──
    //
    // enterInstallerMode does its own master + installers-collection
    // checks internally. We've already ruled out the master hash above,
    // so this call effectively just runs the installers-collection
    // lookup. If a matching active installer + active dealer is found,
    // the notifier returns true.
    final installerOk = await ref
        .read(installerModeActiveProvider.notifier)
        .enterInstallerMode(pin);
    if (!mounted) return;
    if (installerOk) {
      _onSuccess(AppRoutes.installerLanding);
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
