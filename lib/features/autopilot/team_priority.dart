// lib/features/autopilot/team_priority.dart
//
// THE one place that maps between the two shapes of a user's team ordering.
//
// A user's Game Day teams have always been ordered — `sports_team_priority` on
// the profile, reorderable in Edit Profile, captioned "the top team takes
// priority". That list holds DISPLAY NAMES ("Kansas City Chiefs"), because it
// predates the slug-keyed `game_day_autopilot` subcollection and is also
// consumed by surfaces that only ever had a name (the Interests card, the
// installer handoff, `gameDayTeamsProvider`'s membership filter).
//
// The arbiter needs SLUGS: `GameDayPriorityResolver` ranks a candidate by
// `teamPriority.indexOf(candidate.teamSlug)`, and a config document's id IS the
// slug. Handing the resolver the names list makes every `indexOf` return -1, so
// every team ranks last and the resolver silently degrades to
// first-come-first-served. That is exactly the state the 2026-09-21 audit found
// (`audit/gameday-game-selection-2026-09-21`, Step 3).
//
// So there are two fields, deliberately, and this module owns the translation:
//
//   • `sports_team_priority`  — ordered display names. UNCHANGED shape; every
//                               existing reader keeps working.
//   • `game_day_team_priority` — ordered slugs. NEW. What the arbiter reads.
//
// Both are written together by every reorder path, from one derivation, so the
// two can never disagree about the order. See [alignPriorityLists].
//
// HEAL-ON-READ, NOT A BULK BACKFILL. No production account has the slug field
// yet. [healGameDayTeamPriority] derives it from what the account already has,
// and the caller writes the result back to THAT USER'S OWN document the next
// time they open Game Day — the same lazy shape the pixel-map heal uses. There
// is no admin sweep and no cross-account write.

import '../sports_alerts/data/team_colors.dart';

/// One row of the ordering, carrying both shapes so a reorder can write both
/// fields from a single user gesture.
///
/// [slug] is null only for a legacy free-text profile entry that matches no
/// catalogue team — `sports_teams` was unvalidated for a long time, and the
/// fleet still carries values like "Kansas City Sporting Kansas City". Those
/// rows still render and still reorder; they simply contribute nothing to the
/// slug list, because there is no team for them to rank.
class TeamPriorityEntry {
  final String? slug;
  final String displayName;

  const TeamPriorityEntry({required this.slug, required this.displayName});

  @override
  bool operator ==(Object other) =>
      other is TeamPriorityEntry &&
      other.slug == slug &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(slug, displayName);

  @override
  String toString() => 'TeamPriorityEntry($displayName, slug=$slug)';
}

/// Case/whitespace-insensitive key for a team display name.
///
/// Matches the normalisation `TeamRegistrationService._stripTeamFromProfile`
/// and `unified_monitoring._profileKey` already use, so a name this module
/// considers equal is exactly one those paths would have considered equal.
String teamNameKey(String teamName) => teamName.trim().toLowerCase();

/// Reverse [kTeamColors]: display name → slug. Case-insensitive.
///
/// Returns null for a name no catalogue team carries. Built once, lazily — the
/// catalogue is a 449-entry compile-time const, so a linear scan per lookup
/// would be wasteful on a list that is re-derived on every profile stream tick.
String? slugForTeamName(String teamName) {
  _nameToSlug ??= {
    for (final e in kTeamColors.entries) teamNameKey(e.value.teamName): e.key,
  };
  return _nameToSlug![teamNameKey(teamName)];
}

Map<String, String>? _nameToSlug;

/// Display name for a slug, or the slug itself when it is not in the
/// catalogue (which should not happen — configs are created from [kTeamColors]
/// — but a rendered row must never be blank).
String teamNameForSlug(String slug) => kTeamColors[slug]?.teamName ?? slug;

