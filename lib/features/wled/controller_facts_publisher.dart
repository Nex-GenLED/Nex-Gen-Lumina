// lib/features/wled/controller_facts_publisher.dart
//
// The seam the defaults healer publishes through.
//
// Two reasons this is an injected object rather than two direct calls:
//
//   1. ONE WRITE. Participation and base boundaries are read from a single
//      /json/cfg fetch and land on a single document. Assembling both families
//      here means a connect costs ONE `set(merge: true)`, not two — and when
//      both families dedup, ZERO.
//
//   2. The healer stays testable without Firestore. `ControllerDefaultsHealer`
//      is a pure-ish orchestrator over a fake repo; giving it a Firestore
//      dependency would have made every existing heal test carry a fake
//      Firestore it does not care about.

import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';

/// Source tag written to `*_source` for a publish that came from the
/// on-connect defaults healer.
const String kHealerPublishSource = 'healer';

/// Publishes the device-only facts a LAN client can see and the server cannot.
abstract class ControllerFactsPublisher {
  const ControllerFactsPublisher();

  /// Publish both families in one write.
  ///
  /// Each family self-gates: [participation] null (no opinion) or resolved
  /// against an unknown device shape contributes nothing; [baseBoundaries]
  /// null (timer table unreadable) contributes nothing; either may also dedup
  /// against its process-lifetime memo. When both abstain there is no write.
  ///
  /// Never throws.
  Future<void> publishDeviceFacts({
    required String? controllerId,
    required List<int>? participation,
    required List<int> deviceChannelIds,
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
  Future<void> publishDeviceFacts({
    required String? controllerId,
    required List<int>? participation,
    required List<int> deviceChannelIds,
    required List<BaseBoundaryRow>? baseBoundaries,
    required int slotsRead,
    required String source,
  }) async {
    final id = controllerId;
    if (id == null || id.isEmpty) return;
    await writeControllerFacts(
      controllerId: id,
      families: [
        prepareParticipationFacts(
          controllerId: id,
          resolved: participation,
          deviceChannelIds: deviceChannelIds,
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
