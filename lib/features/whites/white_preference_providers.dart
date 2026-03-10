import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/whites/white_preset_models.dart';

/// Provider for the user's preferred primary white
final preferredWhitePrimaryProvider = Provider<WhitePreset>((ref) {
  final profile = ref.watch(currentUserProfileProvider).valueOrNull;
  if (profile?.preferredWhitePrimary != null) {
    return WhitePreset.fromJson(profile!.preferredWhitePrimary!);
  }
  // Default: Warm White
  return kWhitePresets[0];
});

/// Provider for the user's preferred complement white
final preferredWhiteComplementProvider = Provider<WhitePreset>((ref) {
  final profile = ref.watch(currentUserProfileProvider).valueOrNull;
  if (profile?.preferredWhiteComplement != null) {
    return WhitePreset.fromJson(profile!.preferredWhiteComplement!);
  }
  // Default: Bright White (complement of default Warm White)
  return kWhitePresets[4];
});

/// Save white preferences to Firestore
Future<void> saveWhitePreferences({
  required WhitePreset primary,
  required WhitePreset complement,
  required WidgetRef ref,
}) async {
  final user = ref.read(authStateProvider).value;
  if (user == null) return;

  await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
    'preferred_white_primary': primary.toJson(),
    'preferred_white_complement': complement.toJson(),
    'updated_at': Timestamp.now(),
  });
}

/// Save white preferences using a Ref (for non-widget contexts)
Future<void> saveWhitePreferencesWithRef({
  required WhitePreset primary,
  required WhitePreset complement,
  required Ref ref,
}) async {
  final user = ref.read(authStateProvider).value;
  if (user == null) return;

  await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
    'preferred_white_primary': primary.toJson(),
    'preferred_white_complement': complement.toJson(),
    'updated_at': Timestamp.now(),
  });
}
