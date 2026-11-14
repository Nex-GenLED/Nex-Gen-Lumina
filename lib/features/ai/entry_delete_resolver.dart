// lib/features/ai/entry_delete_resolver.dart
//
// Build 128 — the APP's half of "the model proposes, the app confirms".
//
// Pure. Given the model's description ([EntryDeleteIntent]) and the calendar
// the phone holds, decide what to show the customer:
//   • a PROPOSAL — the dated entries that match, capped at
//     [kEntryDeleteMaxPerRequest], for a confirmation card with Delete and
//     Cancel (nothing is removed until Delete is tapped);
//   • a refusal — a repeating schedule (never deleted here), or a window that
//     holds only Game Day / automatic entries (managed in Game Day settings);
//   • "nothing matched", naming the window asked for;
//   • a question, when the model could not tell which day(s).
// It never guesses: an unclear scope is a question, not a best effort.
//
// WHAT IS DELETABLE. Entries Lumina wrote (sourceTag lumina_ai) and entries
// the customer made by hand (type user with no source tag). A Game Day entry
// — any entry that holds a Game Day, whatever its type, because an edited one
// becomes type user and keeps the tag — is refused and pointed at Game Day
// settings, and so is every other automatic entry (autopilot, neighbourhood
// sync, type auto/autopilot). Holiday defaults are not persisted and are not
// counted. Recurring schedules are a different model and are never touched.
//
// The strings here are the customer-facing ones; docs/release/
// build_128_candidate.md section 3 quotes them.

import 'package:nexgen_command/features/ai/entry_delete_intent.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';

/// The most entries one confirmed request may remove.
const int kEntryDeleteMaxPerRequest = 31;

/// Reply when the driver has no delete service wired (the surface was built
/// without one). The request degrades to the manual route.
const String kEntryDeleteNotAvailable =
    "I can't delete calendar entries from here yet. Open Schedule, tap the "
    'entry, then Delete This Entry.';

/// Reply for a repeating schedule — never deleted by Lumina.
const String kEntryDeleteRecurringRefused =
    "I can't delete a repeating schedule from here. Open My Schedule, tap the "
    'schedule, then Delete Recurring Schedule.';

/// Reply when the window holds only Game Day entries.
const String kEntryDeleteGameDayRefused =
    "Those are Game Day entries, so I can't delete them from here. You can "
    'manage them in Game Day settings.';

/// Reply when the model could not tell which day(s).
const String kEntryDeleteUnclear =
    'Which entries should I delete? Give me a day, a range of dates, or say '
    '"everything you created".';

/// Posted when the customer taps Cancel on the card.
const String kEntryDeleteCancelled = 'Okay, nothing was deleted.';

/// How the customer answered a proposal.
enum EntryDeleteDecision { pending, deleted, cancelled }

/// Which way [resolveEntryDeletion] went.
enum EntryDeleteResolutionKind {
  /// Show the card: [EntryDeleteResolution.proposal] is set.
  propose,

  /// Nothing deletable matched; [EntryDeleteResolution.reply] says so.
  nothing,

  /// Only Game Day entries matched.
  gameDayRefused,

  /// The customer asked about a repeating schedule.
  recurringRefused,

  /// The model could not tell which day(s); ask.
  unclear,
}

/// Which entries a confirmed Delete would remove, and what the card says.
class EntryDeleteProposal {
  /// The entries, at most [kEntryDeleteMaxPerRequest], in date order.
  final List<CalendarEntry> entries;

  /// Game Day entries in the window, left alone.
  final int gameDaySkipped;

  /// Other automatic entries in the window, left alone.
  final int autoSkipped;

  /// Matching entries beyond the cap, not in [entries].
  final int overflow;

  /// The window as the customer asked for it, for the reply ("on Fri, Nov
  /// 20", "from Nov 20 to Nov 27", "that I created").
  final String scopeLabel;

