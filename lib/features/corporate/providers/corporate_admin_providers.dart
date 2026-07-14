import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/corporate/models/network_announcement.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/models/dealer_code.dart';

// ─────────────────────────────────────────────────────────────────────────
// Dealers — re-uses the same `dealers` collection used by the existing
// admin dashboard. Aliased here so the corporate admin tab imports a
// corporate-namespaced provider.
// ─────────────────────────────────────────────────────────────────────────

/// Streams the full dealers collection ordered by dealer code.
final allDealersProvider = StreamProvider<List<DealerInfo>>((ref) {
  return FirebaseFirestore.instance
      .collection('dealers')
      .orderBy('dealerCode')
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => DealerInfo.fromMap(doc.data())).toList());
});

// ─────────────────────────────────────────────────────────────────────────
// Network announcements
// ─────────────────────────────────────────────────────────────────────────

/// Live stream of announcements stored at
/// `app_config/announcements/items` ordered by `createdAt` desc.
final networkAnnouncementProvider =
    StreamProvider<List<NetworkAnnouncement>>((ref) {
  return FirebaseFirestore.instance
      .collection('app_config')
      .doc('announcements')
      .collection('items')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) {
    return snap.docs.map((doc) {
      final data = doc.data();
      // Ensure id field always reflects the doc id even if absent in the
      // payload (e.g. on freshly created docs).
      return NetworkAnnouncement.fromJson({...data, 'id': doc.id});
    }).toList();
  });
});

// ─────────────────────────────────────────────────────────────────────────
// Network pricing defaults
//
// Stored at app_config/pricing_defaults. Used by DealerPricingService as
// the intermediate fallback BEFORE DealerPricing.defaults().
// ─────────────────────────────────────────────────────────────────────────

/// One-shot read of the network-wide default pricing. Returns null when
/// no document exists yet (caller can render the hardcoded
/// [DealerPricing.defaults] in that case).
final networkPricingDefaultsProvider =
    FutureProvider<DealerPricing?>((ref) async {
  final snap = await FirebaseFirestore.instance
      .collection('app_config')
      .doc('pricing_defaults')
      .get();
  if (!snap.exists) return null;
  final data = snap.data();
  if (data == null) return null;
  return DealerPricing.fromJson(data);
});

// ─────────────────────────────────────────────────────────────────────────
// PIN configuration — read-only "is set?" provider for each role.
//
// IMPORTANT: only checks for presence of `pin_hash`, never reads it.
// Used by the System PINs section to render "Set" / "Not set" labels.
//
// Doc IDs match the existing notifier code:
//   - app_config/master_sales_pin
//   - app_config/master_installer  (NOTE: no `_pin` suffix — matches the
//     existing InstallerModeNotifier code)
//   - app_config/master_corporate_pin
//   - app_config/master_admin       (added 2026-05-05; no `_pin` suffix
//     to match the master_installer convention)
// ─────────────────────────────────────────────────────────────────────────

class PinSlotState {
  final String slotKey;
  final String label;
  final bool isSet;
  const PinSlotState({
    required this.slotKey,
    required this.label,
    required this.isSet,
  });
}

const String kPinDocSales = 'master_sales_pin';
const String kPinDocInstaller = 'master_installer';
const String kPinDocCorporate = 'master_corporate_pin';
const String kPinDocAdmin = 'master_admin';

