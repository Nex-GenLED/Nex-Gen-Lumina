// lib/features/schedule/schedules_subcollection_feature_flag.dart
//
// Staged-rollout flag gating the storage backend for the user's schedules.
//
// When resolved OFF (default), schedules persist as the `schedules` array field
// on /users/{uid} — byte-identical to every prior release
// (LegacyArrayScheduleRepository). When ON, they persist under
// /users/{uid}/schedules/{id} (SubcollectionScheduleRepository).
//
// The flag lives at config/schedules_subcollection and DEFAULTS FALSE. A single
// global boolean can't stage a rollout or isolate the founder account for
// hardware bench-verify, so the doc schema is (READ-SIDE only — no writer here):
//
//   {
//     enabled: bool,               // global kill-switch / full-on
//     allowlistUids: List<String>, // per-uid opt-in (founder, canary)
//     rolloutPercent: int (0-100),  // stable % bucket rollout
//   }
//
// Resolution for a uid is TRUE iff ANY of:
//   • enabled == true, OR
//   • uid ∈ allowlistUids, OR
//   • rolloutPercent > 0 AND schedulesSubcollectionBucket(uid) < rolloutPercent
//
// DEFENSIVE-FALSE is preserved exactly: a missing doc, missing/non-bool
// `enabled`, non-list `allowlistUids`, non-int/out-of-range `rolloutPercent`,
// the StreamProvider loading window, and any stream error all collapse to the
// safe empty config → resolves false. A per-uid bucket is stable across reads
// and releases (documented hash), so a uid never flip-flops between backends.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';

/// Firestore document path holding the flag.
const String kSchedulesSubcollectionFlagCollection = 'config';
const String kSchedulesSubcollectionFlagDocId = 'schedules_subcollection';

/// Parsed, always-valid view of the flag doc. Every field has a safe empty
/// default so degraded reads can never enable the subcollection backend.
@immutable
class SchedulesSubcollectionConfig {
  const SchedulesSubcollectionConfig({
    this.enabled = false,
    this.allowlistUids = const <String>[],
    this.rolloutPercent = 0,
  });

  final bool enabled;
  final List<String> allowlistUids;

  /// 0-100. Stable-bucket percentage rollout.
  final int rolloutPercent;

  static const SchedulesSubcollectionConfig empty = SchedulesSubcollectionConfig();
}

/// Defensive parse of the raw flag-doc data into a [SchedulesSubcollectionConfig].
/// `null` data (whole doc missing / no data) → [SchedulesSubcollectionConfig.empty].
/// Each field independently falls back to its safe empty when absent or the
/// wrong type. `rolloutPercent` is clamped to [0, 100].
SchedulesSubcollectionConfig parseSchedulesSubcollectionConfig(
    Map<String, dynamic>? data) {
  if (data == null) return SchedulesSubcollectionConfig.empty;

  final enabled = data['enabled'] is bool ? data['enabled'] as bool : false;

  final rawList = data['allowlistUids'];
  final allowlist =
      rawList is List ? rawList.whereType<String>().toList() : const <String>[];

  final rawPct = data['rolloutPercent'];
  final pctRaw = rawPct is int ? rawPct : 0;
  final pct = pctRaw < 0 ? 0 : (pctRaw > 100 ? 100 : pctRaw);

  return SchedulesSubcollectionConfig(
    enabled: enabled,
    allowlistUids: allowlist,
    rolloutPercent: pct,
  );
}

/// Stable, release-invariant rollout bucket in [0, 100) for [uid].
///
/// md5(uid) → the first 4 digest bytes as a big-endian uint32 → mod 100. md5 is
/// deterministic and its output is uniform enough for bucketing, so a given uid
/// ALWAYS maps to the same bucket across every read and app release. This must
/// never change — altering the hash would re-bucket the whole fleet and churn
/// which users are on which backend.
int schedulesSubcollectionBucket(String uid) {
  final b = md5.convert(utf8.encode(uid)).bytes;
  final n = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]; // uint32 in a 64-bit int
  return n % 100;
}

