// lib/features/ai/entry_delete_services.dart
//
// Build 128 — what the conversation driver needs from the app to carry out a
// `deleteCalendarEntries` intent: the calendar to resolve against, a way to
// post the confirmation card, and the SAME removal path the detail sheet's
// "Delete This Entry" button uses (`CalendarScheduleNotifier.removeEntryById`,
// which releases or re-derives the night's lease and then writes through
// `saveCalendarEntries`). A separate small interface rather than more members
// on LuminaConversationServices, so the driver's existing fakes stay as they
// are and a surface built without it degrades to the manual route
// ([kEntryDeleteNotAvailable]).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/entry_delete_resolver.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';

/// The app, as the delete branch of [LuminaConversationDriver] sees it.
abstract class LuminaEntryDeleteServices {
  /// Every dated entry the phone holds right now.
  List<CalendarEntry> calendarEntries();

  /// The current time — "everything you created" means today and later.
  DateTime now();

  /// Posts the confirmation card: [text] above the list, Delete and Cancel.
  void postProposal(String text, EntryDeleteProposal proposal);

  /// Removes [entries] one at a time through the manual route and returns
  /// how many were removed. Never throws.
  Future<int> deleteEntries(List<CalendarEntry> entries);

  /// Called after [EntryDeleteProposal.decision] changed, so the card can
  /// show the decision and drop its buttons.
  void proposalDecided(EntryDeleteProposal proposal);
}

/// Riverpod binding. Every provider is read inline through [ref] at the
/// moment of use — no notifier is held.
class RiverpodLuminaEntryDeleteServices implements LuminaEntryDeleteServices {
  final WidgetRef ref;

  const RiverpodLuminaEntryDeleteServices(this.ref);

  @override
  List<CalendarEntry> calendarEntries() =>
      ref.read(calendarScheduleProvider).allEntries;

  @override
  DateTime now() => DateTime.now();

  @override
  void postProposal(String text, EntryDeleteProposal proposal) => ref
      .read(luminaSheetProvider.notifier)
      .addEntryDeleteProposal(text, proposal);

  @override
  Future<int> deleteEntries(List<CalendarEntry> entries) async {
    // Function-scoped capture of a container-scoped notifier (the pattern the
    // scheduling handler uses): the removals must finish even if the surface
    // is dismissed mid-way, and `ref` would throw after dispose.
    final calendar = ref.read(calendarScheduleProvider.notifier);
    var removed = 0;
    for (final e in entries) {
      try {
        if (await calendar.removeEntryById(e.dateKey, e.entryId)) removed++;
      } catch (err) {
        debugPrint('[EntryDelete] ${e.dateKey}/${e.entryId} failed: $err');
      }
    }
    return removed;
  }

  @override
  void proposalDecided(EntryDeleteProposal proposal) =>
      ref.read(luminaSheetProvider.notifier).entryDeleteProposalDecided();
}
