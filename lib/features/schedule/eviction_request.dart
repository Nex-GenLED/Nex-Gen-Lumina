// lib/features/schedule/eviction_request.dart
//
// Cross-layer plumbing for the Item #61 Workstream B eviction picker.
//
// PROBLEM: [CalendarScheduleNotifier.applyEntries] runs without a
// BuildContext (it's a Riverpod notifier) but, when the lease manager
// returns [LeaseOutcome.noFreeSlots], it needs to surface a modal so
// the user can pick a recurring ScheduleItem to soft-evict. Passing a
// BuildContext into the notifier is the canonical anti-pattern.
//
// PATTERN: The notifier sets [pendingEvictionRequestProvider] with the
// incoming entry plus a [Completer] for the user's selection, then
// awaits the completer. A `ref.listen` on My Schedule (the page that
// owns the create flow) picks up the request, shows the picker, and
// resolves the completer. The notifier resumes with the result.
//
// No new pattern is introduced beyond this file — Riverpod's
// `ref.listen` + `StateProvider` is the existing primitive used
// throughout the app for one-shot UI side-effects.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

/// A request from [CalendarScheduleNotifier.applyEntries] for the UI
/// to show the eviction picker. The notifier awaits [completer] and
/// resumes with the user's choice (or null if cancelled).
class EvictionRequest {
  /// The incoming CalendarEntry that needs a freed slot.
  final CalendarEntry entry;

  /// When the lease would expire (= entry's offTime as a real
  /// DateTime). The picker labels "Pause until X" using this and
  /// passes it back to [CalendarEntryLeaseManager.applyEvictionAndLease]
  /// so the soft-eviction window matches the lease lifetime exactly.
  final DateTime leaseUntil;

  /// Completed by the UI listener with the user's selection or null
  /// for cancel. The notifier awaits this — no progress beyond the
  /// noFreeSlots branch until the user responds.
  final Completer<ScheduleItem?> completer;

  EvictionRequest({
    required this.entry,
    required this.leaseUntil,
    required this.completer,
  });
}

/// Set by [CalendarScheduleNotifier.applyEntries] when the lease
/// manager reports `noFreeSlots`. The My Schedule page listens with
/// `ref.listen` and surfaces the picker. The provider stays set until
/// the picker resolves the completer; the listener clears it
/// immediately after.
final pendingEvictionRequestProvider =
    StateProvider<EvictionRequest?>((ref) => null);