final pinSlotStatesProvider = FutureProvider<List<PinSlotState>>((ref) async {
  final db = FirebaseFirestore.instance;

  Future<bool> isSet(String docId) async {
    try {
      final snap = await db.collection('app_config').doc(docId).get();
      if (!snap.exists) return false;
      final hash = snap.data()?['pin_hash'] as String?;
      return hash != null && hash.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  return [
    PinSlotState(
      slotKey: kPinDocSales,
      label: 'Master Sales PIN',
      isSet: await isSet(kPinDocSales),
    ),
    PinSlotState(
      slotKey: kPinDocInstaller,
      label: 'Master Installer PIN',
      isSet: await isSet(kPinDocInstaller),
    ),
    PinSlotState(
      slotKey: kPinDocCorporate,
      label: 'Master Corporate PIN',
      isSet: await isSet(kPinDocCorporate),
    ),
    PinSlotState(
      slotKey: kPinDocAdmin,
      label: 'Master Admin PIN',
      isSet: await isSet(kPinDocAdmin),
    ),
  ];
});

// ─────────────────────────────────────────────────────────────────────────
// Mutating service — encapsulates writes for the admin tab so the screen
// stays focused on UI.
// ─────────────────────────────────────────────────────────────────────────

class CorporateAdminService {
  CorporateAdminService(this._db);
  final FirebaseFirestore _db;

  // ── Dealers ──

  /// Find the dealer document by its [dealerCode] field. Returns null if
  /// not found.
  Future<DocumentReference<Map<String, dynamic>>?> _dealerDocByCode(
      String dealerCode) async {
    final q = await _db
        .collection('dealers')
        .where('dealerCode', isEqualTo: dealerCode)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.reference;
  }

  Future<void> setDealerActive(String dealerCode, bool isActive) async {
    final ref = await _dealerDocByCode(dealerCode);
    if (ref == null) {
      throw StateError('Dealer $dealerCode not found');
    }

    // When deactivating, cascade to every installer in the dealer's roster.
    // Without this an offboarded dealer's installers can still authenticate
    // with their PIN and write to /sales_jobs and dealer inventory under the
    // dealer's code — defeating the purpose of the dealer toggle.
    final batch = _db.batch();
    batch.update(ref, {'isActive': isActive});
    if (!isActive) {
      final installers = await _db
          .collection('installers')
          .where('dealerCode', isEqualTo: dealerCode)
          .get();
      for (final doc in installers.docs) {
        batch.update(doc.reference, {'isActive': false});
      }
    }
    await batch.commit();
  }

  Future<void> updateDealer(
    String dealerCode, {
    String? businessName,
    String? contactEmail,
    String? contactPhone,
    String? territory,
  }) async {
    final ref = await _dealerDocByCode(dealerCode);
    if (ref == null) {
      throw StateError('Dealer $dealerCode not found');
    }
    final updates = <String, dynamic>{};
    // Write to BOTH the existing companyName field AND the new
    // businessName field so the existing dealer/installer screens that
    // read companyName keep working unchanged.
    if (businessName != null) {
      updates['companyName'] = businessName;
      updates['businessName'] = businessName;
    }
    if (contactEmail != null) updates['email'] = contactEmail;
    if (contactPhone != null) updates['phone'] = contactPhone;
    if (territory != null) updates['territory'] = territory;
    if (updates.isEmpty) return;
    await ref.update(updates);
  }

  /// Allocates the next free CANONICAL dealer code — the 2-digit form
  /// (`'01'`..`'99'`), per [DealerCode].
  ///
  /// ## Why this changed (C1)
  ///
  /// This used to mint `NXG-DEALER-{STATE}-{###}`. That format is unusable:
  /// the staff PIN system composes `fullPin = dealerCode + installerCode`
  /// (installer_providers.dart:82) and requires exactly 4 digits — client
  /// gate at installer_providers.dart:168, server `PIN_REGEX = /^\d{4,6}$/`
  /// at staffAuth.ts:112. A prefixed dealer could never have an installer
  /// who could sign in, so the only *reachable* Add-Dealer UI could not
  /// produce a functioning dealer. Every consumer expects 2-digit; the live
  /// functional staff data already uses it. See [DealerCode] for the full
  /// evidence.
  ///
  /// [stateCode] is retained as the caller's territory hint — it is stored
  /// on the `territory` field but is deliberately NO LONGER encoded into the
  /// code itself. Territory belongs in a queryable field, not smuggled into
  /// an identifier the PIN parser has to survive.
  ///
  /// ## Allocation
  ///
  /// Scans every existing dealer, collects the codes already in canonical
  /// form, and returns the LOWEST unused one. Deliberately gap-filling:
  /// codes are a scarce 99-wide keyspace, and a deleted dealer's code should
  /// become reusable.
  ///
  /// Non-conforming legacy docs are SKIPPED, not parsed. This matters — the
  /// rival allocator (`AdminService.getNextDealerCode`,
  /// admin_providers.dart:256) does `int.parse` on the highest-sorted
  /// dealerCode and therefore already throws `FormatException` against the
  /// live `NXG-DEALER-MISSOURI-001` doc. This one tolerates that doc.
  ///
  /// [DealerCode.masterReserved] (`'55'`) is never allocated — see that
  /// field's doc for why handing it to a real dealer would expose them to
  /// every master-PIN session in the fleet.
  ///
  /// Throws [StateError] when the 2-digit space is exhausted.
  Future<String> generateDealerCode({String? stateCode}) async {
    final snap = await _db.collection('dealers').get();

    final used = <int>{};
    for (final doc in snap.docs) {
      final code = doc.data()['dealerCode'];
      // Skip anything non-canonical (legacy prefixed docs) rather than
      // int.parse it — parsing is exactly how the rival allocator breaks.
      if (code is String && DealerCode.isValid(code)) {
        used.add(int.parse(code));
      }
    }
    used.add(int.parse(DealerCode.masterReserved));

    for (var i = 1; i <= DealerCode.maxCode; i++) {
      if (!used.contains(i)) return i.toString().padLeft(2, '0');
    }
    throw StateError(
      'No dealer code available: the 2-digit space (01-99, minus the '
      'reserved master code ${DealerCode.masterReserved}) is exhausted.',
    );
  }

  /// Creates a dealer with a freshly-allocated canonical code.
  ///
  /// The code is [DealerCode.validate]d before the write, so a
  /// non-conforming code can never reach Firestore through this path even if
  /// [generateDealerCode] is later changed or overridden.
  Future<void> createDealer({
    required String businessName,
    required String contactEmail,
    required String contactPhone,
    String? territory,
  }) async {
    final code = DealerCode.validate(
      await generateDealerCode(stateCode: territory),
      context: 'CorporateAdminService.createDealer',
    );
    await _db.collection('dealers').doc(code).set({
      'dealerCode': code,
      'name': businessName,
      'companyName': businessName,
      'businessName': businessName,
      'email': contactEmail,
      'phone': contactPhone,
      if (territory != null && territory.isNotEmpty) 'territory': territory,
      'isActive': true,
      'registeredAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Pricing defaults ──

  Future<void> savePricingDefaults(DealerPricing pricing) async {
    await _db
        .collection('app_config')
        .doc('pricing_defaults')
        .set(pricing.toJson());
  }

  // ── Announcements ──

  Future<void> publishAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required String createdByUid,
  }) async {
    final ref = _db
        .collection('app_config')
        .doc('announcements')
        .collection('items')
        .doc();
    await ref.set({
      'id': ref.id,
      'title': title,
      'body': body,
      'audience': audience.name,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': createdByUid,
      'isActive': true,
    });
  }

  Future<void> archiveAnnouncement(String id) async {
    await _db
        .collection('app_config')
        .doc('announcements')
        .collection('items')
        .doc(id)
        .update({'isActive': false});
  }

  // ── PINs ──

  /// Persists a new PIN to the named app_config doc. Hashes with sha256
  /// before writing — never stores raw PINs. Returns true on success.
  Future<bool> setPin({
    required String slotKey,
    required String newPin,
  }) async {
    if (newPin.length != 4) return false;
    final hash = sha256.convert(utf8.encode(newPin)).toString();
    await _db.collection('app_config').doc(slotKey).set(
      {'pin_hash': hash, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    return true;
  }

  /// Verify [enteredPin] against the stored hash for [slotKey]. Used to
  /// guard PIN-change actions before allowing the new value to be set.
  Future<bool> verifyPin({
    required String slotKey,
    required String enteredPin,
  }) async {
    if (enteredPin.length != 4) return false;
    try {
      final snap =
          await _db.collection('app_config').doc(slotKey).get();
      if (!snap.exists) return false;
      final stored = snap.data()?['pin_hash'] as String?;
      if (stored == null || stored.isEmpty) return false;
      final entered = sha256.convert(utf8.encode(enteredPin)).toString();
      return stored == entered;
    } catch (_) {
      return false;
    }
  }
}

final corporateAdminServiceProvider = Provider<CorporateAdminService>(
  (ref) => CorporateAdminService(FirebaseFirestore.instance),
);
