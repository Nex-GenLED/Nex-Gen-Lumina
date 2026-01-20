import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nexgen_command/app_providers.dart';
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