  /// The customer's answer. Mutable, like `LuminaMessage.feedbackGiven`: the
  /// card disables its buttons once decided.
  EntryDeleteDecision decision = EntryDeleteDecision.pending;

  EntryDeleteProposal({
    required this.entries,
    required this.scopeLabel,
    this.gameDaySkipped = 0,
    this.autoSkipped = 0,
    this.overflow = 0,
  });

  int get count => entries.length;

  /// The card's lead line.
  String get leadText {
    final b = StringBuffer(count == 1
        ? 'Delete this entry? Nothing is removed until you tap Delete.'
        : 'Delete these $count entries? Nothing is removed until you tap '
            'Delete.');
    if (gameDaySkipped > 0) {
      b.write(gameDaySkipped == 1
          ? ' 1 Game Day entry stays; manage it in Game Day settings.'
          : ' $gameDaySkipped Game Day entries stay; manage those in Game '
              'Day settings.');
    }
    if (overflow > 0) {
      b.write(' I can remove up to $kEntryDeleteMaxPerRequest at a time; '
          '$overflow more match. Ask again afterwards for the rest.');
    }
    return b.toString();
  }

  /// One line per entry: "Fri, Nov 20 · Chiefs Game Night".
  List<String> get lines => [
        for (final e in entries)
          '${formatEntryDeleteDate(e.dateKey)} · ${e.displayName}',
      ];
}

/// The outcome of [resolveEntryDeletion].
class EntryDeleteResolution {
  final EntryDeleteResolutionKind kind;

  /// Set for [EntryDeleteResolutionKind.propose].
  final EntryDeleteProposal? proposal;

  /// The sentence to post for every other kind.
  final String reply;

  const EntryDeleteResolution._(this.kind, this.proposal, this.reply);

  const EntryDeleteResolution.propose(EntryDeleteProposal proposal)
      : this._(EntryDeleteResolutionKind.propose, proposal, '');

  const EntryDeleteResolution.reply(EntryDeleteResolutionKind kind, String text)
      : this._(kind, null, text);
}

/// True when Lumina may remove [e] on the customer's confirmation.
bool isEntryDeletableByLumina(CalendarEntry e) {
  if (e.type == CalendarEntryType.holiday) return false;
  if (e.holdsGameDay) return false;
  if (e.sourceTag == CalendarEntrySourceTag.luminaAi) return true;
  return e.type == CalendarEntryType.user && e.sourceTag == null;
}

/// Resolve the model's description against the calendar. [today] bounds
/// "everything you created" (today and later) and nothing else.
EntryDeleteResolution resolveEntryDeletion(
  EntryDeleteIntent intent,
  Iterable<CalendarEntry> calendar, {
  required DateTime today,
}) {
  if (intent.target == EntryDeleteTarget.recurring) {
    return const EntryDeleteResolution.reply(
        EntryDeleteResolutionKind.recurringRefused,
        kEntryDeleteRecurringRefused);
  }

  switch (intent.scope) {
    case EntryDeleteScope.unclear:
      return const EntryDeleteResolution.reply(
          EntryDeleteResolutionKind.unclear, kEntryDeleteUnclear);

    case EntryDeleteScope.luminaAll:
      final todayKey = dateKeyOf(today);
      final mine = calendar
          .where((e) =>
              e.sourceTag == CalendarEntrySourceTag.luminaAi &&
              isEntryDeletableByLumina(e) &&
              e.dateKey.compareTo(todayKey) >= 0 &&
              _nameMatches(e, intent.nameFilter))
          .toList();
      const label = 'that I created';
      if (mine.isEmpty) {
        return EntryDeleteResolution.reply(EntryDeleteResolutionKind.nothing,
            _nothingReply(label, intent.nameFilter, gameDay: 0));
      }
      return EntryDeleteResolution.propose(_capped(mine, label));

    case EntryDeleteScope.date:
    case EntryDeleteScope.range:
      final from = intent.scope == EntryDeleteScope.date
          ? intent.date!
          : intent.startDate!;
      final to = intent.scope == EntryDeleteScope.date
          ? intent.date!
          : intent.endDate!;
      final label = from == to
          ? 'on ${formatEntryDeleteDate(from)}'
          : 'from ${formatEntryDeleteDate(from, weekday: false)} to '
              '${formatEntryDeleteDate(to, weekday: false)}';

      final inWindow = calendar
          .where((e) =>
              e.type != CalendarEntryType.holiday &&
              e.dateKey.compareTo(from) >= 0 &&
              e.dateKey.compareTo(to) <= 0)
          .toList();
      final gameDay = inWindow.where((e) => e.holdsGameDay).length;
      final deletable = inWindow
          .where((e) =>
              isEntryDeletableByLumina(e) && _nameMatches(e, intent.nameFilter))
          .toList();
      final auto = inWindow.length - gameDay - deletable.length;

      if (deletable.isEmpty) {
        if (gameDay > 0 && auto == 0 && intent.nameFilter == null) {
          return const EntryDeleteResolution.reply(
              EntryDeleteResolutionKind.gameDayRefused,
              kEntryDeleteGameDayRefused);
        }
        return EntryDeleteResolution.reply(EntryDeleteResolutionKind.nothing,
            _nothingReply(label, intent.nameFilter, gameDay: gameDay));
      }
      return EntryDeleteResolution.propose(
          _capped(deletable, label, gameDay: gameDay, auto: auto));
  }
}

