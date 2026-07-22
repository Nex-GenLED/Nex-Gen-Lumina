import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/sales/models/dealer_messaging_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DealerMessagingConfigService
//
// CRUD against the per-dealer messaging configuration document.
//
// Firestore path: dealers/{dealerCode}/config/messaging
//
// Mirrors the shape of DealerPricingService — same `dealers/{code}/...`
// nested-doc convention, same defaults-on-missing fallback, same flat
// service-class style. The streaming version exists so the dealer
// dashboard's Messaging tab can react to live config changes (and so
// the screen handles the "no config doc yet" case naturally — the
// stream emits defaults until the dealer first saves).
// ─────────────────────────────────────────────────────────────────────────────

class DealerMessagingConfigService {
  final FirebaseFirestore _db;

  DealerMessagingConfigService(this._db);

  DocumentReference<Map<String, dynamic>> _configDoc(String dealerCode) =>
      _db
          .collection('dealers')
          .doc(dealerCode)
          .collection('config')
          .doc('messaging');

  /// Live stream of the dealer's messaging config. Emits
  /// [DealerMessagingConfig.defaults] when the document doesn't exist
  /// or fails to deserialize, so the screen always has something to
  /// render and the dealer can save fresh defaults via the screen.
  Stream<DealerMessagingConfig> watchConfig(String dealerCode) {
    if (dealerCode.isEmpty) {
      return Stream.value(DealerMessagingConfig.defaults(dealerCode));
    }
    return _configDoc(dealerCode).snapshots().map((snap) {
      if (!snap.exists) {
        return DealerMessagingConfig.defaults(dealerCode);
      }
      final data = snap.data();
      if (data == null) {
        return DealerMessagingConfig.defaults(dealerCode);
      }
      try {
        return DealerMessagingConfig.fromJson({
          ...data,
          // Ensure dealerCode is always present in the deserialized
          // config — the Firestore doc may not store it (since it's
          // implicit in the path) and we want copyWith chains and
          // round-trips to keep it.
          'dealerCode': dealerCode,
        });
      } catch (_) {
        return DealerMessagingConfig.defaults(dealerCode);
      }
    });
  }

  /// Persist the dealer's messaging config. Always uses
  /// `set(..., merge: true)` so partial saves don't wipe fields the
  /// caller didn't include. Always overwrites `updatedAt` with the
  /// server timestamp.
  Future<void> saveConfig(DealerMessagingConfig config) async {
    if (config.dealerCode.isEmpty) {
      throw ArgumentError('saveConfig: dealerCode must not be empty');
    }
    final json = config.toJson();
    // Replace the local updatedAt (if any) with the server timestamp so
    // the source of truth for last-updated is consistent across all
    // dealers regardless of device clock skew.
    json['updatedAt'] = FieldValue.serverTimestamp();
    await _configDoc(config.dealerCode).set(json, SetOptions(merge: true));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final dealerMessagingConfigServiceProvider =
    Provider<DealerMessagingConfigService>(
  (ref) => DealerMessagingConfigService(FirebaseFirestore.instance),
);
