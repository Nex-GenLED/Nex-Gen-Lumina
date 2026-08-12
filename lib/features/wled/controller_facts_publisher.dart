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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';

/// Source tag written to `*_source` for a publish that came from the
/// on-connect defaults healer.
const String kHealerPublishSource = 'healer';

/// Mirrors the participation disposition onto the controller document so it is
/// observable **off the device**.
///
/// WHY THIS FIELD EXISTS. `ControllerHealReport.factsPublish` is in-process
/// only, and `debugPrint` is nulled under `kReleaseMode` (`main.dart:129`), so
/// on a release build a SKIPPED disposition left **zero external evidence**.
/// Firestore was the only witness and it only ever witnessed success — which is
/// how §7.2d ended up unable to tell "the healer never ran" from "the healer
/// ran and skipped". Those need completely different responses.
///
/// **An ABSENT field means the healer never attempted a publish on this
/// controller.** It never means "attempted and skipped" — every disposition
/// writes, including [ParticipationDisposition.offered].
const String kParticipationDispositionField =
    'participation_publish_disposition';

/// The mirrored label for one disposition — `offered`, or
/// `SKIPPED(<reason>)`.
///
/// **One formatter.** This is both the Firestore field value and the
/// participation clause of [FactsPublishOutcome.describe], so the log line and
/// the document can never disagree about what happened.
String participationDispositionLabel(ParticipationDisposition d) {
  switch (d) {
    case ParticipationDisposition.offered:
      return 'offered';
    case ParticipationDisposition.shapeUnknown:
      return 'SKIPPED(bus list unreadable — shape unknown)';
    case ParticipationDisposition.noBusesConfigured:
      return 'SKIPPED(controller reports no LED outputs)';
    case ParticipationDisposition.inputsTimedOut:
      return 'SKIPPED(inputs timed out after '
          '${kParticipationInputTimeout.inSeconds}s)';
    case ParticipationDisposition.inputsFailed:
      return 'SKIPPED(input resolution threw)';
    case ParticipationDisposition.inputsAbsent:
      return 'SKIPPED(no inputs supplied)';
  }
}

/// Process-lifetime memo of the last disposition mirrored per controller.
///
/// The mirror is deduped for the same reason the facts are: without it, a
/// second connect in one session — which correctly writes NOTHING today —
/// would start costing a document mutation, silently breaking the step-6
/// one-write guarantee. Deduping keeps the counts exactly as they were.
@visibleForTesting
final Map<String, String> publishedDispositionMemo = <String, String>{};

@visibleForTesting
void resetDispositionMemo() => publishedDispositionMemo.clear();

/// This family's contribution to a publish, or [PreparedFacts.none] when the
/// disposition is unchanged from what this process last mirrored.
///
/// Deliberately NOT given the `_publish_count` / `_previous` treatment the two
/// fact families get: this is a status field, not a denormalized value a
/// planner acts on, and its history is already legible from `_at`.
PreparedFacts prepareDispositionFacts({
  required String controllerId,
  required String disposition,
}) {
  if (publishedDispositionMemo[controllerId] == disposition) {
    return PreparedFacts.none;
  }
  final fields = <String, Object?>{
    kParticipationDispositionField: disposition,
    factAtField(kParticipationDispositionField): FieldValue.serverTimestamp(),
  };
  return PreparedFacts(
    fields,
    () => publishedDispositionMemo[controllerId] = disposition,
  );
}

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

  /// The bus list could not be READ — `cfg.hw.led` absent or malformed.
  ///
  /// Since the +73 rewire the bus list comes from the healer's own cfg fetch,
  /// so on a LAN connect whose cfg parsed this should be **unreachable**. It is
  /// deliberately kept: an unreachable disposition that fires anyway is exactly
  /// the signal worth having, and the enum-iteration test forbids adding a
  /// disposition that cannot announce itself.
  shapeUnknown,

  /// The bus list was READ and the controller reports **no LED outputs**.
  ///
  /// Distinct from [shapeUnknown] on purpose. "We could not see the hardware"
  /// and "we saw it and there is nothing wired" are different faults with
  /// different fixes — collapsing them is the null-vs-unknown class that
  /// produced #63, and this enum is the last place that distinction survives
  /// before it reaches a human.
  noBusesConfigured,

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

  /// The participation clause — the SAME string mirrored to Firestore as
  /// [kParticipationDispositionField]. See [participationDispositionLabel].
  String get participationLabel => participationDispositionLabel(participation);

  /// One line, always logged. Deliberately states the negative cases as
  /// loudly as the positive one.
  String describe() {
    final p = 'participation=$participationLabel';
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
  /// may also dedup against its process-lifetime memo. When all three abstain
  /// there is no write.
  ///
  /// [participationDisposition] is the [participationDispositionLabel] for this
  /// attempt, mirrored to the document so a skip is visible off-device. It
  /// rides the SAME `set(merge: true)` when either fact family writes, and
  /// becomes its own single write only when they do not and it has changed —
  /// so it never perturbs the one-write guarantee. Null suppresses the mirror
  /// entirely (no attempt was made).
  ///
  /// Returns whether a document write actually went out. Never throws.
  Future<bool> publishDeviceFacts({
    required String? controllerId,
    required ParticipationInput? participation,
    required List<BaseBoundaryRow>? baseBoundaries,
    required int slotsRead,
    required String source,
    String? participationDisposition,
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
    String? participationDisposition,
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
        // Last, so it merges into whatever write the fact families already
        // justify rather than provoking a second one. writeControllerFacts
        // folds every non-empty family into ONE set(merge: true), and this
        // family is the same never-throws envelope as the rest — a mirror
        // failure cannot fail the publish.
        if (participationDisposition != null)
          prepareDispositionFacts(
            controllerId: id,
            disposition: participationDisposition,
          ),
      ],
      label: source,
    );
  }
}
