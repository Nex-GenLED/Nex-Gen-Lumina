// lib/features/wled/pattern_apply_gate.dart
//
// The channel gate, as a TAP sees it (audit row 1).
//
// Favourites, Explore cards and Recent Patterns each read
// `effectiveChannelIdsProvider` synchronously and, when it was empty, returned
// with only a debugPrint: the customer tapped, nothing happened, nothing was
// said. Away from home that was every tap, and at home it was every tap in
// the first seconds after launch, while the controller's channels were still
// being read.
//
// Now a tap waits for a channel source that is still answering, and when the
// gate is really closed it puts `applyBlockedReason`'s sentence on the shared
// failure state the dashboard already renders — the same place every other
// failed command is reported.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:nexgen_command/shared/write_result.dart';

/// The effective channels for an apply the customer just tapped, or null
/// after the reason nothing can be sent has been put on screen.
///
/// Takes the [ProviderContainer], not a widget `ref`: the wait can outlive the
/// widget that was tapped.
Future<List<int>?> resolveChannelsForTap(ProviderContainer container) async {
  final ids = await resolveEffectiveChannelIds(container.read);
  if (ids.isNotEmpty) return ids;
  await reportApplyBlocked(container);
  return null;
}

/// Puts the current "why not" on screen (the shared failure state) and returns
/// the blocked result.
Future<WriteResult> reportApplyBlocked(ProviderContainer container) {
  final reason = applyBlockedReason(container.read) ?? kApplyBlockedFallback;
  return container.read(wledStateProvider.notifier).runAndReport(
        Future.value(WriteResult.blocked(reason)),
        onFailure: kApplyBlockedFallback,
      );
}
