import 'dart:convert';

import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';

/// The [ScheduleItem.presetKind] of a painted design scheduled nightly: the
/// sync writes a WLED API-command preset (`o:true`) for it. The one value
/// this field can take today; absent means the ordinary captured-state
/// preset. Defined here (pure Dart) so the model, the sync, the picker and
/// the bench harness all read the same string.
const String kSchedulePresetKindApi = 'api';

/// Represents a single automation schedule for lights/patterns.
///
/// Each schedule has an "on" time when the pattern/action starts
/// and an optional "off" time when the lights turn off.
///
/// The [wledPayload] field stores the actual WLED JSON state to apply
/// (effects, colors, brightness, etc.). This is saved as a preset on the
/// device so that WLED timers can reliably trigger the intended state.
class ScheduleItem {
  final String id;
  /// Display label for ON time, e.g., "7:00 PM" or "Sunset".
  final String timeLabel;
  /// Display label for OFF time, e.g., "11:00 PM" or "Sunrise". Null if no off time.
  final String? offTimeLabel;
  /// Abbreviated repeat days, e.g., ["Mon","Wed","Fri"].
  final List<String> repeatDays;
  /// Action label, e.g., "Pattern: Candy Cane" or "Turn Off".
  final String actionLabel;
  final bool enabled;

  /// The actual WLED JSON payload to apply when this schedule triggers.
  /// Contains effect IDs, colors, brightness, segment configuration, etc.
  /// When null, the schedule will use legacy preset-based behavior.
  final Map<String, dynamic>? wledPayload;

  /// The preset ID assigned to this schedule (10-250).
  /// WLED timers reference this preset ID to load the saved state.
  /// Assigned automatically during sync if not set.
  final int? presetId;

  /// When true, the schedule will pick a random audio-reactive effect
  /// from the controller's SR WLED usermod instead of using a fixed pattern.
  /// Requires a controller with onboard microphone support (NGL-CTRL-P1).
  final bool? useAudioReactive;

  /// Soft-eviction marker. When non-null and in the future, this
  /// schedule is treated as if it were `enabled: false` by
  /// [ScheduleSyncService.buildCfgPayload] and the lease manager's
  /// slot-demand calculation. Used by Item #61 Workstream B's
  /// eviction picker to free a WLED timer slot for an incoming
  /// CalendarEntry lease without removing the recurring schedule
  /// outright. After the timestamp passes the field is cleared by
  /// the lease manager's periodic sweep.
  final DateTime? disabledUntil;

  /// Provenance marker for compound Lumina prompts (Item #51 Prompts 3-4).
  /// When a single user prompt decomposes into N schedules ("red until
  /// Dec 25, then warm white through New Year's"), every resulting
  /// ScheduleItem carries the same opaque id so the UI can later group
  /// siblings, offer bulk-undo, or atomically roll back the set.
  ///
  /// Null for any schedule not authored by the compound dispatcher —
  /// manual entries, autopilot fan-outs, and pre-compound AI singletons
  /// all leave this unset. Additive field; existing Firestore records
  /// deserialize to null without migration.
  final String? sourcePromptId;

  /// Monotonic per-user insertion-order key (A-5-prime). The subcollection
  /// backend orders its stream/fetch by this, so its read order reproduces the
  /// legacy `schedules` array's insertion order (array reads are already
  /// insertion-ordered). Assigned on create as (max sortKey over the user's
  /// current schedules) + 1; the array→subcollection backfill stamps it = the
  /// array index. Absent on any pre-migration doc → 0 (back-compat), so legacy
  /// docs collapse to a stable 0-tie that the backfill then re-stamps.
  final int sortKey;

  /// WLED bus indices this schedule applies to — 1:1 with the segment id
  /// (`DeviceChannel.id`, derived from `hw.led.ins`). `null` = every channel,
  /// which is what every writer produces today.
  ///
  /// CONSUMED BY THE FIRING LAYER as of Phase D. `syncAll`'s pattern-preset
  /// path routes the design through `ScheduleSyncService.scopePatternPayload`,
  /// so the addressed channels get the design and every other live segment is
  /// written `on:false`.
  ///
  /// ⚠️ A SCOPED SCHEDULE DARKENS THE CHANNELS IT EXCLUDES. "Leave the others
  /// as they were" is not available to a timer-fired preset: `psave` snapshots
  /// every segment (audit/U7_ABSENT_SEGMENT_PROBE.md), so an omitted channel is
  /// captured at whatever it happened to be showing rather than left alone. The
  /// editor states this.
  ///
  /// DURABILITY: also persisted to the `schedule_scope` sidecar (D1), because
  /// an old build rewrites the whole array through `toJson()` and would
  /// otherwise strip this field from every schedule in the account.
  final List<int>? channels;

