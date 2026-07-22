import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/models/commercial/commercial_event.dart';

/// Streams the current user's [CommercialEvent]s, ordered by start
/// date ascending. Lives at /users/{uid}/commercial_events/{eventId}.
///
/// Returns an empty list while unauthenticated. The Part-1 firestore
/// rule already restricts read access to the owner, so this listener
/// is effectively scoped to the current user.
final commercialEventsProvider =
    StreamProvider<List<CommercialEvent>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('commercial_events')
      .orderBy('start_date')
      .snapshots()
      .map((snap) =>
          snap.docs.map(CommercialEvent.fromFirestore).toList(growable: false));
});

/// The currently-active event, if any. "Active" is computed at read
/// time via [CommercialEvent.statusAt] — no stored status field, no
/// stale data when the device clock crosses an event boundary while
/// offline.
///
/// If multiple events overlap, returns the one whose start_date is
/// nearest to now (Firestore order-by start_date ascending → first
/// active match in the iteration is the most recently started).
final activeCommercialEventProvider = Provider<CommercialEvent?>((ref) {
  final events = ref.watch(commercialEventsProvider).valueOrNull ?? const [];
  if (events.isEmpty) return null;
  final now = DateTime.now();
  CommercialEvent? mostRecent;
  for (final e in events) {
    if (e.statusAt(now) == EventStatus.active) {
      if (mostRecent == null ||
          e.startDate.isAfter(mostRecent.startDate)) {
        mostRecent = e;
      }
    }
  }
  return mostRecent;
});

/// Upcoming events (start_date in the future), preserving the
/// underlying ascending order.
final upcomingCommercialEventsProvider =
    Provider<List<CommercialEvent>>((ref) {
  final events = ref.watch(commercialEventsProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  return events.where((e) => e.startDate.isAfter(now)).toList(growable: false);
});

/// Past events (end_date already in the past), preserving the
/// underlying ascending order. Rendered in a collapsed ExpansionTile
/// on the events screen.
final pastCommercialEventsProvider =
    Provider<List<CommercialEvent>>((ref) {
  final events = ref.watch(commercialEventsProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  return events.where((e) => e.endDate.isBefore(now)).toList(growable: false);
});
