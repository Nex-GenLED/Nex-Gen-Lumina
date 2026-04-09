import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/models/dealer_messaging_config.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/services/dealer_messaging_config_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sales Session
// ─────────────────────────────────────────────────────────────────────────────

class SalesSession {
  final String salespersonUid;
  final String dealerCode;
  final DateTime authenticatedAt;

  const SalesSession({
    required this.salespersonUid,
    required this.dealerCode,
    required this.authenticatedAt,
  });
}

final currentSalesSessionProvider = StateProvider<SalesSession?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Active Job (the job currently being built during a sales visit)
// ─────────────────────────────────────────────────────────────────────────────

final activeJobProvider = StateProvider<SalesJob?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Sales Mode Notifier — mirrors InstallerModeNotifier exactly
// ─────────────────────────────────────────────────────────────────────────────

const Duration kSalesSessionTimeout = Duration(minutes: 30);
const Duration kSalesSessionWarningThreshold = Duration(minutes: 5);

class SalesModeNotifier extends StateNotifier<bool> {
  SalesModeNotifier(this._ref) : super(false);

  final Ref _ref;
  Timer? _sessionTimer;
  Timer? _warningTimer;

  /// Callback for session timeout warning (set by UI)
  VoidCallback? onSessionWarning;

  bool get isActive => state;

  static const int _maxAttempts = 5;
  int _failedAttempts = 0;

  /// Validate PIN against Firestore app_config/master_sales_pin
  Future<bool> enterSalesMode(String enteredPin) async {
    if (_failedAttempts >= _maxAttempts) {
      debugPrint('Sales mode: locked out after $_maxAttempts failed attempts');
      return false;
    }

    if (enteredPin.length != 4) return false;

    try {
      // Hash the entered PIN
      final enteredHash = sha256.convert(utf8.encode(enteredPin)).toString();

      // Check master sales PIN from Firestore
      final configDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('master_sales_pin')
          .get();

      if (configDoc.exists) {
        final storedHash = configDoc.data()?['pin_hash'] as String?;
        if (storedHash != null && storedHash == enteredHash) {
          _failedAttempts = 0;

          // Extract dealer code from first 2 digits
          final dealerCode = enteredPin.substring(0, 2);

          _ref.read(currentSalesSessionProvider.notifier).state = SalesSession(
            salespersonUid: enteredPin,
            dealerCode: dealerCode,
            authenticatedAt: DateTime.now(),
          );

          _startSessionTimer();
          state = true;
          debugPrint('Sales mode: activated with dealer code $dealerCode');
          return true;
        }
      }

      // Fallback: check against installers collection with PIN match
      // (allows reuse of existing dealer/installer PIN infrastructure)
      final installerQuery = await FirebaseFirestore.instance
          .collection('installers')
          .where('fullPin', isEqualTo: enteredPin)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (installerQuery.docs.isNotEmpty) {
        final installerData = installerQuery.docs.first.data();
        final dealerCode = installerData['dealerCode'] as String? ?? enteredPin.substring(0, 2);

        // Verify dealer is active
        final dealerQuery = await FirebaseFirestore.instance
            .collection('dealers')
            .where('dealerCode', isEqualTo: dealerCode)
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();

        if (dealerQuery.docs.isNotEmpty) {
          _failedAttempts = 0;

          _ref.read(currentSalesSessionProvider.notifier).state = SalesSession(
            salespersonUid: installerQuery.docs.first.id,
            dealerCode: dealerCode,
            authenticatedAt: DateTime.now(),
          );

          _startSessionTimer();
          state = true;
          debugPrint('Sales mode: activated via installer PIN for dealer $dealerCode');
          return true;
        }
      }

      _failedAttempts++;
      debugPrint('Sales mode: failed attempt $_failedAttempts/$_maxAttempts');
      return false;
    } catch (e) {
      debugPrint('Sales mode: validation error: $e');
      _failedAttempts++;
      return false;
    }
  }

  void exitSalesMode() {
    _sessionTimer?.cancel();
    _warningTimer?.cancel();
    _ref.read(currentSalesSessionProvider.notifier).state = null;
    _ref.read(activeJobProvider.notifier).state = null;
    state = false;
    debugPrint('Sales mode: deactivated');
  }

  void recordActivity() {
    // Reset the session timer on activity
    _startSessionTimer();
  }