/// Pure resolution: does [uid] get the subcollection backend under [config]?
/// TRUE iff globally enabled, or explicitly allowlisted, or inside the stable
/// percentage bucket. A null/empty uid can only be enabled globally (the per-uid
/// rules need a uid). Returns false for the empty config regardless of uid.
bool resolveSchedulesSubcollectionEnabled(
    SchedulesSubcollectionConfig config, String? uid) {
  if (config.enabled) return true;
  if (uid == null || uid.isEmpty) return false;
  if (config.allowlistUids.contains(uid)) return true;
  if (config.rolloutPercent > 0 &&
      schedulesSubcollectionBucket(uid) < config.rolloutPercent) {
    return true;
  }
  return false;
}

/// Streams the parsed flag config. Defaults to [SchedulesSubcollectionConfig.empty]
/// for any degraded state — missing doc, malformed fields, or a Firestore error.
final schedulesSubcollectionConfigProvider =
    StreamProvider<SchedulesSubcollectionConfig>((ref) async* {
  SchedulesSubcollectionConfig? lastEmitted;
  try {
    final docStream = FirebaseFirestore.instance
        .collection(kSchedulesSubcollectionFlagCollection)
        .doc(kSchedulesSubcollectionFlagDocId)
        .snapshots();
    await for (final snap in docStream) {
      final cfg = parseSchedulesSubcollectionConfig(snap.data());
      if (lastEmitted == null ||
          cfg.enabled != lastEmitted.enabled ||
          cfg.rolloutPercent != lastEmitted.rolloutPercent ||
          cfg.allowlistUids.length != lastEmitted.allowlistUids.length) {
        debugPrint('SchedulesSubcollection: enabled=${cfg.enabled} '
            'allowlist=${cfg.allowlistUids.length} pct=${cfg.rolloutPercent}');
        lastEmitted = cfg;
      }
      yield cfg;
    }
  } catch (e) {
    debugPrint(
        'SchedulesSubcollection: config stream error — $e (defaulting to empty)');
    yield SchedulesSubcollectionConfig.empty;
  }
});

/// Per-CURRENT-uid resolution used by the schedules read path
/// (scheduleRepositoryProvider + userSchedulesStreamProvider). Resolves for the
/// effective user (installer impersonation-aware via [effectiveUserUidProvider]).
/// Defaults to `false` during the config StreamProvider's loading window or any
/// error — the safe default (legacy array backend).
final schedulesSubcollectionEnabledSyncProvider = Provider<bool>((ref) {
  final config = ref.watch(schedulesSubcollectionConfigProvider).maybeWhen(
        data: (c) => c,
        orElse: () => SchedulesSubcollectionConfig.empty,
      );
  final uid = ref.watch(effectiveUserUidProvider);
  return resolveSchedulesSubcollectionEnabled(config, uid);
});

/// uid-less convenience: the GLOBAL-only result (the `enabled` kill-switch),
/// for any non-user context. Defaults false. Equivalent to
/// resolveSchedulesSubcollectionEnabled(config, null).
final schedulesSubcollectionGloballyEnabledProvider = Provider<bool>((ref) {
  return ref.watch(schedulesSubcollectionConfigProvider).maybeWhen(
        data: (c) => c.enabled,
        orElse: () => false,
      );
});

/// One-time bootstrap so the Firestore console has a doc to edit. Creates the
/// flag with `enabled:false` if absent. Best-effort; failures are logged, never
/// rethrown.
///
/// NOTE: deliberately NOT called anywhere (enables no new writes). The optional
/// `allowlistUids` / `rolloutPercent` fields are added by hand in the console
/// during a staged rollout — the reader treats them as absent → safe empty.
Future<void> bootstrapSchedulesSubcollectionFlagDoc() async {
  try {
    final doc = FirebaseFirestore.instance
        .collection(kSchedulesSubcollectionFlagCollection)
        .doc(kSchedulesSubcollectionFlagDocId);
    final snap = await doc.get();
    if (snap.exists) return;
    await doc.set(<String, dynamic>{
      'enabled': false,
      'lastModified': FieldValue.serverTimestamp(),
      'modifiedBy': 'system_bootstrap',
      'notes': 'Auto-created. enabled=true for a full flip. For a staged '
          'rollout add allowlistUids:[<uid>...] (founder/canary) and/or '
          'rolloutPercent:0-100. Do NOT enable before a backfill + subcollection '
          'Firestore rules ship.',
    });
    debugPrint(
        'SchedulesSubcollection: bootstrapped config/schedules_subcollection (enabled=false)');
  } catch (e) {
    debugPrint(
        'SchedulesSubcollection: bootstrap failed — $e (safe; defaults false)');
  }
}