/// Derive the slug ordering for an account that has never had one.
///
/// This is the heal. It runs against the CURRENT USER's own data only, and the
/// caller writes the result back to that user's own document.
///
/// Inputs:
///   [storedSlugs]  — whatever `game_day_team_priority` already holds (empty on
///                    a first run; non-empty on later runs, and then it is the
///                    authority for the teams it names).
///   [profileNames] — `sports_team_priority`, the ordered display names the
///                    user has actually arranged. This is the ORDER to honour.
///   [configSlugs]  — the slugs of the account's `game_day_autopilot` documents.
///                    Firestore hands these back in document-id order, which is
///                    the order the populate loop and the evaluate loop already
///                    walk, so passing them in that order makes the appended
///                    tail deterministic and matches what the user sees today.
///
/// Rules, in order:
///   1. Keep [storedSlugs] that still have a config, in their stored order.
///      An explicit ordering the user has already set is never re-derived.
///   2. Append [profileNames] translated to slugs, in profile order, skipping
///      any already present. A name that matches no catalogue team is dropped
///      (there is nothing to rank), and so is a slug with no config — the team
///      was removed, and ranking a team that cannot play is meaningless.
///   3. Append any remaining [configSlugs] not yet listed, in the order given.
///      This covers the accounts whose profile array drifted from their configs
///      (three in production as of 2026-09-22) — a team with a config but no
///      profile row ranks last rather than vanishing.
///
/// Pure. Returns the healed list; compare with [storedSlugs] to decide whether
/// a write is owed — see [priorityNeedsHeal].
List<String> healGameDayTeamPriority({
  required List<String> storedSlugs,
  required List<String> profileNames,
  required List<String> configSlugs,
}) {
  final configSet = configSlugs.toSet();
  final out = <String>[];
  final seen = <String>{};

  void add(String? slug) {
    if (slug == null) return;
    if (!configSet.contains(slug)) return; // no config ⇒ nothing to rank
    if (!seen.add(slug)) return;
    out.add(slug);
  }

  for (final s in storedSlugs) {
    add(s);
  }
  for (final n in profileNames) {
    add(slugForTeamName(n));
  }
  for (final s in configSlugs) {
    add(s);
  }
  return out;
}

/// True when [healGameDayTeamPriority] would change what is stored.
///
/// Order matters, so this is an element-wise comparison, not a set comparison:
/// a user who drags their #2 team to #1 must produce a write.
bool priorityNeedsHeal({
  required List<String> storedSlugs,
  required List<String> healedSlugs,
}) {
  if (storedSlugs.length != healedSlugs.length) return true;
  for (var i = 0; i < storedSlugs.length; i++) {
    if (storedSlugs[i] != healedSlugs[i]) return true;
  }
  return false;
}

/// Build the rows a reorder control renders, from the slug ordering plus the
/// profile's name list.
///
/// Slug-backed rows come first, in slug-priority order — that is the ordering
/// the arbiter actually uses, so it is the ordering the user must see. Legacy
/// name-only rows (no catalogue match) are appended after them so they stay
/// visible and removable rather than silently disappearing from the screen
/// that owns them.
List<TeamPriorityEntry> buildPriorityEntries({
  required List<String> slugPriority,
  required List<String> profileNames,
}) {
  final out = <TeamPriorityEntry>[];
  final usedNames = <String>{};

  for (final slug in slugPriority) {
    final name = teamNameForSlug(slug);
    out.add(TeamPriorityEntry(slug: slug, displayName: name));
    usedNames.add(teamNameKey(name));
  }
  for (final n in profileNames) {
    final key = teamNameKey(n);
    if (key.isEmpty) continue;
    if (usedNames.contains(key)) continue;
    // A name already covered by a slug row above is skipped by `usedNames`;
    // what reaches here is either a legacy free-text entry or a team whose
    // config was removed. Either way it keeps its row and no slug.
    usedNames.add(key);
    out.add(TeamPriorityEntry(slug: slugForTeamName(n), displayName: n));
  }
  return out;
}

