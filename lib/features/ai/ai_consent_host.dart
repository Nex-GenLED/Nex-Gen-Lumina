import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/ai/ai_consent.dart';
import 'package:nexgen_command/features/ai/ai_consent_sheet.dart';

/// Shown when a grant could not be saved. The request is not sent.
const String kAiConsentSaveFailed =
    "Couldn't turn on Lumina AI. Check your connection and try again.";

/// Shown when switching off could not be saved to the account. Lumina AI is
/// still off on this phone.
const String kAiConsentRevokeNotSaved =
    "Lumina AI is off on this phone. We couldn't save that to your account "
    'yet, so it stays off here until you turn it back on.';

/// Binds [AiConsentGate] to the signed-in app shell. It mirrors the
/// account's stored decision and registers the consent sheet as the
/// prompter. Returns the teardown. MainScaffold calls it once.
VoidCallback bindAiConsentGate(WidgetRef ref) {
  void sync() => AiConsentGate.syncFromStore(
        ref.read(authStateProvider).valueOrNull?.uid,
        ref.read(aiConsentProvider).valueOrNull,
      );
  final consentSub =
      ref.listenManual(aiConsentProvider, (_, __) => sync(), fireImmediately: true);
  final authSub = ref.listenManual(authStateProvider, (_, __) => sync());
  Future<bool> prompter() => promptForAiConsent(ref);
  AiConsentGate.registerPrompter(prompter);
  return () {
    consentSub.close();
    authSub.close();
    AiConsentGate.unregisterPrompter(prompter);
  };
}

/// Shows the sheet and saves the answer. True only when a grant was SAVED.
///
/// Fails closed: no screen to show it on, signed out, Not now, dismissed, or
/// a grant whose write throws (offline, rules, a missing user doc) all
/// return false, and the caller sends nothing.
Future<bool> promptForAiConsent(WidgetRef ref, {BuildContext? context}) async {
  final ctx = context ?? AppRouter.rootNavigatorKey.currentContext;
  final uid = ref.read(authStateProvider).valueOrNull?.uid;
  if (ctx == null || uid == null) return false;

  final answer = await showAiConsentSheet(ctx);
  final store = ref.read(aiConsentStoreProvider);

  if (answer != true) {
    if (answer == false) {
      try {
        await store.write(uid, AiConsentStatus.declined);
      } catch (e) {
        debugPrint('AI consent: decline not saved: $e');
      }
    }
    return false;
  }

  try {
    await store.write(uid, AiConsentStatus.granted);
  } catch (e) {
    debugPrint('AI consent: grant not saved, nothing sent: $e');
    AppRouter.scaffoldMessengerKey.currentState
        ?.showSnackBar(const SnackBar(content: Text(kAiConsentSaveFailed)));
    return false;
  }
  AiConsentGate.markGranted();
  return true;
}

/// Switches Lumina AI off for this account. It takes effect on this phone at
/// once, even when the save fails. Returns whether the save landed.
Future<bool> revokeAiConsent(WidgetRef ref) async {
  AiConsentGate.markRevoked();
  final uid = ref.read(authStateProvider).valueOrNull?.uid;
  if (uid == null) return false;
  try {
    await ref.read(aiConsentStoreProvider).write(uid, AiConsentStatus.revoked);
    return true;
  } catch (e) {
    debugPrint('AI consent: revoke not saved (still off on this phone): $e');
    return false;
  }
}
