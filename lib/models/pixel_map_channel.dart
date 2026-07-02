import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Design Studio Slice 1 — one channel's slice of the semantic pixel map.
///
/// Persisted at `/users/{uid}/controllers/{controllerId}/pixelMap/{channelId}`
/// (doc id = [channelIndex] as a string). Each doc carries the ordered feature
/// list ([RooflineSegment]-shaped) for a single hardware channel plus the
/// device-truth [sourcePixelCount] (the `WledLedBus.len` captured at map time),
/// versioning, and a staleness flag.
///
/// The app-wide read/write type stays [RooflineConfiguration] (the aggregate);
/// [splitConfigToPixelMapChannels] / [aggregatePixelMapChannelsToConfig] convert
/// between the two so the ~12 existing config consumers are untouched.
class PixelMapChannel {
  /// Firestore doc id of the parent controller.
  final String controllerId;

  /// 0-based hardware channel index (maps to `WledLedBus` index). Doc id.
  final int channelIndex;

  /// This channel's ordered feature list. Every segment's `channelIndex`
  /// equals [channelIndex].
  final List<RooflineSegment> segments;

  /// Device-truth pixel count for this channel at map time — the
  /// `WledLedBus.len` from `deviceChannelsProvider`, never hand-typed.
  /// Staleness = this drifting from the live bus length.
  final int sourcePixelCount;

  /// Bumped on every save so consumers can detect regeneration.
  final int mapVersion;

  /// Who wrote this map: the customer's uid, or `installer:<dealerCode>` for
  /// an installer-authored map (Slice 2).
  final String createdBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Cached staleness hint persisted on the doc. The authoritative signal is
  /// computed live via [isStaleAgainst] against the connected device; this
  /// field lets consumers show a "remap" prompt before a device is reachable.
  final bool isStale;

  /// Home-wide config name, denormalized so each channel doc is self-describing.
  final String? name;

  /// Home photo path, denormalized (same value across a controller's channels).
  final String? photoPath;

  const PixelMapChannel({
    required this.controllerId,
    required this.channelIndex,
    required this.segments,
    required this.sourcePixelCount,
    required this.createdAt,
    required this.updatedAt,
    this.mapVersion = 1,
    this.createdBy = '',
    this.isStale = false,
    this.name,
    this.photoPath,
  });

  /// Sum of this channel's mapped segment pixel counts.
  int get mappedPixelCount =>
      segments.fold(0, (sum, s) => sum + s.pixelCount);

  /// True when [liveCount] (the current `WledLedBus.len`) differs from the
  /// count recorded at map time. A null live count (device unreachable) is
  /// NOT stale — we can't prove drift without device truth.
  bool isStaleAgainst(int? liveCount) =>
      liveCount != null && liveCount != sourcePixelCount;

  PixelMapChannel copyWith({
    String? controllerId,
    int? channelIndex,
    List<RooflineSegment>? segments,
    int? sourcePixelCount,
    int? mapVersion,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isStale,
    String? name,
    String? photoPath,
  }) {
    return PixelMapChannel(
      controllerId: controllerId ?? this.controllerId,
      channelIndex: channelIndex ?? this.channelIndex,
      segments: segments ?? this.segments,
      sourcePixelCount: sourcePixelCount ?? this.sourcePixelCount,
      mapVersion: mapVersion ?? this.mapVersion,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isStale: isStale ?? this.isStale,
      name: name ?? this.name,
      photoPath: photoPath ?? this.photoPath,
    );
  }

  factory PixelMapChannel.fromFirestore(
    String controllerId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return PixelMapChannel.fromJson(controllerId, doc.id, doc.data() ?? {});
  }