  /// Which controller [channels] indexes into (D1 / P5 decision).
  ///
  /// A bus index is only meaningful against ONE controller's `hw.led.ins` —
  /// channel 1 on the garage controller is not channel 1 on the back-yard one.
  /// So a scoped item names its controller, and the sync path applies it only
  /// there. Null whenever [channels] is null.
  final String? controllerId;

  /// Roofline slice 2 — the saved design this schedule replays, when it is a
  /// PAINTED (per-pixel) design scheduled nightly. Null for every other
  /// schedule (catalog patterns, Turn Off, Brightness, React to Music).
  ///
  /// Stored as `design_id`. The sync reads [presetKind], not this, to choose
  /// the preset builder; this is the back-reference the UI and support use.
  final String? designId;

  /// Roofline slice 2 — which KIND of WLED preset the sync writes for this
  /// schedule. Null (every schedule before this field existed, and every
  /// catalog pattern) means the ordinary captured-state preset: the body is
  /// scoped, fanned out over the buses and psaved as live state.
  /// `kSchedulePresetKindApi` ('api') means a WLED API-command preset
  /// (`o:true`): the stored [wledPayload] IS the request the controller
  /// replays at fire time, one entry per bus with explicit bounds, carrying
  /// the painted picture (`seg[].i`). The sync bypasses scoping and fan-out
  /// for it and gates it (LAN, layout fit, firmware, byte cap) before any
  /// write. See design_api_preset.dart.
  ///
  /// Stored as `preset_kind`. DURABILITY: an older build rewrites the whole
  /// `schedules` array through its own `toJson()` and would drop both fields;
  /// the schedule then reads as a plain per-pixel payload, which the sync
  /// REFUSES to psave (it would fire dark), so the failure is a refusal, not
  /// a wrong look. No sidecar in this slice.
  final String? presetKind;

  const ScheduleItem({
    required this.id,
    required this.timeLabel,
    this.offTimeLabel,
    required this.repeatDays,
    required this.actionLabel,
    required this.enabled,
    this.wledPayload,
    this.presetId,
    this.useAudioReactive,
    this.disabledUntil,
    this.sourcePromptId,
    this.sortKey = 0,
    this.channels,
    this.controllerId,
    this.designId,
    this.presetKind,
  });

  /// True when this item targets a subset of channels rather than the strip.
  bool get isChannelScoped => channels != null;

  /// True when the sync must write this schedule as a WLED API-command preset
  /// (a painted design) — see [presetKind].
  bool get isDesignApiPreset => presetKind == kSchedulePresetKindApi;

  /// UI-safe action label. Routes the pattern-name portion of a
  /// `"Pattern: <name>"` [actionLabel] through the centralized slug
  /// resolver. Non-pattern labels (e.g. "Turn Off") pass through
  /// unchanged.
  String get displayActionLabel => actionLabel.startsWith('Pattern: ')
      ? 'Pattern: ${displayNameFor(actionLabel.substring(9))}'
      : actionLabel;

  /// Returns true if this schedule has an off time configured.
  bool get hasOffTime => offTimeLabel != null && offTimeLabel!.isNotEmpty;

  /// Returns true if this schedule has a WLED payload to apply.
  bool get hasWledPayload => wledPayload != null && wledPayload!.isNotEmpty;

  /// Whether this schedule is currently soft-evicted by a
  /// [CalendarEntryLeaseManager] eviction. Returns false if
  /// [disabledUntil] is null or in the past.
  ///
  /// Boundary convention: `disabledUntil > DateTime.now()` only —
  /// an exactly-equal timestamp is treated as expired (re-enabled).
  /// The 1-second resolution of `DateTime.now()` plus the
  /// 5-minute periodic sweep means equal-to-now is effectively
  /// never hit in practice; this convention picks the more
  /// permissive interpretation when it does.
  bool get isCurrentlyEvicted {
    final until = disabledUntil;
    if (until == null) return false;
    return until.isAfter(DateTime.now());
  }

