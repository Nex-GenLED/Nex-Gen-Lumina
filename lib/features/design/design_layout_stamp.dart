// lib/features/design/design_layout_stamp.dart
//
// Roofline slice 1, item 1 — the LAYOUT STAMP a positional design carries.
//
// A painted (or AI-composed) design is a picture laid over the controller's
// buses: channel-local LED indices per bus id. Until now the design recorded
// only `led_count` per channel and was tied to the ACCOUNT, not to the
// controller or to the bus layout it was painted on
// (ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03 §A.2). Nothing compared the stored
// counts with the live buses at apply time, so a design painted for one
// layout could be sent to another and land on the wrong LEDs.
//
// The stamp is written AT SAVE TIME from device truth only: the live
// `deviceChannelsProvider` (one channel per `hw.led.ins[]` bus, LAN cfg read)
// and the selected controller's record id. It is never derived from the
// pixelMap or from the design's own channels.
//
// Pure Dart: no flutter, no Riverpod, so the fit check (item 2) and its tests
// run without a device or a provider container.

import 'package:nexgen_command/features/wled/device_channel.dart';

/// Firestore field names on `/users/{uid}/designs/{id}`. Additive; the
/// designs rule asserts no field shapes, so no rules change is needed.
const String kDesignControllerIdField = 'controller_id';
const String kDesignBusLengthsField = 'bus_lengths';

/// The controller and bus layout a design was saved against.
class DesignLayoutStamp {
  /// The selected controller's record id at save time. Null when the app had
  /// no selected record (a device being set up, a direct address): the bus
  /// lengths alone still gate the apply.
  final String? controllerId;

  /// LED count per bus, indexed by bus id (= WLED segment id = channel id).
  /// Never empty: a stamp with no buses is no stamp (see [fromChannels]).
  final List<int> busLengths;

  const DesignLayoutStamp({this.controllerId, required this.busLengths});

  int get busCount => busLengths.length;

  /// The stamp for the live channel list, or null when there is nothing to
  /// stamp with (no cfg read: off the LAN, loading, unreadable). A writer
  /// with a null stamp saves the design UNSTAMPED, exactly as before.
  ///
  /// Lengths are placed by channel id so a list that arrives out of order
  /// still stamps bus 0 first; a channel with an id past the end of the
  /// contiguous range leaves zero-length gaps, which is itself a mismatch
  /// against any sane live layout.
  static DesignLayoutStamp? fromChannels(
    List<DeviceChannel> channels, {
    String? controllerId,
  }) {
    if (channels.isEmpty) return null;
    var maxId = -1;
    for (final c in channels) {
      if (c.id > maxId) maxId = c.id;
    }
    if (maxId < 0) return null;
    final lengths = List<int>.filled(maxId + 1, 0);
    for (final c in channels) {
      if (c.id < 0) continue;
      lengths[c.id] = (c.stop - c.start).clamp(0, 1 << 20);
    }
    final id = controllerId?.trim();
    return DesignLayoutStamp(
      controllerId: (id == null || id.isEmpty) ? null : id,
      busLengths: List<int>.unmodifiable(lengths),
    );
  }

  /// Reads the stamp off a design document. Null when the document carries
  /// no usable `bus_lengths` (legacy documents, or a malformed list): such a
  /// design keeps today's behaviour until it is re-saved.
  static DesignLayoutStamp? fromFirestoreData(Map<String, dynamic> data) {
    final raw = data[kDesignBusLengthsField];
    if (raw is! List || raw.isEmpty) return null;
    final lengths = <int>[];
    for (final v in raw) {
      if (v is int && v >= 0) {
        lengths.add(v);
      } else {
        return null;
      }
    }
    final rawId = data[kDesignControllerIdField];
    final id = rawId is String ? rawId.trim() : null;
    return DesignLayoutStamp(
      controllerId: (id == null || id.isEmpty) ? null : id,
      busLengths: List<int>.unmodifiable(lengths),
    );
  }

  /// The two fields as written. Flat ints only: `sanitizeForFirestore`
  /// accepts a flat list, and the native iOS codec objects only to nested
  /// arrays (#84).
  Map<String, dynamic> toFirestoreFields() => {
        if (controllerId != null) kDesignControllerIdField: controllerId,
        kDesignBusLengthsField: List<int>.from(busLengths),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DesignLayoutStamp) return false;
    if (other.controllerId != controllerId) return false;
    if (other.busLengths.length != busLengths.length) return false;
    for (var i = 0; i < busLengths.length; i++) {
      if (other.busLengths[i] != busLengths[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(controllerId, Object.hashAll(busLengths));

  @override
  String toString() => 'DesignLayoutStamp($controllerId, $busLengths)';
}