  void extendSession() {
    _startSessionTimer();
    debugPrint('Sales mode: session extended');
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _warningTimer?.cancel();

    // Warning timer fires 5 minutes before timeout
    final warningDelay = kSalesSessionTimeout - kSalesSessionWarningThreshold;
    _warningTimer = Timer(warningDelay, () {
      onSessionWarning?.call();
    });

    // Session timeout
    _sessionTimer = Timer(kSalesSessionTimeout, () {
      debugPrint('Sales mode: session timed out');
      exitSalesMode();
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _warningTimer?.cancel();
    super.dispose();
  }
}

final salesModeProvider =
    StateNotifierProvider<SalesModeNotifier, bool>((ref) {
  return SalesModeNotifier(ref);
});

// Convenience alias for watching active state
final salesModeActiveProvider = salesModeProvider;

// ─────────────────────────────────────────────────────────────────────────────
// Sales Jobs Stream — streams jobs for the current dealer
// ─────────────────────────────────────────────────────────────────────────────

final salesJobsStreamProvider = StreamProvider<List<SalesJob>>((ref) {
  final session = ref.watch(currentSalesSessionProvider);
  if (session == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('sales_jobs')
      .where('dealerCode', isEqualTo: session.dealerCode)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => SalesJob.fromJson(doc.data()))
          .toList());
});

// ─────────────────────────────────────────────────────────────────────────────
// Sales Jobs By Status — server-side filtered stream
//
// Pass `null` (or an empty list) to return all jobs for the current dealer.
// Pass a list of [SalesJobStatus] values to apply a Firestore
// `where('status', whereIn: [...])` clause server-side. The Day 1 queue
// uses this to fetch `[estimateSigned, prewireScheduled]` in one query.
//
// Dealer code resolution: prefers the active sales session (Sales Mode);
// falls back to the active installer session (Installer Mode) so the same
// provider can power both the salesperson's "My Estimates" list and the
// electrician's Day 1 queue.
//
// Note: combining `where('dealerCode')` + `where('status', whereIn: ...)`
// + `orderBy('createdAt')` reuses the existing composite index on
// `dealerCode + status + createdAt` (Firestore handles whereIn against
// the same index). No second composite index is required.
// ─────────────────────────────────────────────────────────────────────────────

final salesJobsByStatusProvider =
    StreamProvider.family<List<SalesJob>, List<SalesJobStatus>?>(
        (ref, statuses) {
  // Prefer the sales session, fall back to the installer session.
  final salesSession = ref.watch(currentSalesSessionProvider);
  final installerSession = ref.watch(installerSessionProvider);
  final dealerCode =
      salesSession?.dealerCode ?? installerSession?.dealer.dealerCode;
  if (dealerCode == null || dealerCode.isEmpty) {
    return const Stream.empty();
  }

  Query<Map<String, dynamic>> query = FirebaseFirestore.instance
      .collection('sales_jobs')
      .where('dealerCode', isEqualTo: dealerCode);

  if (statuses != null && statuses.isNotEmpty) {
    query = query.where(
      'status',
      whereIn: statuses.map((s) => s.name).toList(),
    );
  }

  return query
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => SalesJob.fromJson(doc.data()))
          .toList());
});

// ─────────────────────────────────────────────────────────────────────────────
// Dealer Messaging Config — live stream of dealers/{dealerCode}/config/messaging
//
// Family-keyed by dealerCode so the config screen can pass the resolved
// dealer code from the dealer dashboard tab. Emits
// DealerMessagingConfig.defaults() when the document doesn't exist yet,
// so the screen always renders something and freshly-provisioned
// dealers don't see a loading spinner forever.
// ─────────────────────────────────────────────────────────────────────────────

final dealerMessagingConfigProvider =
    StreamProvider.family<DealerMessagingConfig, String>((ref, dealerCode) {
  final service = ref.watch(dealerMessagingConfigServiceProvider);
  return service.watchConfig(dealerCode);
});

// ─────────────────────────────────────────────────────────────────────────────
// Job Number Generator
// ─────────────────────────────────────────────────────────────────────────────

Future<String> generateJobNumber() async {
  final now = DateTime.now();
  final dateStr =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

  // Count existing jobs created today
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  final todayJobs = await FirebaseFirestore.instance
      .collection('sales_jobs')
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
      .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
      .count()
      .get();

  final count = (todayJobs.count ?? 0) + 1;
  return 'NXG-$dateStr-${count.toString().padLeft(3, '0')}';
}
