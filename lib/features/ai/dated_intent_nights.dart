// lib/features/ai/dated_intent_nights.dart
//
// +112 (#121) — the chat's cloud `schedulingIntents` as DATED nights.
//
// A cloud reply that carries schedulingIntents names repeat days and times.
// When the customer did not ask for anything to repeat, those days mean "the
// next such nights", so each repeat day becomes the next matching date inside
// a week, and each date becomes one PlannedNight for the D2 persistence
// (`planLuminaNightWrites` → `applyEntriesDetailed(drop)`), which already
// skips Game Day dates, armed nights and the customer's own entries, and
// reports a full pool instead of prompting.
//
// The pure parts live here so they are unit-tested; the Riverpod/UI half is
// `offerDatedNightsFromIntents` at the bottom.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_persistence.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/dated_entry_compose.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/theme.dart';

const _kDayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The next date (today included) for each of [repeatDays] within seven days
/// of [today], sorted. Day labels are matched on their first three letters,
/// case-insensitively; unknown labels are ignored.
List<DateTime> nextDatesForDays(List<String> repeatDays, DateTime today) {
  final wanted = <int>{};
  for (final raw in repeatDays) {
    final s = raw.trim().toLowerCase();
    if (s.length < 3) continue;
    final idx = _kDayShort.indexWhere((d) => d.toLowerCase() == s.substring(0, 3));
    if (idx >= 0) wanted.add(idx + 1); // DateTime.monday == 1
  }
  final start = DateTime(today.year, today.month, today.day);
  return [
    for (var i = 0; i < 7; i++)
      if (wanted.contains(start.add(Duration(days: i)).weekday))
        start.add(Duration(days: i)),
  ];
}

