import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_game_day_autopilot.dart';
import '../neighborhood_providers.dart';
import '../services/group_autopilot_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SERVICE PROVIDER
// ═════════════════════════════════════════════════════════════════════════════

final groupAutopilotServiceProvider = Provider<GroupAutopilotService>((ref) {
  return GroupAutopilotService();
});

// ═════════════════════════════════════════════════════════════════════════════
// GROUP AUTOPILOT CONFIG (real-time stream)
// ═════════════════════════════════════════════════════════════════════════════

/// Streams the group autopilot config for the currently active neighborhood.
/// Returns null if no group is selected or no autopilot is configured.
final groupAutopilotConfigProvider =
    StreamProvider<GroupGameDayAutopilot?>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return Stream.value(null);

  final service = ref.watch(groupAutopilotServiceProvider);
  return service.watchGroupAutopilot(groupId);
});

// ═════════════════════════════════════════════════════════════════════════════
// MEMBER OPT-IN STATUS
// ═════════════════════════════════════════════════════════════════════════════

/// Whether the current user is opted in to the active group's autopilot.
/// Defaults to true (new members are opted in by default).
final groupAutopilotOptInProvider = FutureProvider<bool>((ref) async {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return true;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return true;

  final service = ref.watch(groupAutopilotServiceProvider);
  return service.getMemberOptIn(groupId, uid);
});

/// Opt-in status for a specific member in the active group.
/// Used by the host's Sync Control Center to show per-member status.
final memberAutopilotOptInProvider =
    FutureProvider.family<bool, String>((ref, userId) async {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return true;

  final service = ref.watch(groupAutopilotServiceProvider);
  return service.getMemberOptIn(groupId, userId);
});

// ═════════════════════════════════════════════════════════════════════════════
// CONVENIENCE: Is current user the host?
// ═════════════════════════════════════════════════════════════════════════════

/// Whether the current user is the host of the active group autopilot.
final isGroupAutopilotHostProvider = Provider<bool>((ref) {
  final config = ref.watch(groupAutopilotConfigProvider).valueOrNull;
  if (config == null) return false;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  return uid != null && config.hostUserId == uid;
});

// ═════════════════════════════════════════════════════════════════════════════
// CONVENIENCE: Active member count
// ═════════════════════════════════════════════════════════════════════════════

/// Number of members currently opted in to the group autopilot.
final groupAutopilotMemberCountProvider = Provider<int>((ref) {
  final config = ref.watch(groupAutopilotConfigProvider).valueOrNull;
  return config?.optedInCount ?? 0;
});
