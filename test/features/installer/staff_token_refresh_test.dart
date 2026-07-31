// Token-refresh + anonymous-fallback instrumentation (P0-1 / D4 gate).
//
// Covers the two pieces that are testable without a live Firebase Auth
// session: the custom-token expiry decision, and the telemetry row whose
// count gates the D4 rules deploy (S-5). The sign-in calls themselves are
// plugin-bound and are verified on-device instead — see
// audit/TOKEN_REFRESH_REPORT.md Part 4.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';
import 'package:nexgen_command/features/installer/staff_auth_telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // staffAuthDeviceId() persists through SharedPreferences.
    SharedPreferences.setMockInitialValues({});
  });

  group('staffTokenNeedsRefresh — the 1-hour custom-token TTL', () {
    final mint = DateTime(2026, 8, 6, 9, 0, 0);

    test('a token minted seconds ago is used as-is (no callable burned)', () {
      expect(
        staffTokenNeedsRefresh(
          authenticatedAt: mint,
          now: mint.add(const Duration(seconds: 30)),
        ),
        isFalse,
      );
    });

    test('still fresh just inside the 50-minute safety margin', () {
      expect(
        staffTokenNeedsRefresh(
          authenticatedAt: mint,
          now: mint.add(const Duration(minutes: 49, seconds: 59)),
        ),
        isFalse,
      );
    });

    test('refreshes AT the margin — before the real 60-minute expiry', () {
      expect(
        staffTokenNeedsRefresh(
          authenticatedAt: mint,
          now: mint.add(const Duration(minutes: 50)),
        ),
        isTrue,
      );
    });

    test('a long pixel-walk (75 min) refreshes', () {
      expect(
        staffTokenNeedsRefresh(
          authenticatedAt: mint,
          now: mint.add(const Duration(minutes: 75)),
        ),
        isTrue,
      );
    });

    test('the margin leaves real headroom before the hard TTL', () {
      // Regression guard: if anyone widens the margin past 60 minutes the
      // refresh would fire only after the token was already dead.
      expect(kStaffTokenSafetyMargin, lessThan(const Duration(minutes: 60)));
    });
  });

  group('recordAnonymousFallback — the S-5 counter', () {
    test('writes one queryable row with every field Tyler filters on',
        () async {
      final db = FakeFirebaseFirestore();

      await recordAnonymousFallback(
        stage: AnonFallbackStage.restoreAfterAccountCreation,
        reason: 'remint_permission-denied',
        dealerCode: '01',
        installerCode: '01',
        authUid: 'staff_installer_0101',
        firestore: db,
      );

      final snap = await db.collection(kStaffAuthTelemetryCollection).get();
      expect(snap.docs, hasLength(1));

      final row = snap.docs.first.data();
      // The discriminator the console query filters on.
      expect(row['event_type'], kAnonFallbackEventType);
      expect(row['stage'], 'restore_after_account_creation');
      expect(row['reason'], 'remint_permission-denied');
      expect(row['dealer_code'], '01');
      expect(row['installer_code'], '01');
      expect(row['auth_uid'], 'staff_installer_0101');
      // Version stamp is what separates adopted builds from stale ones.
      expect(row['app_version'], kStaffAuthTelemetryAppVersion);
      expect(row['device_id'], isNotEmpty);
      expect(row.containsKey('created_at'), isTrue);
    });

    test('device id is stable across records (one device, not many)', () async {
      final db = FakeFirebaseFirestore();

      await recordAnonymousFallback(
        stage: AnonFallbackStage.preflightRefresh,
        reason: 'first',
        firestore: db,
      );
      await recordAnonymousFallback(
        stage: AnonFallbackStage.preflightRefresh,
        reason: 'second',
        firestore: db,
      );

      final snap = await db.collection(kStaffAuthTelemetryCollection).get();
      expect(snap.docs, hasLength(2));
      final ids = snap.docs.map((d) => d.data()['device_id']).toSet();
      expect(ids, hasLength(1),
          reason: 'a churning device id would inflate the fleet count');
    });

    test('the preflight stage records its own wire value', () async {
      final db = FakeFirebaseFirestore();
      await recordAnonymousFallback(
        stage: AnonFallbackStage.preflightRefresh,
        reason: 'refresh_failed',
        firestore: db,
      );
      final snap = await db.collection(kStaffAuthTelemetryCollection).get();
      expect(snap.docs.first.data()['stage'], 'preflight_refresh');
    });

    test('an unbounded reason string is truncated, not rejected', () async {
      final db = FakeFirebaseFirestore();
      await recordAnonymousFallback(
        stage: AnonFallbackStage.preflightRefresh,
        reason: 'x' * 5000,
        firestore: db,
      );
      final snap = await db.collection(kStaffAuthTelemetryCollection).get();
      expect((snap.docs.first.data()['reason'] as String).length, 300);
    });

    test('missing optional context still produces a countable row', () async {
      // A fallback with no session at all must still be observable — that is
      // the case S-5 most needs to see.
      final db = FakeFirebaseFirestore();
      await recordAnonymousFallback(
        stage: AnonFallbackStage.restoreAfterAccountCreation,
        reason: 'no_session',
        firestore: db,
      );
      final snap = await db.collection(kStaffAuthTelemetryCollection).get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.first.data()['dealer_code'], '');
      expect(snap.docs.first.data()['event_type'], kAnonFallbackEventType);
    });

    test('TELEMETRY IS NOT LOAD-BEARING: a failing sink never throws',
        () async {
      // Simulates the sink being unavailable (offline / rules denial). The
      // install must be completely unaffected.
      SharedPreferences.setMockInitialValues({});
      await expectLater(
        recordAnonymousFallback(
          stage: AnonFallbackStage.preflightRefresh,
          reason: 'sink down',
          firestore: _ExplodingFirestore(),
        ),
        completes,
      );
    });
  });
}

/// Firestore stand-in whose every access throws, proving the recorder swallows.
class _ExplodingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw StateError('sink unavailable');
}
