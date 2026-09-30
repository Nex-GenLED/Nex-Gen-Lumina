// lib/features/design/design_studio_feature_flag.dart
//
// +110 E2 follow-up D1 — the Design Studio segmentation gate is SOFT by
// default and hard only when a fleet flag says so (or the install's own map
// says so; see `design_studio_gate.dart`).
//
// The flag lives at config/design_studio.requireSegmentation and is streamed
// exactly like config/calendar_leases.liveWritesEnabled
// (calendar_lease_feature_flag.dart): a missing document, a missing field, a
// non-boolean field or a Firestore error all read as FALSE, and a flip in the
// console reaches running apps without a restart.
//
// Deliberately NO bootstrap. The document is created by hand when the owner
// decides to flip the fleet; the app never writes `config/`.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firestore document path holding the flag.
const String kDesignStudioFlagCollection = 'config';
const String kDesignStudioFlagDocId = 'design_studio';

/// The field. `true` = every install is hard-gated on a segmented roofline.
const String kDesignStudioRequireSegmentationField = 'requireSegmentation';

/// Pure: the flag's value from a document's data. Anything but a literal
/// boolean `true` is `false`.
bool designStudioRequireSegmentationFrom(Map<String, dynamic>? data) {
  if (data == null) return false;
  final raw = data[kDesignStudioRequireSegmentationField];
  return raw is bool && raw;
}

/// Streams config/design_studio.requireSegmentation. Defaults to `false` for
/// every degraded state (missing doc, missing field, non-boolean, error).
///
/// The gate reads it through `.maybeWhen(data: …, orElse: () => false)`, so
/// the loading window is soft too — a customer never meets the hard gate
/// because the flag had not arrived yet.
final designStudioRequireSegmentationProvider =
    StreamProvider<bool>((ref) async* {
  bool? lastEmitted;
  try {
    final docStream = FirebaseFirestore.instance
        .collection(kDesignStudioFlagCollection)
        .doc(kDesignStudioFlagDocId)
        .snapshots();
    await for (final snap in docStream) {
      final value =
          designStudioRequireSegmentationFrom(snap.exists ? snap.data() : null);
      if (value != lastEmitted) {
        debugPrint('DesignStudio: requireSegmentation = $value');
        lastEmitted = value;
      }
      yield value;
    }
  } catch (e) {
    debugPrint('DesignStudio: feature-flag stream error — $e '
        '(defaulting to false)');
    yield false;
  }
});
