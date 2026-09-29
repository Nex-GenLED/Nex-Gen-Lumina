// lib/features/wled/pattern_tweak_sender.dart
//
// Sends an ADJUSTMENT (see pattern_tweak_payload.dart) and says what happened.
//
// Shared by the Home Tune panel and the Explore adjustment sheet, which used
// to each build `applyChannelFilter(...)` + `repo.applyJson(...)` inline, drop
// the result in a `catch → debugPrint`, and return silently when the channel
// gate was empty (audit rows 1, 80).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/pattern_tweak_payload.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:nexgen_command/shared/write_result.dart';

/// What the customer is told when the controller did not take an adjustment.
const String kAdjustmentFailedMessage =
    "Your lights didn't take that change — check your connection and try "
    'again.';

/// Sends [fields] to every effective channel as an adjustment: only those
/// channels, only those fields, never a power change.
///
/// Waits for a channel source that is still being read (the first seconds
/// after launch; the first command away from home). A closed gate comes back
/// as [WriteResult.blocked] carrying `applyBlockedReason`'s sentence; a write
/// the controller refused, or one that threw, as a failure with
/// [kAdjustmentFailedMessage]. Nothing is shown here — wrap the call in
/// `WledNotifier.runAndReport` to put a failure on screen.
Future<WriteResult> sendChannelTweak(
  T Function<T>(ProviderListenable<T> provider) read,
  Map<String, dynamic> fields,
) async {
  final channels = await resolveEffectiveChannelIds(read);
  if (channels.isEmpty) {
    return WriteResult.blocked(applyBlockedReason(read) ?? kApplyBlockedFallback);
  }
  final repo = read(wledRepositoryProvider);
  if (repo == null) {
    return WriteResult.blocked(applyBlockedReason(read) ?? kApplyBlockedFallback);
  }
  final payload = buildChannelTweakPayload(fields, channels);
  // Belt and braces: the builder cannot emit `on`, and this says so loudly in
  // debug if it ever learns to.
  assert(!payloadTouchesPower(payload),
      'an adjustment must never change channel power: $payload');
  try {
    final ok = await repo.applyJson(payload);
    return ok
        ? const WriteResult.success()
        : const WriteResult.failed(
            WriteFailureKind.unreachable,
            message: kAdjustmentFailedMessage,
          );
  } catch (e) {
    debugPrint('sendChannelTweak: write threw — $e');
    return WriteResult.failed(
      WriteFailureKind.error,
      message: kAdjustmentFailedMessage,
      error: e,
    );
  }
}
