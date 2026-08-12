// lib/features/wled/controller_facts_publisher.dart
//
// The seam the defaults healer publishes through.
//
// Two reasons this is an injected object rather than two direct calls:
//
//   1. ONE WRITE. Participation and base boundaries land on a single document.
//      Assembling both families here means a connect costs ONE
//      `set(merge: true)`, not two — and when both families dedup, ZERO.
//
//   2. The healer stays testable without Firestore. `ControllerDefaultsHealer`
//      is a pure-ish orchestrator over a fake repo; giving it a Firestore
//      dependency would have made every existing heal test carry a fake
//      Firestore it does not care about.

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';

/// Source tag written to `*_source` for a publish that came from the
/// on-connect defaults healer.
const String kHealerPublishSource = 'healer';

/// The participation half of a publish, **resolved by the caller**.
///
/// Both fields come from providers the healer deliberately does not hold (see
/// `ControllerDefaultsHealer.participationInputs`). They travel together
/// because the resolved set is only meaningful against the device shape it was
/// computed from — pairing them in one object makes it impossible to publish
/// one without the other.
@immutable
class ParticipationInput {
  /// `resolveParticipatingChannels`' output.
  final List<int> resolved;

  /// The hardware BUS list it was resolved against. Never empty — a caller
  /// that cannot determine the shape returns null instead of an empty list,
  /// because "we do not know the device" and "the device has no channels" must
  /// not collapse (see `participationShapeIsKnown`).
  final List<int> deviceChannelIds;

  const ParticipationInput({
    required this.resolved,
    required this.deviceChannelIds,
  });

  @override
  String toString() =>
      'ParticipationInput($resolved of $deviceChannelIds)';
}

/// Why the participation family did or did not reach the write.
///
/// **This enum exists because the silence was its own defect.** The first cut
/// abstained from publishing participation on every single connect and left no
/// trace anywhere — no log line, no field, no report entry — so the feature was
/// inert in production and it took a bench run to notice. Every outcome below
/// is now logged on exactly one line.
enum ParticipationDisposition {
  /// Handed to the writer. It may still have deduped — see [FactsPublishOutcome.wrote].
  offered,

  /// The caller resolved the shape and it was EMPTY. Publishing a resolution
  /// against an unknown bus list would record `[]`, which the server reads as
  /// a usable "light nothing".
  shapeUnknown,

  /// The inputs did not resolve inside the bound. Base boundaries publish
  /// alone; the next connect retries.
  inputsTimedOut,

  /// Resolving the inputs threw.
  inputsFailed,

  /// No caller supplied inputs at all (demo, or a caller that does not publish
  /// participation).
  inputsAbsent,
}

/// What a dispatched publish actually did. Attached to
/// `ControllerHealReport.factsPublish` so the outcome is observable rather than
/// inferred, and awaited by tests instead of pumping the event queue.
@immutable
class FactsPublishOutcome {
  final ParticipationDisposition participation;

  /// True when the caller had base-boundary rows to offer (i.e. the timer table
  /// was readable). False means the cfg read could not see it.
  final bool baseBoundariesOffered;

  /// True when a document write actually went out. False means every offered
  /// family deduped, or the write was refused/failed — both normal.
  final bool wrote;

  const FactsPublishOutcome({
    required this.participation,
    required this.baseBoundariesOffered,
    required this.wrote,
  });

  /// One line, always logged. Deliberately states the negative cases as
  /// loudly as the positive one.
  String describe() {
    final p = switch (participation) {
      ParticipationDisposition.offered => 'participation=offered',
      ParticipationDisposition.shapeUnknown =>
        'participation=SKIPPED(bus list resolved empty — shape unknown)',
      ParticipationDisposition.inputsTimedOut =>
        'participation=SKIPPED(inputs timed out after '
            '${kParticipationInputTimeout.inSeconds}s)',
      ParticipationDisposition.inputsFailed =>
        'participation=SKIPPED(input resolution threw)',
      ParticipationDisposition.inputsAbsent =>
        'participation=SKIPPED(no inputs supplied)',
    };
    final b = baseBoundariesOffered
        ? 'base_boundaries=offered'
        : 'base_boundaries=SKIPPED(timer table unreadable)';
    return '$p $b wrote=$wrote';
  }

  @override
  String toString() => describe();
}

/// How long a publish waits for the participation inputs before giving up and
/// publishing base boundaries alone.
///
/// **Why 20 seconds, and why it must exceed 15.** The inputs come from
/// `deviceHardwareConfigProvider`, a FutureProvider that performs its own
/// `GET /json/cfg` through `WledService` — whose HTTP timeouts are **15
/// seconds**, deliberately (the "System Offline" false-alarm fix mandates 15s;
/// shorter values were the original defect). A bound below 15s would therefore
/// abandon a fetch that is still legitimately in flight, reintroducing the same
/// too-aggressive-timeout mistake one layer up. 20s = that full allowance plus
/// 5s for provider machinery and the roofline stream's first emission.
///
/// **What happens on expiry, and it is NOT silent:** base boundaries publish
/// alone — today's behaviour, not a regression — and the run logs
/// `participation=SKIPPED(inputs timed out …)`. Nothing is written for
/// participation, so the next connect retries with a cold memo.
///
/// **The cost of waiting**, stated honestly: the publish is unawaited, so no
/// heal and no UI is delayed. But because both families ride one write, base
/// boundaries also wait for this bound in the failure case. In practice the bus
/// list resolves in well under a second — its fetch starts at t=0 alongside the
/// healer's own — so the wait is the pathological path only. The residual risk
/// is a session that ends inside that window publishing nothing at all, which
/// is already a session where the controller is barely reachable.
const Duration kParticipationInputTimeout = Duration(seconds: 20);

/// Publishes the device-only facts a LAN client can see and the server cannot.
abstract class ControllerFactsPublisher {
  const ControllerFactsPublisher();

  /// Publish both families in one write.
  ///
  /// Each family self-gates: [participation] null contributes nothing;
  /// [baseBoundaries] null (timer table unreadable) contributes nothing; either
  /// may also dedup against its process-lifetime memo. When both abstain there
  /// is no write.
  ///
  /// Returns whether a document write actually went out. Never throws.
  Future<bool> publishDeviceFacts({
    required String? controllerId,
    required ParticipationInput? participation,
    required List<BaseBoundaryRow>? baseBoundaries,
    required int slotsRead,
    required String source,
  });
}

/// The real implementation — one merge-set on
/// `users/{uid}/controllers/{controllerId}`.
class FirestoreControllerFactsPublisher extends ControllerFactsPublisher {
  const FirestoreControllerFactsPublisher();

  @override
  Future<bool> publishDeviceFacts({
    required String? controllerId,
    required ParticipationInput? participation,
    required List<BaseBoundaryRow>? baseBoundaries,
    required int slotsRead,
    required String source,
  }) async {
    final id = controllerId;
    if (id == null || id.isEmpty) return false;
    return writeControllerFacts(
      controllerId: id,
      families: [
        prepareParticipationFacts(
          controllerId: id,
          resolved: participation?.resolved,
          deviceChannelIds:
              participation?.deviceChannelIds ?? const <int>[],
          source: source,
        ),
        prepareBaseBoundaryFacts(
          controllerId: id,
          rows: baseBoundaries,
          slotsRead: slotsRead,
          source: source,
        ),
      ],
      label: source,
    );
  }
}