/// One dated night per (intent, next matching date), de-duplicated by date
/// (the first intent to claim a date keeps it), sorted by date.
///
/// An intent with no off time ends at the next sunrise — the lease needs an
/// end, and that is the D2 default too. Sunset / Sunrise triggers resolve to
/// that date's clock time from the account's coordinates.
List<PlannedNight> plannedNightsFromIntents({
  required List<SchedulingIntent> intents,
  Map<String, dynamic>? sharedPayload,
  required DateTime now,
  double? latitude,
  double? longitude,
}) {
  final out = <PlannedNight>[];
  final seen = <String>{};
  for (final intent in intents) {
    final payload = intent.wled ?? sharedPayload ?? const <String, dynamic>{};
    for (final date in nextDatesForDays(intent.repeatDays, now)) {
      final key = dateKeyOf(date);
      if (!seen.add(key)) continue;
      final on = resolveDatedClock(
        trigger: intent.timeLabel,
        date: date,
        isEnd: false,
        latitude: latitude,
        longitude: longitude,
      );
      final off = resolveDatedClock(
        trigger: intent.offTimeLabel ?? 'Sunrise',
        date: date,
        isEnd: true,
        latitude: latitude,
        longitude: longitude,
      );
      final bri = payload['bri'];
      final name = displayNameFor(intent.patternName);
      out.add(PlannedNight(
        index: out.length,
        date: date,
        patternName: name,
        effectName: name,
        wled: Map<String, dynamic>.from(payload),
        onTime: on.hhmm,
        offTime: off.hhmm,
        color: firstColorOfPayload(payload),
        brightnessPercent:
            bri is num ? (bri / 255 * 100).round().clamp(1, 100) : 100,
      ));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return [
    for (var i = 0; i < out.length; i++)
      PlannedNight(
        index: i,
        date: out[i].date,
        patternName: out[i].patternName,
        effectName: out[i].effectName,
        wled: out[i].wled,
        onTime: out[i].onTime,
        offTime: out[i].offTime,
        color: out[i].color,
        brightnessPercent: out[i].brightnessPercent,
      ),
  ];
}

/// The reply after an Add: what landed, what was skipped (and why), what
/// did not fit. Never claims more than the outcome shows.
String datedNightsReply({
  required String themeName,
  required List<PlannedNight> nights,
  required ScheduleNightsOutcome outcome,
}) {
  final savedIdx = outcome.saved.toSet();
  final saved = [for (final n in nights) if (savedIdx.contains(n.index)) n];
  final parts = <String>[];
  if (saved.isEmpty) {
    parts.add("I couldn't save $themeName to your Schedule"
        '${outcome.message == null ? '.' : ' — ${outcome.message}'}');
  } else if (saved.length == 1) {
    parts.add('$themeName is in your Schedule for ${saved.first.dayLabel} '
        '(${formatDatedDate(saved.first.date)}). It runs that night only.');
  } else {
    final list = saved.map((n) => n.dayLabel).join(', ');
    parts.add('$themeName is in your Schedule for ${saved.length} nights: '
        '$list. They run on those nights only — say "every night" or '
        '"every Friday" if you want it to repeat.');
  }
  parts.addAll(outcome.skipped);
  if (outcome.unfitted > 0) {
    parts.add("I couldn't fit ${outcome.unfitted} "
        '${outcome.unfitted == 1 ? 'night' : 'nights'} — your schedule is '
        'full. Free a slot in My Schedule and ask again.');
  }
  return parts.join(' ');
}

/// The Riverpod/UI half: propose the nights in one SnackBar, write them on
/// [Add] through the D2 persistence, then post the honest reply.
Future<void> offerDatedNightsFromIntents({
  required WidgetRef ref,
  required BuildContext context,
  required List<SchedulingIntent> intents,
  required LuminaCommandResult result,
  required LuminaPatternPreview? preview,
  VoidCallback? onMessagePosted,
}) async {
  // Capture every handle NOW — the sheet that owns `ref` may be gone by the
  // time the SnackBar action runs (same rule as handleSchedulingIntents).
  final controller = ref.read(luminaSheetProvider.notifier);
  final calendarNotifier = ref.read(calendarScheduleProvider.notifier);
  final leaseManager = ref.read(calendarEntryLeaseManagerProvider);
  final profile = ref.read(currentUserProfileProvider).valueOrNull;

  final nights = plannedNightsFromIntents(
    intents: intents,
    sharedPayload: result.wledPayload,
    now: DateTime.now(),
    latitude: profile?.latitude,
    longitude: profile?.longitude,
  );
  if (nights.isEmpty) {
    controller.addAssistantMessage(
      "I couldn't work out which nights you meant. Tell me the days, or say "
      '"every night" if it should repeat.',
    );
    onMessagePosted?.call();
    return;
  }
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final themeName = displayNameFor(intents.first.patternName);
  final count = nights.length;
  final promptText = count == 1
      ? 'Add "$themeName" for ${nights.first.dayLabel} only?'
      : 'Add "$themeName" for the next $count nights '
          '(${nights.map((n) => n.dayLabel).join(', ')})?';

  messenger.showSnackBar(
    SnackBar(
      content: Text(promptText, style: const TextStyle(color: Color(0xFFDCF0FF))),
      backgroundColor: NexGenPalette.gunmetal90,
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Add',
        textColor: NexGenPalette.cyan,
        onPressed: () async {
          final batchId = DateTime.now().millisecondsSinceEpoch.toString();
          final leased =
              leaseManager.activeLeases.map((l) => l.dateKey).toSet();
          final plan = planLuminaNightWrites(
            nights: nights,
            batchId: batchId,
            existingOn: calendarNotifier.entriesFor,
            leasedDateKeys: leased,
          );
          ScheduleNightsOutcome outcome;
          if (plan.entries.isEmpty) {
            outcome = ScheduleNightsOutcome(
              requested: count,
              persisted: 0,
              skipped: plan.skipReplies,
              message: plan.skipped.isEmpty
                  ? "I couldn't tell what time each night should start. Tell "
                      'me a time like "7pm" or "sunset".'
                  : null,
            );
          } else {
            try {
              final applied = await calendarNotifier.applyEntriesDetailed(
                plan.entries,
                noFreeSlots: NoFreeSlotsPolicy.drop,
              );
              if (!applied.ok) {
                outcome = ScheduleNightsOutcome(
                  requested: count,
                  persisted: 0,
                  skipped: plan.skipReplies,
                  message: applied.message ??
                      "the Schedule didn't accept them. Check your connection "
                          'and try again.',
                );
              } else {
                final droppedIds =
                    applied.dropped.map((e) => e.entryId).toSet();
                final saved = [
                  for (final w in plan.writes)
                    if (!droppedIds.contains(w.entry.entryId)) w.night.index,
                ];
                outcome = ScheduleNightsOutcome(
                  requested: count,
                  persisted: saved.length,
                  saved: saved,
                  skipped: plan.skipReplies,
                  unfitted: droppedIds.length,
                );
              }
            } catch (e) {
              debugPrint('offerDatedNightsFromIntents: apply threw: $e');
              outcome = ScheduleNightsOutcome(
                requested: count,
                persisted: 0,
                skipped: plan.skipReplies,
                message: 'something went wrong saving them. Try again.',
              );
            }
          }
          controller.addAssistantMessage(
            datedNightsReply(
                themeName: themeName, nights: nights, outcome: outcome),
            preview: preview,
            wledPayload: result.wledPayload,
          );
          onMessagePosted?.call();
          messenger.showSnackBar(
            SnackBar(
              content: Text(outcome.persisted > 0
                  ? '${outcome.persisted} '
                      '${outcome.persisted == 1 ? 'night' : 'nights'} added'
                  : 'Nothing was added'),
              backgroundColor: outcome.persisted > 0
                  ? Colors.green.shade700
                  : NexGenPalette.gunmetal90,
              duration: const Duration(seconds: 3),
            ),
          );
        },
      ),
    ),
  );
}
