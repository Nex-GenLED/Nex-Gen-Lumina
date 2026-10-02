// lib/features/game_day/game_day_run_mode.dart
//
// +114 (plan §3.4, app half) — WHO runs this home's Game Day, in three states.
//
//   SERVER   `gameday_server` says served, with a fresh heartbeat. The lights
//            change with the app closed; the next fire is named.
//   PHONE    everything else — not allowlisted, pre-flight skipped, a stale
//            heartbeat, a status that has not loaded. The lights change when
//            the app is open at home (and a lease can turn them on at kickoff).
//            When the account IS allowlisted but pre-flight held it back, the
//            reason is shown so the customer (or dealer) can fix it.
//   BLOCKED  allowlisted, and the readiness gate is blocking. Only meaningful
//            when the server path is in play; for a phone-run home the gate
//            changes nothing, so it is never shown there (the old banner told
//            phone-run homes "not firing yet", which was wrong in both
//            directions).
//
// PURE: no providers, no widgets. The banner and the badges call these.

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/utils/time_format.dart';

enum GameDayRunMode { server, phone, blocked }

/// PURE. The account's mode, or one team's when [teamSlug] is given (the
/// server serves per team, D2).
GameDayRunMode gameDayRunModeFor({
  required GameDayServerStatus status,
  required GateStatus gate,
  required DateTime now,
  String? teamSlug,
}) {
  final served = teamSlug == null
      ? status.servedAt(now)
      : status.servesTeamAt(teamSlug, now);
  if (served) return GameDayRunMode.server;
  if (status.allowlisted && !gate.armed) return GameDayRunMode.blocked;
  return GameDayRunMode.phone;
}

@immutable
class GameDayRunCopy {
  final String title;
  final List<String> lines;
  const GameDayRunCopy(this.title, this.lines);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "today 2:55 PM", "tomorrow 7:15 PM", "Sun 12:00 PM".
String gameDayWhen(DateTime at, DateTime now, {String timeFormat = '12h'}) {
  final local = at.toLocal();
  final hhmm = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final time = formatTimeLabel(hhmm, timeFormat: timeFormat);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'today $time';
  if (diff == 1) return 'tomorrow $time';
  return '${_weekdays[local.weekday - 1]} $time';
}

String _names(List<String> names) {
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// PURE. What the banner says for [mode].
///
/// [teamName] maps a slug to the customer's name for the team;
/// [enabledTeamSlugs] are the account's Game Day teams, so a SERVER home with a
/// team the server does not run (D2 — e.g. a per-pixel saved design the server
/// refuses) is told which games still need the phone.
GameDayRunCopy gameDayRunCopy({
  required GameDayRunMode mode,
  required GameDayServerStatus status,
  required GateStatus gate,
  required DateTime now,
  required String Function(String slug) teamName,
  List<String> enabledTeamSlugs = const [],
  String timeFormat = '12h',
}) {
  switch (mode) {
    case GameDayRunMode.server:
      final phoneTeams = [
        for (final s in enabledTeamSlugs)
          if (!status.servesTeamAt(s, now)) teamName(s),
      ];
      final next = status.nextFire;
      final last = status.lastFire;
      return GameDayRunCopy('Game Day runs from our servers', [
        'Your lights change for the game even with the app closed.',
        if (phoneTeams.isNotEmpty)
          '${_names(phoneTeams)} still ${phoneTeams.length == 1 ? 'runs' : 'run'} '
              'from this phone: keep the app open at home for '
              '${phoneTeams.length == 1 ? 'that game' : 'those games'}.',
        if (next != null && next.seq == 'start')
          'Next: ${next.teamSlug == null ? 'your team' : teamName(next.teamSlug!)}, '
              '${gameDayWhen(next.fireAt, now, timeFormat: timeFormat)}.',
        if (next != null && next.seq == 'end')
          '${next.teamSlug == null ? 'Your team\'s' : '${teamName(next.teamSlug!)}\'s'} '
              'game is on. Your lights go back to normal after the final.',
        if (last != null && last.completed && last.completedAt != null)
          'Last change: ${gameDayWhen(last.completedAt!, now, timeFormat: timeFormat)}'
              '${last.latencyMs == null ? '' : ', ${(last.latencyMs! / 1000).round()} s after it was due'}.',
      ]);
    case GameDayRunMode.phone:
      final pf = status.preflight;
      final reasons = <String>[
        if (pf != null && !pf.ok && !pf.observeOnly)
          for (final r in pf.reasons)
            if (preflightReasonCopy(r) != null) preflightReasonCopy(r)!,
      ];
      return GameDayRunCopy('Game Day runs from this phone', [
        'Your lights change for the game when the Lumina app is open at home.',
        if (status.staleAt(now))
          'Our servers have not checked in for a while, so this phone is '
              'running Game Day for now.',
        ...reasons,
      ]);
    case GameDayRunMode.blocked:
      return GameDayRunCopy(gate.headline, gate.reasons);
  }
}

/// The badge text for an UPCOMING game on a team card. Live and final games
/// are reports of fact and are never relabelled.
String upcomingBadgeLabel(GameDayRunMode mode) => switch (mode) {
      GameDayRunMode.server => 'Today · server',
      GameDayRunMode.phone => 'Today · phone',
      GameDayRunMode.blocked => kGatedBadgeLabel,
    };

/// The short tag a Game Day row on a day timeline carries.
String runModeTag(GameDayRunMode mode) => switch (mode) {
      GameDayRunMode.server => 'server',
      GameDayRunMode.phone => 'phone',
      GameDayRunMode.blocked => 'setup needed',
    };