/// The two field values a reorder must write, derived from one ordered row
/// list so the screens cannot drift.
///
/// `names` keeps EVERY row, including legacy name-only ones — dropping them
/// here would quietly delete a team from the profile array as a side effect of
/// a drag. `slugs` keeps only the rows that have one.
({List<String> names, List<String> slugs}) alignPriorityLists(
  List<TeamPriorityEntry> entries,
) {
  final names = <String>[];
  final slugs = <String>[];
  final seenNames = <String>{};
  final seenSlugs = <String>{};
  for (final e in entries) {
    final key = teamNameKey(e.displayName);
    if (key.isNotEmpty && seenNames.add(key)) names.add(e.displayName);
    final slug = e.slug;
    if (slug != null && seenSlugs.add(slug)) slugs.add(slug);
  }
  return (names: names, slugs: slugs);
}

/// Order configs so the HIGHEST-priority team is considered FIRST.
///
/// The twin of [orderConfigsForCalendarWrite], and deliberately its opposite:
/// arbitration wants the winner first, lease-primacy wants the winner last.
/// Both take the same hierarchy; confusing them would silently invert the
/// outcome, which is why they live side by side with this note.
///
/// Why the evaluate loop needs it at all. Resolution is per-config, and the
/// loop walks Firestore document-id order. Given two teams whose windows open
/// on the SAME tick, the lower-priority one would be resolved first against an
/// empty field, activate, apply its design — and only then would the #1 team
/// be resolved, preempt it, and apply over the top. The end state is right but
/// the house visibly flashes the wrong team's colours first, and two writes go
/// to the controller where one was needed. Considering the hierarchy in order
/// means the #1 team activates first and everyone else simply defers.
///
/// Unranked teams sort last, keeping their relative input order. Stable.
List<T> orderConfigsByPriority<T>(
  List<T> configs,
  List<String> teamPriority,
  String Function(T) slugOf,
) {
  final rankOf = <String, int>{
    for (var i = 0; i < teamPriority.length; i++) teamPriority[i]: i,
  };
  final indexed = <({T config, int rank, int order})>[
    for (var i = 0; i < configs.length; i++)
      (
        config: configs[i],
        rank: rankOf[slugOf(configs[i])] ?? teamPriority.length,
        order: i,
      ),
  ];
  indexed.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    return a.order.compareTo(b.order);
  });
  return [for (final e in indexed) e.config];
}

/// Order configs so the HIGHEST-priority team is written LAST.
///
/// Why last, and not first. The calendar lease registry is keyed by `dateKey`
/// and holds exactly one lease per night (`calendar_entry_lease_manager.dart`
/// "STILL ONE ENTRY PER DATE, DELIBERATELY"), and `CalendarEntrySet.primaries`
/// hands back the LAST-written entry for a date. So on a night two teams share,
/// whichever team writes last owns the WLED timer. Writing in reverse priority
/// makes that the #1 team instead of whichever slug happens to sort later.
///
/// This deliberately does NOT live in `computeEnabledConfigsForTeam`. That
/// function answers "which teams participate in this populate pass", including
/// splicing a just-toggled team in past Firestore stream lag, and it puts that
/// team LAST for freshness reasons that have nothing to do with lease primacy
/// (`game_day_multi_team_test.dart` pins that contract). Ordering for primacy
/// is a separate question asked later, at the write, by this function — so
/// neither rule has to know about the other.
///
/// Unranked teams (not in [teamPriority]) sort as lowest priority and therefore
/// write FIRST, keeping their relative input order. The sort is stable.
List<T> orderConfigsForCalendarWrite<T>(
  List<T> configs,
  List<String> teamPriority,
  String Function(T) slugOf,
) {
  final rankOf = <String, int>{
    for (var i = 0; i < teamPriority.length; i++) teamPriority[i]: i,
  };
  final indexed = <({T config, int rank, int order})>[
    for (var i = 0; i < configs.length; i++)
      (
        config: configs[i],
        rank: rankOf[slugOf(configs[i])] ?? teamPriority.length,
        order: i,
      ),
  ];
  indexed.sort((a, b) {
    // Descending rank number = ascending priority, so #1 lands last.
    final byRank = b.rank.compareTo(a.rank);
    if (byRank != 0) return byRank;
    return a.order.compareTo(b.order); // stable within a rank
  });
  return [for (final e in indexed) e.config];
}
