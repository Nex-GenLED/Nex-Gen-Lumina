import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';

/// UID of the customer account an installer is currently accessing via the
/// "Existing Customer" search flow (null when not in installer-impersonation
/// mode).
///
/// When non-null, [effectiveUserUidProvider] resolves to this value instead
/// of the actual signed-in installer's UID, redirecting all customer-data
/// providers (controllers, schedules, favorites, brand profile) at the
/// customer's `/users/{uid}` documents.
///
/// Cleared by tapping "Exit" on [InstallerModeBanner] or by restarting the
/// app. The Firebase Auth identity is unchanged — only the UID used for
/// data reads is overridden, so the installer's own claims (`role`,
/// `dealerCode`) still gate writes via firestore.rules.
final installerAccessingCustomerProvider = StateProvider<String?>((ref) => null);

/// Display label shown in the installer-mode banner (typically the
/// customer's display_name from `/users/{uid}`). Loaded by the existing-
/// customer search screen at the moment the installer taps a result, so the
/// banner doesn't have to do a redundant Firestore read.
final installerAccessingCustomerNameProvider =
    StateProvider<String?>((ref) => null);

/// Returns the UID that customer-facing data providers should read from.
/// Falls through this priority:
///
///   1. [installerAccessingCustomerProvider] — when an installer is
///      impersonating a customer via the Existing Customer flow.
///   2. The actual Firebase Auth user UID (from [authStateProvider]).
///
/// Auth-side providers (login, signup, password reset, claim checks) MUST
/// keep using [FirebaseAuth.instance.currentUser]/[authStateProvider]
/// directly — this provider is only for data scopes that should follow the
/// installer's chosen customer.
final effectiveUserUidProvider = Provider<String?>((ref) {
  final installerCustomerUid = ref.watch(installerAccessingCustomerProvider);
  if (installerCustomerUid != null && installerCustomerUid.isNotEmpty) {
    return installerCustomerUid;
  }
  final authUser = ref.watch(authStateProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );
  return authUser?.uid;
});

/// Lightweight customer search hit used by the Existing Customer search UI.
class CustomerSearchHit {
  final String uid;
  final String displayName;
  final String email;
  final String? address;

  const CustomerSearchHit({
    required this.uid,
    required this.displayName,
    required this.email,
    this.address,
  });

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return email.isNotEmpty ? email.substring(0, 1).toUpperCase() : '?';
    }
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Runs three parallel prefix queries against `/users` (display_name, email,
/// address) and returns a deduplicated, name-sorted list of up to 30 hits.
///
/// Firestore prefix queries are case-sensitive; the search only matches
/// values that begin with [query]. Each individual query is capped at 10
/// results.
Future<List<CustomerSearchHit>> searchCustomers(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  final users = FirebaseFirestore.instance.collection('users');
  final end = '$trimmed';

  // Three parallel prefix queries — name, email, address. Each capped at 10.
  final results = await Future.wait([
    users
        .where('display_name', isGreaterThanOrEqualTo: trimmed)
        .where('display_name', isLessThan: end)
        .limit(10)
        .get(),
    users
        .where('email', isGreaterThanOrEqualTo: trimmed)
        .where('email', isLessThan: end)
        .limit(10)
        .get(),
    users
        .where('address', isGreaterThanOrEqualTo: trimmed)
        .where('address', isLessThan: end)
        .limit(10)
        .get(),
  ]);

  final byUid = <String, CustomerSearchHit>{};
  for (final snap in results) {
    for (final doc in snap.docs) {
      if (byUid.containsKey(doc.id)) continue;
      final data = doc.data();
      final profileType = data['profile_type'] as String?;
      // /users only holds residential/commercial customers — staff are in
      // /installers — but defend against future schema drift.
      if (profileType == 'installer' || profileType == 'admin') continue;
      byUid[doc.id] = CustomerSearchHit(
        uid: doc.id,
        displayName: (data['display_name'] as String?) ?? '',
        email: (data['email'] as String?) ?? '',
        address: data['address'] as String?,
      );
    }
  }

  final hits = byUid.values.toList()
    ..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  return hits;
}