/// The reply after a confirmed Delete: how many went, or how many did not.
String entryDeleteOutcomeText({required int requested, required int deleted}) {
  if (deleted == requested) {
    return deleted == 1 ? 'Deleted 1 entry.' : 'Deleted $deleted entries.';
  }
  final failed = requested - deleted;
  return 'Deleted $deleted of $requested entries; $failed '
      "couldn't be removed. Check your connection and try again.";
}

EntryDeleteProposal _capped(
  List<CalendarEntry> matched,
  String label, {
  int gameDay = 0,
  int auto = 0,
}) {
  matched.sort((a, b) {
    final d = a.dateKey.compareTo(b.dateKey);
    if (d != 0) return d;
    final t = (a.onTime ?? '').compareTo(b.onTime ?? '');
    if (t != 0) return t;
    return a.entryId.compareTo(b.entryId);
  });
  final kept = matched.take(kEntryDeleteMaxPerRequest).toList();
  return EntryDeleteProposal(
    entries: kept,
    scopeLabel: label,
    gameDaySkipped: gameDay,
    autoSkipped: auto,
    overflow: matched.length - kept.length,
  );
}

String _nothingReply(String label, String? nameFilter, {required int gameDay}) {
  final b = StringBuffer(nameFilter == null
      ? "I couldn't find any entries to delete $label."
      : "I couldn't find an entry called \"$nameFilter\" $label.");
  if (gameDay > 0) {
    b.write(gameDay == 1
        ? ' The Game Day entry there stays; manage it in Game Day settings.'
        : ' The $gameDay Game Day entries there stay; manage those in Game '
            'Day settings.');
  }
  return b.toString();
}

bool _nameMatches(CalendarEntry e, String? filter) {
  if (filter == null) return true;
  final f = filter.toLowerCase();
  return e.patternName.toLowerCase().contains(f) ||
      e.displayName.toLowerCase().contains(f);
}

const _kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _kMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `YYYY-MM-DD` for [d], the calendar's key form.
String dateKeyOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// "Fri, Nov 20" (or "Nov 20" without the weekday). An unparseable key is
/// shown as given rather than hidden.
String formatEntryDeleteDate(String dateKey, {bool weekday = true}) {
  final d = DateTime.tryParse(dateKey);
  if (d == null) return dateKey;
  final md = '${_kMonths[d.month - 1]} ${d.day}';
  return weekday ? '${_kWeekdays[d.weekday - 1]}, $md' : md;
}