  ScheduleItem copyWith({
    String? id,
    String? timeLabel,
    String? offTimeLabel,
    bool clearOffTime = false,
    List<String>? repeatDays,
    String? actionLabel,
    bool? enabled,
    Map<String, dynamic>? wledPayload,
    bool clearWledPayload = false,
    int? presetId,
    bool clearPresetId = false,
    bool? useAudioReactive,
    DateTime? disabledUntil,
    bool clearDisabledUntil = false,
    String? sourcePromptId,
    int? sortKey,
    List<int>? channels,
    String? controllerId,
    /// Clears BOTH scope fields. Needed because `channels: null` cannot mean
    /// "remove the scope" through the usual `?? this.x` idiom.
    bool clearScope = false,
    String? designId,
    String? presetKind,
    /// Clears BOTH design fields (a re-pick of a catalog pattern over a
    /// painted design must not keep calling the schedule a design).
    bool clearDesign = false,
  }) =>
      ScheduleItem(
        id: id ?? this.id,
        timeLabel: timeLabel ?? this.timeLabel,
        offTimeLabel: clearOffTime ? null : (offTimeLabel ?? this.offTimeLabel),
        repeatDays: repeatDays ?? this.repeatDays,
        actionLabel: actionLabel ?? this.actionLabel,
        enabled: enabled ?? this.enabled,
        wledPayload: clearWledPayload ? null : (wledPayload ?? this.wledPayload),
        presetId: clearPresetId ? null : (presetId ?? this.presetId),
        useAudioReactive: useAudioReactive ?? this.useAudioReactive,
        disabledUntil:
            clearDisabledUntil ? null : (disabledUntil ?? this.disabledUntil),
        sourcePromptId: sourcePromptId ?? this.sourcePromptId,
        sortKey: sortKey ?? this.sortKey,
        channels: clearScope ? null : (channels ?? this.channels),
        controllerId:
            clearScope ? null : (controllerId ?? this.controllerId),
        designId: clearDesign ? null : (designId ?? this.designId),
        presetKind: clearDesign ? null : (presetKind ?? this.presetKind),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timeLabel': timeLabel,
        if (offTimeLabel != null) 'offTimeLabel': offTimeLabel,
        'repeatDays': repeatDays,
        'actionLabel': actionLabel,
        'enabled': enabled,
        if (wledPayload != null) 'wledPayload': jsonEncode(wledPayload),
        if (presetId != null) 'presetId': presetId,
        if (useAudioReactive != null) 'useAudioReactive': useAudioReactive,
        if (disabledUntil != null)
          'disabledUntil': disabledUntil!.toIso8601String(),
        if (sourcePromptId != null) 'sourcePromptId': sourcePromptId,
        // Always emitted — it's a first-class ordering field, not optional.
        'sortKey': sortKey,
        // Omitted when null so a schedule that scopes to every channel (all of
        // them, today) writes the same document it always did.
        if (channels != null) 'channels': channels,
        if (controllerId != null) 'controllerId': controllerId,
        // Omitted when null so every schedule that is not a painted design
        // writes the same document it always did.
        if (designId != null) 'design_id': designId,
        if (presetKind != null) 'preset_kind': presetKind,
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        id: json['id'] as String,
        timeLabel: json['timeLabel'] as String,
        offTimeLabel: json['offTimeLabel'] as String?,
        repeatDays: (json['repeatDays'] as List).map((e) => e.toString()).toList(),
        actionLabel: json['actionLabel'] as String,
        enabled: json['enabled'] as bool,
        wledPayload: json['wledPayload'] is String
            ? (jsonDecode(json['wledPayload'] as String) as Map<String, dynamic>?)
            : json['wledPayload'] as Map<String, dynamic>?,
        presetId: json['presetId'] as int?,
        useAudioReactive: json['useAudioReactive'] as bool?,
        // Defensive parse — absence, non-string, or invalid ISO 8601
        // all collapse to null so a corrupt field can't crash boot.
        disabledUntil: _tryParseDisabledUntil(json['disabledUntil']),
        sourcePromptId: json['sourcePromptId'] as String?,
        // Absent on pre-migration docs → 0 (back-compat). Tolerate num.
        sortKey: (json['sortKey'] as num?)?.toInt() ?? 0,
        channels: _tryParseChannels(json['channels']),
        controllerId: json['controllerId'] as String?,
        designId: _tryParseNonEmptyString(json['design_id']),
        presetKind: _tryParseNonEmptyString(json['preset_kind']),
      );

  /// Absent, wrong type, or empty collapse to null rather than throw or keep
  /// an empty marker a reader could mistake for a kind.
  static String? _tryParseNonEmptyString(dynamic raw) {
    if (raw is! String) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  /// Absent, wrong type, or non-numeric members all collapse rather than
  /// throw. An empty list survives as empty — "explicitly none" is a different
  /// statement from null ("all"), even though nothing reads either yet.
  static List<int>? _tryParseChannels(dynamic raw) {
    if (raw is! List) return null;
    return raw.whereType<num>().map((n) => n.toInt()).toList(growable: false);
  }

  static DateTime? _tryParseDisabledUntil(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  // describeIdentity equivalent without a flutter/foundation dependency (this
  // model is imported by the pure-Dart bench harness — no dart:ui).
  String toString() =>
      '$runtimeType#${identityHashCode(this).toRadixString(16)}';
}
