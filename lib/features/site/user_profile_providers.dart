import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/models/installation_model.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Exposes UserService via Riverpod
final userServiceProvider = Provider<UserService>((ref) => UserService());

/// Streams the current user's profile document from Firestore.
/// Returns null if not signed in or if document doesn't exist yet.
final currentUserProfileProvider = StreamProvider<UserModel?>((ref) {
  final user = ref.watch(authStateProvider).maybeWhen(data: (u) => u, orElse: () => null);
  if (user == null) return const Stream.empty();
  final svc = ref.watch(userServiceProvider);
  return svc.streamUser(user.uid);
});

/// Loads the Installation document for the current user (if any) and
/// initialises [linkedControllersProvider] and [siteModeProvider] from its
/// `systemConfig`. This runs once per auth session and is a no-op when the
/// user has no `installationId`.
final installationConfigLoaderProvider = FutureProvider<void>((ref) async {
  final profile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (u) => u,
    orElse: () => null,
  );
  final installationId = profile?.installationId;
  if (installationId == null || installationId.isEmpty) return;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('installations')
        .doc(installationId)
        .get();

    if (!doc.exists) return;

    final installation = Installation.fromFirestore(doc);

    // Restore site mode
    ref.read(siteModeProvider.notifier).state = installation.siteMode;

    // Restore linked controllers (Residential mode)
    final config = installation.systemConfig;
    if (config != null && installation.siteMode == SiteMode.residential) {
      final linkedIds = (config['linkedControllerIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toSet();
      if (linkedIds != null && linkedIds.isNotEmpty) {
        final current = ref.read(linkedControllersProvider);
        // Only populate if the set is still empty (avoid overwriting
        // user changes made after login).
        if (current.isEmpty) {
          ref.read(linkedControllersProvider.notifier).setAll(linkedIds);
          debugPrint('installationConfigLoader: restored ${linkedIds.length} linked controller(s)');
        }
      }
    }
  } catch (e) {
    debugPrint('installationConfigLoader: failed to load installation $installationId: $e');
  }
});
