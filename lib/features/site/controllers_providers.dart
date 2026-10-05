import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/connection_method.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/site_models.dart';

/// The Firestore [controllersStreamProvider] reads. Overridden in tests so
/// the real reader can be driven against a fake store.
final controllersFirestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

/// Streams the current user's controllers collection. Reads from
/// [effectiveUserUidProvider] so installer impersonation (Existing
/// Customer flow) transparently scopes the stream to the customer's UID.
final controllersStreamProvider = StreamProvider<List<ControllerInfo>>((ref) {
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null) {
    debugPrint('controllersStreamProvider: No user logged in');
    return const Stream.empty();
  }

  debugPrint('controllersStreamProvider: Listening to controllers for user $uid');

  // Don't use orderBy to avoid composite index requirement - we'll sort in memory
  final col = ref
      .watch(controllersFirestoreProvider)
      .collection('users')
      .doc(uid)
      .collection('controllers');

  return col.snapshots().map((snap) {
    debugPrint('controllersStreamProvider: Received ${snap.docs.length} controllers from Firestore');

    final controllers = snap.docs.map((d) {
      final data = d.data();
      final createdTs = data['createdAt'];
      final updatedTs = data['updatedAt'];

      return ControllerInfo(
        id: d.id,
        ip: (data['ip'] ?? '') as String,
        name: data['name'] as String?,
        serial: data['serial'] as String?,
        ssid: data['ssid'] as String?,
        wifiConfigured: data['wifiConfigured'] as bool?,
        connectionMethod: connectionMethodFromJson(data['connectionMethod']),
        createdAt: createdTs is Timestamp ? createdTs.toDate() : null,
        updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : null,
      );
    }).toList();

    // Sort by createdAt in memory (newest first), putting nulls at the end
    controllers.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });

    return controllers;
  });
});

/// Deletes a controller document by id.
///
/// Scoped to [effectiveUserUidProvider], NOT `FirebaseAuth.currentUser` (#96).
/// An installer in the Existing Customer flow is shown the customer's
/// controllers by [controllersStreamProvider]; a delete keyed on the installer's
/// own uid would look for that doc id in the installer's subcollection, where it
/// does not exist — and Firestore deletes are idempotent, so it would return
/// `true` having deleted nothing. Read at provider-build time (not inside the
/// closure) so consumers rebuild when the impersonation target changes, matching
/// [controllersStreamProvider].
///
/// #118 — deleting the ACTIVE controller also lets go of it: the record id is
/// added to [deletedControllerIdsProvider], which the controller selection
/// drops at once, choosing again from the records that remain (instead of the
/// app holding an address that belongs to no record — no identity check, no
/// relay).
final deleteControllerProvider = Provider<Future<bool> Function(String)>((ref) {
  final uid = ref.watch(effectiveUserUidProvider);
  final db = ref.watch(controllersFirestoreProvider);
  return (String id) async {
    if (uid == null || uid.isEmpty) return false;
    // Captured before the await.
    final deleted = ref.read(deletedControllerIdsProvider.notifier);
    try {
      await db.collection('users').doc(uid).collection('controllers').doc(id).delete();
      // The set is per account; after an account change mid-delete it is gone.
      if (deleted.mounted) deleted.state = {...deleted.state, id};
      return true;
    } catch (e) {
      debugPrint('Delete controller failed: $e');
      return false;
    }
  };
});

/// #118 — record ids deleted from this phone in this session, per account. The
/// controller selection skips them, so a controller list that has not yet
/// caught up with the delete cannot hand the deleted record straight back.
final deletedControllerIdsProvider = StateProvider<Set<String>>((ref) {
  ref.watch(effectiveUserUidProvider);
  return const <String>{};
});

/// Renames a controller in Firestore.
///
/// Scoped to [effectiveUserUidProvider] for the same reason as
/// [deleteControllerProvider] (#96) — with one difference in failure mode: an
/// `update()` on a missing document THROWS rather than no-opping, so the
/// pre-fix rename surfaced as a caught "Rename controller failed" instead of a
/// false success.
final renameControllerProvider = Provider<Future<bool> Function(String, String)>((ref) {
  final uid = ref.watch(effectiveUserUidProvider);
  return (String id, String newName) async {
    if (uid == null || uid.isEmpty) return false;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('controllers')
          .doc(id)
          .update({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Controller renamed to: $newName');
      return true;
    } catch (e) {
      debugPrint('Rename controller failed: $e');
      return false;
    }
  };
});

/// Arms the controller selection for the running app. Watched by MainScaffold.
///
/// #118 — this used to copy the newest record's address into
/// selectedDeviceIpProvider, and only while the selection was EMPTY: a stale
/// address (another account's, a record's old one, a deleted record's) was
/// never revisited, and a newest record without an address selected nothing.
/// While the shell is up the selection is now chosen by
/// [ControllerSelectionNotifier] — the saved choice, the only record, the most
/// recently connected one, or the customer's answer when two or more answer —
/// and chosen again on every change to the account or its records.
///
/// Returns true once armed.
final autoConnectControllerProvider = Provider<bool>((ref) {
  final selection = ref.watch(controllerSelectionProvider.notifier);
  // Not during this build: arming may change the selection at once.
  Future.microtask(selection.enableAutoSelect);
  return true;
});