  /// [docId] is the channel index as a string; used as a fallback when the
  /// body omits `channel_index`.
  factory PixelMapChannel.fromJson(
    String controllerId,
    String docId,
    Map<String, dynamic> json,
  ) {
    return PixelMapChannel(
      controllerId: controllerId,
      channelIndex:
          json['channel_index'] as int? ?? int.tryParse(docId) ?? 0,
      segments: (json['segments'] as List<dynamic>?)
              ?.map((s) => RooflineSegment.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      sourcePixelCount: json['source_pixel_count'] as int? ?? 0,
      mapVersion: json['map_version'] as int? ?? 1,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isStale: json['is_stale'] as bool? ?? false,
      name: json['name'] as String?,
      photoPath: json['photo_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'channel_index': channelIndex,
      'segments': segments.map((s) => s.toJson()).toList(),
      'source_pixel_count': sourcePixelCount,
      'map_version': mapVersion,
      'created_by': createdBy,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'is_stale': isStale,
      if (name != null) 'name': name,
      if (photoPath != null) 'photo_path': photoPath,
    };
  }

  @override
  String toString() =>
      'PixelMapChannel(ctrl: $controllerId, ch: $channelIndex, '
      'segs: ${segments.length}, source: $sourcePixelCount, '
      'v: $mapVersion, stale: $isStale)';
}

/// Splits an aggregate [config] into one [PixelMapChannel] per channel that has
/// mapped segments. Per-channel `sourcePixelCount` is taken from
/// [sourceCounts] (device-truth `WledLedBus.len`) when provided, else falls
/// back to that channel's mapped segment sum.
///
/// Pure. [now] is injected (Date.now() is unavailable in some contexts and
/// keeps this deterministic for tests).
List<PixelMapChannel> splitConfigToPixelMapChannels(
  RooflineConfiguration config, {
  required String controllerId,
  Map<int, int> sourceCounts = const {},
  String createdBy = '',
  int mapVersion = 1,
  DateTime? now,
  Map<int, bool> staleByChannel = const {},
}) {
  final stamp = now ?? DateTime.now();
  final channels = config.allChannelIndices; // sorted, unique
  return [
    for (final ch in channels)
      PixelMapChannel(
        controllerId: controllerId,
        channelIndex: ch,
        segments: config.segmentsForChannel(ch),
        sourcePixelCount: sourceCounts[ch] ??
            config
                .segmentsForChannel(ch)
                .fold(0, (sum, s) => sum + s.pixelCount),
        mapVersion: mapVersion,
        createdBy: createdBy,
        createdAt: config.createdAt,
        updatedAt: stamp,
        isStale: staleByChannel[ch] ?? false,
        name: config.name,
        photoPath: config.photoPath,
      ),
  ];
}

/// Aggregates per-channel [channels] docs back into a single
/// [RooflineConfiguration] for the ~12 existing config consumers. Segments are
/// concatenated in channel order (then each channel's own segment order).
/// Home-wide `name`/`photoPath` come from the lowest-indexed channel. Returns
/// an empty config (with [controllerId] identity) when [channels] is empty.
RooflineConfiguration aggregatePixelMapChannelsToConfig(
  String controllerId,
  List<PixelMapChannel> channels,
) {
  if (channels.isEmpty) {
    return RooflineConfiguration.empty().copyWith(
      id: controllerId,
      controllerId: controllerId,
    );
  }

  final sorted = [...channels]..sort((a, b) => a.channelIndex.compareTo(b.channelIndex));
  final segments = <RooflineSegment>[];
  for (final ch in sorted) {
    segments.addAll(ch.segments);
  }

  DateTime created = sorted.first.createdAt;
  DateTime updated = sorted.first.updatedAt;
  for (final ch in sorted) {
    if (ch.createdAt.isBefore(created)) created = ch.createdAt;
    if (ch.updatedAt.isAfter(updated)) updated = ch.updatedAt;
  }

  final maxChannel =
      sorted.map((c) => c.channelIndex).fold(0, (a, b) => a > b ? a : b);

  return RooflineConfiguration(
    id: controllerId,
    controllerId: controllerId,
    name: sorted.first.name ?? 'My Roofline',
    segments: segments,
    createdAt: created,
    updatedAt: updated,
    photoPath: sorted.firstWhere((c) => c.photoPath != null,
        orElse: () => sorted.first).photoPath,
    totalChannelCount: maxChannel + 1,
  );
}
