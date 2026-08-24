// lib/features/schedule/scope_sidecar.dart
//
// Scheduling V3 D1 — DURABLE channel scope, for both schedule stores.
//
// ── THE PROBLEM ───────────────────────────────────────────────────────────────
//
// `channels` and `controllerId` live on the model, and the model round-trips
// through `toJson()` on every save. A build that predates those fields emits a
// `toJson()` without them — and both stores rewrite EVERY entry on an ordinary
// edit, not just the one being changed:
//
//   • `users/{uid}.schedules`      — `saveAll`, `applyArrayTxn` (used by
//     `remove` and `update`), `overwriteArray`, and the subcollection mirror,
//     all `.map((e) => e.toJson())` over the whole set
//     (schedule_store_sync.dart:106, :120, :135; legacy repo :117).
//   • `users/{uid}.calendar_entries` — the whole field is rewritten by
//     `saveCalendarEntries` (audit/SCHEDULE_V3_P2.md P4).
//
// So one edit on an old build silently un-scopes EVERY scoped item in the
// account, and the next sync quietly relights channels the customer had
// excluded. That is not a display bug; it is lights on a house.
//
// ── THE FIX ───────────────────────────────────────────────────────────────────
//
// Persist the scope a SECOND time, in a sidecar field on the same document that
// old builds neither read nor write:
//
//   users/{uid}.schedule_scope        { "<scheduleId>": {"c": "...", "ch":[0,1]} }
//   users/{uid}.calendar_entry_scope  { "<entryKey>":   {"c": "...", "ch":[0]}   }
//
// An old build rewriting `schedules` / `calendar_entries` leaves the sidecar
// untouched, because it has no code that names those fields. A new build reads
// the model field first and FALLS BACK to the sidecar, so the scope survives.
//
// ── WHY A SIDECAR RATHER THAN A SUBCOLLECTION ─────────────────────────────────
//
// It has to be on the SAME document. Firestore's `update()` replaces only the
// named fields, so a sibling field on the same doc is untouched by a write that
// does not name it. A separate document would also survive, but then a scope
// write and its item write could not be atomic, and an interrupted save would
// leave a scope pointing at an item that was never stored.
//
// ── SHAPE ─────────────────────────────────────────────────────────────────────
//
// `{"c": <controllerId?>, "ch": [<int>...]}` — short keys because this map has
// one entry per scoped item and rides on the user document, which is already
// the largest doc in the account. `ch` is a FLAT list of ints; never a list of
// lists (#84). An entry is written ONLY for a scoped item, so an all-channel
// account has no sidecar field at all.

import 'package:flutter/foundation.dart';

/// One item's channel scope. `null` in both fields means "all channels" — the
/// same meaning `CalendarEntry.channels == null` carries on the model.
@immutable
class ItemScope {
  /// WLED bus indices, 1:1 with segment id. Null = every channel.
  final List<int>? channels;

  /// Which controller [channels] refer to. A bus index is only meaningful
  /// against one controller's `hw.led.ins`, so a scoped item must name it.
  /// Null whenever [channels] is null.
  final String? controllerId;

  const ItemScope({this.channels, this.controllerId});

  static const ItemScope none = ItemScope();

  /// True when this scope says anything worth persisting.
  bool get isScoped => channels != null;

  @override
  bool operator ==(Object other) =>
      other is ItemScope &&
      other.controllerId == controllerId &&
      _sameInts(other.channels, channels);

  @override
  int get hashCode => Object.hash(controllerId, Object.hashAll(channels ?? const []));

  static bool _sameInts(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'ItemScope(c: $controllerId, ch: $channels)';
}

const String kScopeChannelsKey = 'ch';
const String kScopeControllerKey = 'c';

/// Firestore field name for the recurring-schedule sidecar.
const String kScheduleScopeField = 'schedule_scope';

/// Firestore field name for the dated-entry sidecar.
const String kCalendarEntryScopeField = 'calendar_entry_scope';

/// Build the sidecar map from `key → scope`.
///
/// UNSCOPED ITEMS ARE OMITTED, not written as nulls. That keeps the field
/// absent entirely for the overwhelming majority of accounts, and it makes
/// "removed the scope" a real deletion rather than a tombstone — see
/// [encodeScopeSidecar]'s use in the writers, which always rebuilds the whole
/// map so a cleared scope disappears.
Map<String, dynamic> encodeScopeSidecar(Map<String, ItemScope> byKey) {
  final out = <String, dynamic>{};
  byKey.forEach((key, scope) {
    if (!scope.isScoped) return;
    out[key] = <String, dynamic>{
      if (scope.controllerId != null) kScopeControllerKey: scope.controllerId,
      kScopeChannelsKey: scope.channels,
    };
  });
  return out;
}

/// Read one item's scope out of a raw sidecar map.
///
/// Tolerant by design: a missing field, a non-map value, a non-list `ch`, or
/// non-numeric members all collapse to [ItemScope.none] rather than throwing.
/// A corrupt sidecar must degrade to "all channels" — the pre-V3 behaviour —
/// never crash a boot.
ItemScope decodeScopeEntry(dynamic sidecar, String key) {
  if (sidecar is! Map) return ItemScope.none;
  final raw = sidecar[key];
  if (raw is! Map) return ItemScope.none;
  final ch = raw[kScopeChannelsKey];
  if (ch is! List) return ItemScope.none;
  final channels = ch.whereType<num>().map((n) => n.toInt()).toList(growable: false);
  final c = raw[kScopeControllerKey];
  return ItemScope(
    channels: channels,
    controllerId: c is String && c.isNotEmpty ? c : null,
  );
}

/// Resolve the scope for an item, preferring what the item itself carries and
/// falling back to the sidecar.
///
/// THE FALLBACK IS THE WHOLE POINT. `modelChannels` is null both when the item
/// is genuinely all-channel AND when an old build stripped it, and those two
/// cases are indistinguishable from the item alone. The sidecar disambiguates:
/// present ⇒ the scope was set and something dropped it; absent ⇒ all channels.
ItemScope resolveScope({
  required List<int>? modelChannels,
  required String? modelControllerId,
  required dynamic sidecar,
  required String key,
}) {
  if (modelChannels != null) {
    return ItemScope(channels: modelChannels, controllerId: modelControllerId);
  }
  return decodeScopeEntry(sidecar, key);
}
