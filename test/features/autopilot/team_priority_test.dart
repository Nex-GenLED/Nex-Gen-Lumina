// test/features/autopilot/team_priority_test.dart
//
// The heal, the two-field alignment, and the calendar write order.
//
// The heal runs unsupervised against real accounts the first time each one
// opens Game Day, and there is no bulk backfill to inspect afterwards — so
// the production shapes the 2026-09-22 audit found are pinned here as cases:
// a names-only list (18 of 18 accounts), a list entry matching no config
// (1 account), and configs missing from the list (3 accounts).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/team_priority.dart';

void main() {
  group('slugForTeamName', () {
    test('maps a catalogue display name to its slug', () {
      expect(slugForTeamName('Kansas City Chiefs'), 'nfl_chiefs');
      expect(slugForTeamName('Kansas City Royals'), 'mlb_royals');
    });

    test('is case- and whitespace-insensitive, matching the profile-array '
        'normalisation the add/remove paths already use', () {
      expect(slugForTeamName('  kansas city chiefs '), 'nfl_chiefs');
      expect(slugForTeamName('KANSAS CITY CHIEFS'), 'nfl_chiefs');
    });

    test('returns null for a legacy free-text entry', () {
      // A real production value, from the account the audit found.
      expect(slugForTeamName('Kansas City Sporting Kansas City'), isNull);
      expect(slugForTeamName(''), isNull);
    });
  });

  group('healGameDayTeamPriority', () {
    test('names-only account: derives the slug order from the names the user '
        'arranged — the shape of every production account on 2026-09-22', () {
      final healed = healGameDayTeamPriority(
        storedSlugs: const [],
        profileNames: const ['Kansas City Chiefs', 'Kansas City Royals'],
        configSlugs: const ['mlb_royals', 'nfl_chiefs'], // doc-id order
      );
      // Profile order wins over doc-id order. This is the whole point: doc-id
      // order is what the loop used to obey, and it is what put Royals first
      // for a user who ranked Chiefs first.
      expect(healed, ['nfl_chiefs', 'mlb_royals']);
    });

    test('a stored slug order is authoritative and is NOT re-derived', () {
      final healed = healGameDayTeamPriority(
        storedSlugs: const ['mlb_royals', 'nfl_chiefs'],
        profileNames: const ['Kansas City Chiefs', 'Kansas City Royals'],
        configSlugs: const ['mlb_royals', 'nfl_chiefs'],
      );
      expect(healed, ['mlb_royals', 'nfl_chiefs']);
    });

    test('a name matching no catalogue team is dropped', () {
      final healed = healGameDayTeamPriority(
        storedSlugs: const [],
        profileNames: const [
          'Kansas City Sporting Kansas City', // legacy free text
          'Kansas City Chiefs',
        ],
        configSlugs: const ['nfl_chiefs'],
      );
      expect(healed, ['nfl_chiefs']);
    });

    test('a name whose team has no config is dropped — ranking a team that '
        'cannot play is meaningless', () {
      final healed = healGameDayTeamPriority(
        storedSlugs: const [],
        profileNames: const ['Kansas City Chiefs', 'Kansas City Royals'],
        configSlugs: const ['nfl_chiefs'],
      );
      expect(healed, ['nfl_chiefs']);
    });

    test('a config missing from the profile list is appended last, not lost '
        '(3 production accounts have this drift)', () {
      final healed = healGameDayTeamPriority(
        storedSlugs: const [],
        profileNames: const ['Kansas City Chiefs'],
        configSlugs: const ['mls_sporting_kc', 'nfl_chiefs'],
      );
      expect(healed, ['nfl_chiefs', 'mls_sporting_kc']);
    });

    test('a stale stored slug whose config is gone is dropped', () {
      final healed = healGameDayTeamPriority(
        storedSlugs: const ['nhl_blues', 'nfl_chiefs'],
        profileNames: const ['Kansas City Chiefs'],
        configSlugs: const ['nfl_chiefs'],
      );
      expect(healed, ['nfl_chiefs']);
    });

    test('duplicates collapse, keeping the earliest position', () {
      final healed = healGameDayTeamPriority(
        storedSlugs: const ['nfl_chiefs'],
        profileNames: const ['Kansas City Chiefs', 'Kansas City Royals'],
        configSlugs: const ['mlb_royals', 'nfl_chiefs'],
      );
      expect(healed, ['nfl_chiefs', 'mlb_royals']);
    });

    test('no teams at all yields an empty list, not a crash', () {
      expect(
        healGameDayTeamPriority(
          storedSlugs: const [],
          profileNames: const [],
          configSlugs: const [],
        ),
        isEmpty,
      );
    });

    test('is idempotent — healing a healed list changes nothing, which is '
        'what stops the heal-on-read write from looping', () {
      const names = ['Kansas City Chiefs', 'Kansas City Royals'];
      const configs = ['mlb_royals', 'nfl_chiefs'];
      final once = healGameDayTeamPriority(
        storedSlugs: const [],
        profileNames: names,
        configSlugs: configs,
      );
      final twice = healGameDayTeamPriority(
        storedSlugs: once,
        profileNames: names,
        configSlugs: configs,
      );
      expect(twice, once);
      expect(priorityNeedsHeal(storedSlugs: once, healedSlugs: twice), isFalse);
    });
  });

  group('priorityNeedsHeal', () {
    test('detects a reorder, not just a membership change — dragging #2 to #1 '
        'must produce a write', () {
      expect(
        priorityNeedsHeal(
          storedSlugs: const ['nfl_chiefs', 'mlb_royals'],
          healedSlugs: const ['mlb_royals', 'nfl_chiefs'],
        ),
        isTrue,
      );
    });

    test('identical lists need no write', () {
      expect(
        priorityNeedsHeal(
          storedSlugs: const ['nfl_chiefs'],
          healedSlugs: const ['nfl_chiefs'],
        ),
        isFalse,
      );
    });

    test('a length change needs a write', () {
      expect(
        priorityNeedsHeal(
          storedSlugs: const ['nfl_chiefs'],
          healedSlugs: const ['nfl_chiefs', 'mlb_royals'],
        ),
        isTrue,
      );
    });
  });

  group('buildPriorityEntries', () {
    test('slug rows come first, in arbiter order', () {
      final rows = buildPriorityEntries(
        slugPriority: const ['nfl_chiefs', 'mlb_royals'],
        profileNames: const ['Kansas City Royals', 'Kansas City Chiefs'],
      );
      expect(rows.map((e) => e.slug), ['nfl_chiefs', 'mlb_royals']);
      expect(rows.first.displayName, 'Kansas City Chiefs');
    });

    test('a legacy name-only team keeps a row so it stays removable', () {
      final rows = buildPriorityEntries(
        slugPriority: const ['nfl_chiefs'],
        profileNames: const [
          'Kansas City Chiefs',
          'Kansas City Sporting Kansas City',
        ],
      );
      expect(rows, hasLength(2));
      expect(rows.last.slug, isNull);
      expect(rows.last.displayName, 'Kansas City Sporting Kansas City');
    });

    test('a name already represented by a slug row is not duplicated', () {
      final rows = buildPriorityEntries(
        slugPriority: const ['nfl_chiefs'],
        profileNames: const ['kansas city chiefs'], // different casing
      );
      expect(rows, hasLength(1));
    });
  });

  group('alignPriorityLists', () {
    test('one gesture produces both field values in the same order', () {
      final aligned = alignPriorityLists(const [
        TeamPriorityEntry(slug: 'mlb_royals', displayName: 'Kansas City Royals'),
        TeamPriorityEntry(slug: 'nfl_chiefs', displayName: 'Kansas City Chiefs'),
      ]);
      expect(aligned.slugs, ['mlb_royals', 'nfl_chiefs']);
      expect(aligned.names, ['Kansas City Royals', 'Kansas City Chiefs']);
    });

    test('a legacy row survives in names and contributes no slug — a drag '
        'must never delete a team as a side effect', () {
      final aligned = alignPriorityLists(const [
        TeamPriorityEntry(slug: 'nfl_chiefs', displayName: 'Kansas City Chiefs'),
        TeamPriorityEntry(slug: null, displayName: 'Kansas City Sporting Kansas City'),
      ]);
      expect(aligned.names, hasLength(2));
      expect(aligned.slugs, ['nfl_chiefs']);
    });

    test('duplicates are collapsed in both outputs', () {
      final aligned = alignPriorityLists(const [
        TeamPriorityEntry(slug: 'nfl_chiefs', displayName: 'Kansas City Chiefs'),
        TeamPriorityEntry(slug: 'nfl_chiefs', displayName: 'kansas city chiefs'),
      ]);
      expect(aligned.slugs, ['nfl_chiefs']);
      expect(aligned.names, ['Kansas City Chiefs']);
    });
  });

  group('orderConfigsForCalendarWrite', () {
    String slugOf(String s) => s;

    test('the #1 team writes LAST, so it owns the one lease a shared night '
        'has', () {
      final ordered = orderConfigsForCalendarWrite(
        ['mlb_royals', 'nfl_chiefs'], // doc-id order
        const ['nfl_chiefs', 'mlb_royals'], // priority
        slugOf,
      );
      expect(ordered.last, 'nfl_chiefs');
    });

    test('reversing the hierarchy reverses the write order — this is the '
        'proof that priority, not slug order, decides', () {
      final ordered = orderConfigsForCalendarWrite(
        ['mlb_royals', 'nfl_chiefs'],
        const ['mlb_royals', 'nfl_chiefs'],
        slugOf,
      );
      expect(ordered.last, 'mlb_royals');
    });

    test('unranked teams write first and keep their relative order', () {
      final ordered = orderConfigsForCalendarWrite(
        ['nhl_blues', 'wnba_fever', 'nfl_chiefs'],
        const ['nfl_chiefs'],
        slugOf,
      );
      expect(ordered, ['nhl_blues', 'wnba_fever', 'nfl_chiefs']);
    });

    test('an empty hierarchy preserves input order exactly — no hierarchy '
        'means no reordering, not an arbitrary one', () {
      final input = ['mlb_royals', 'nfl_chiefs', 'wnba_fever'];
      expect(
        orderConfigsForCalendarWrite(input, const [], slugOf),
        input,
      );
    });

    test('a single team is unaffected', () {
      expect(
        orderConfigsForCalendarWrite(
            ['nfl_chiefs'], const ['nfl_chiefs'], slugOf),
        ['nfl_chiefs'],
      );
    });

    test('seven enabled teams (the production maximum) order correctly', () {
      final ordered = orderConfigsForCalendarWrite(
        [
          'mlb_royals',
          'mls_sporting_kc',
          'nba_pacers',
          'ncaa_missouri',
          'nfl_chiefs',
          'nwsl_kc_current',
          'wnba_fever',
        ],
        const [
          'nfl_chiefs',
          'mls_sporting_kc',
          'nwsl_kc_current',
          'nba_pacers',
          'wnba_fever',
          'ncaa_missouri',
          'mlb_royals',
        ],
        slugOf,
      );
      expect(ordered.last, 'nfl_chiefs');
      expect(ordered.first, 'mlb_royals');
    });
  });
}
