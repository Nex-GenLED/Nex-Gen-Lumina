// +110 package E2, item 3 — "give me a chiefs design with motion right now"
// must compose a Chiefs design, in the team's LED colours, with an animated
// effect, from BOTH Lumina surfaces.
//
// The phrase table below runs every phrasing through the real Tier 0
// composition (LuminaBrain.composeTeamResponse), the real reply parser
// (CloudAIProcessor.parseAiResponseForTest) and the real conversation driver
// on both host kinds. It also records, per phrase, what the PRE-fix gate
// (hasExplicitSportsKeyword) said, so the report can show which phrasings
// failed before.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_dispatcher.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_intent.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_conversation_driver.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_flags.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_persistence.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/recurring_sports_autopilot_intent.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
import 'package:nexgen_command/shared/write_result.dart';

// ---------------------------------------------------------------------------
// The phrase table
// ---------------------------------------------------------------------------

class _Phrase {
  const _Phrase(this.text,
      {required this.team, required this.motion, this.solid = false});
  final String text;

  /// The `UnifiedTeamEntry.id` the phrase must resolve to.
  final String team;

  /// Whether the phrase asks for motion.
  final bool motion;

  /// D5 — whether the phrase must come back Solid (fx 0): a negated motion
  /// word, "static"/"still", or a bare "TEAM colors". A phrase that is
  /// neither [motion] nor [solid] keeps the team's own default effect.
  final bool solid;
}

const _phrases = <_Phrase>[
  // The device report, verbatim.
  _Phrase('give me a chiefs design with motion right now',
      team: 'chiefs', motion: true),
  // Team-name variants.
  _Phrase('chiefs design with motion', team: 'chiefs', motion: true),
  _Phrase('KC Chiefs design with motion', team: 'chiefs', motion: true),
  _Phrase('Kansas City Chiefs design with motion',
      team: 'chiefs', motion: true),
  _Phrase('give me the Chiefs with motion', team: 'chiefs', motion: true),
  _Phrase('a design for the chiefs, moving', team: 'chiefs', motion: true),
  // Motion words.
  _Phrase('chiefs design, moving', team: 'chiefs', motion: true),
  _Phrase('animated chiefs design', team: 'chiefs', motion: true),
  _Phrase('chiefs design with movement', team: 'chiefs', motion: true),
  _Phrase('chiefs colors, make it move', team: 'chiefs', motion: true),
  _Phrase('chiefs chase', team: 'chiefs', motion: true),
  // Immediacy.
  _Phrase('chiefs design right now', team: 'chiefs', motion: false),
  _Phrase('chiefs design now', team: 'chiefs', motion: false),
  _Phrase('give me a chiefs design now with motion',
      team: 'chiefs', motion: true),
  // Static.
  _Phrase('chiefs design', team: 'chiefs', motion: false),
  _Phrase('give me a chiefs look', team: 'chiefs', motion: false),
  // Other teams, other leagues.
  _Phrase('give me a royals design with motion', team: 'royals', motion: true),
  _Phrase('Kansas City Royals design, animated', team: 'royals', motion: true),
  _Phrase('lakers design with motion right now', team: 'lakers', motion: true),
  _Phrase('give me the LA Lakers with movement', team: 'lakers', motion: true),
  _Phrase('bruins design, make it move', team: 'bruins', motion: true),
  _Phrase('Boston Bruins colors with motion', team: 'bruins', motion: true),
  _Phrase('sporting kc design with motion', team: 'sporting_kc', motion: true),
  _Phrase('yankees design with motion', team: 'yankees', motion: true),
  _Phrase('New York Yankees design right now', team: 'yankees', motion: false),
  // D5 — the review's item 4 table, with the decided results.
  _Phrase('chiefs colors', team: 'chiefs', motion: false, solid: true),
  _Phrase('chiefs design, no motion', team: 'chiefs', motion: false, solid: true),
  _Phrase('chiefs design without motion',
      team: 'chiefs', motion: false, solid: true),
  _Phrase('chiefs, not moving', team: 'chiefs', motion: false, solid: true),
  _Phrase('chiefs static', team: 'chiefs', motion: false, solid: true),
  // D5 — the new negations.
  _Phrase('chiefs design, no movement',
      team: 'chiefs', motion: false, solid: true),
  _Phrase("chiefs design, don't move", team: 'chiefs', motion: false, solid: true),
  _Phrase('chiefs colors, still', team: 'chiefs', motion: false, solid: true),
  _Phrase('keep the chiefs colors still',
      team: 'chiefs', motion: false, solid: true),
  _Phrase('give me the chiefs, no animation',
      team: 'chiefs', motion: false, solid: true),
  _Phrase('chiefs colours', team: 'chiefs', motion: false, solid: true),
  _Phrase('royals colors', team: 'royals', motion: false, solid: true),
  _Phrase('lakers colors, no motion', team: 'lakers', motion: false, solid: true),
  // D5 — a motion word with "colors" is still motion; "design"/"look" with no
  // motion word keeps the default.
  _Phrase('chiefs colors with motion', team: 'chiefs', motion: true),
  _Phrase('chiefs look', team: 'chiefs', motion: false),
];

/// Phrases that must NOT be taken for a team request.
const _notTeams = <String>[
  'fire effect on the roofline',
  'give me a warm white glow',
  'blue and gold chase',
  'something with heat and movement',
  'red green and white for christmas',
];

// ---------------------------------------------------------------------------
// Driver fakes (the same shape as lumina_conversation_driver_test.dart)
// ---------------------------------------------------------------------------

class _Posted {
  const _Posted(this.text, this.preview, this.wled);
  final String text;
  final LuminaPatternPreview? preview;
  final Map<String, dynamic>? wled;
}

class _Thread implements LuminaThread {
  final List<_Posted> posted = [];
  final List<String> user = [];
  @override
  void addUserMessage(String text) => user.add(text);
  @override
  void updateTranscription(String text) {}
  @override
  void addAssistantMessage(String text,
          {LuminaPatternPreview? preview, Map<String, dynamic>? wledPayload}) =>
      posted.add(_Posted(text, preview, wledPayload));
}

class _Services implements LuminaConversationServices {
  _Services(this.result);
  final LuminaCommandResult result;
  final _Thread thread = _Thread();
  final List<Map<String, dynamic>> applied = [];
  final List<String> labels = [];
  final List<LuminaPatternPreview> metadata = [];

  @override
  LuminaThread openThread() => thread;
  @override
  Future<LuminaCommandResult> route(String prompt) async => result;
  @override
  bool get hasDevice => true;
  @override
  Future<WriteResult> applyToDevice(Map<String, dynamic> payload) async {
    applied.add(payload);
    return const WriteResult.success();
  }

  @override
  void setPatternMetadata(LuminaPatternPreview preview) => metadata.add(preview);
  @override
  void setActiveLabel(String label) => labels.add(label);
  @override
  void clearActiveLabel() {}
  @override
  String get displayPatternName => 'Now Playing';
  @override
  String? get currentUserId => 'u';
  @override
  Future<DispatchResult> dispatchEphemeralSession(
          EphemeralSessionIntent intent, String userId) =>
      throw UnimplementedError();
  @override
  Future<void> dispatchRecurringSportsAutopilot(
          {required RecurringSportsAutopilotIntent intent,
          required LuminaCommandResult result,
          VoidCallback? onMessagePosted}) =>
      throw UnimplementedError();
  @override
  Future<void> dispatchSchedulingIntents(
          {required List<SchedulingIntent> intents,
          required LuminaCommandResult result,
          required LuminaPatternPreview? preview,
          VoidCallback? onMessagePosted}) =>
      throw UnimplementedError();
  @override
  Future<ScheduleNightsOutcome> persistScheduleNights(
          LuminaScheduleFlags flags) async =>
      ScheduleNightsOutcome.nothingToPersist;
  @override
  Future<WriteResult> saveFavorite(
          {required String patternName,
          required Map<String, dynamic> wledPayload}) async =>
      const WriteResult.success();
  @override
  void selectTab(int tabIndex) {}
  @override
  void syncAdjustmentPanel(
      {required String responseText,
      required LuminaPatternPreview preview,
      Map<String, dynamic>? wledPayload}) {}
}

LuminaConversationHost _host(LuminaSurface surface, List<String> log) =>
    LuminaConversationHost(
      surface: surface,
      isMounted: () => true,
      clearInput: () => log.add('clear'),
      onUserMessagePosted:
          surface == LuminaSurface.sheet ? () => log.add('expand') : null,
      scrollToEnd: () => log.add('scroll'),
      closeSurface: () => log.add('close'),
      goRoute: (r) => log.add('go:$r'),
      pushRoute: (r) => log.add('push:$r'),
      showSnackBar: (m) => log.add('snack:$m'),
    );

UnifiedTeamEntry _team(String id) =>
    TeamColorDatabase.allTeams.firstWhere((t) => t.id == id);

List<List<int>> _segColors(Map<String, dynamic> wled) {
  final seg = (wled['seg'] as List).first as Map;
  return (seg['col'] as List)
      .map((c) => (c as List).map((n) => (n as num).toInt()).toList())
      .toList();
}

void main() {
  group('the pre-fix gate (for the record)', () {
    test('never matched a bare team name — that was the bug', () {
      final missed = <String>[];
      for (final p in _phrases) {
        if (!LuminaBrain.hasExplicitSportsKeyword(p.text)) missed.add(p.text);
      }
      // Every phrase without a sports KEYWORD (team, nfl, game day…) fell
      // through to the cloud and was rejected on the way back.
      expect(missed, contains('give me a chiefs design with motion right now'));
      expect(missed.length, greaterThanOrEqualTo(20),
          reason: 'the old gate missed almost the whole table: $missed');
    });
  });

  group('isSportsRequest', () {
    for (final p in _phrases) {
      test('recognises "${p.text}"', () {
        expect(LuminaBrain.isSportsRequest(p.text), isTrue);
      });
    }
    for (final text in _notTeams) {
      test('does not take "$text" for a team', () {
        expect(LuminaBrain.isSportsRequest(text), isFalse);
      });
    }
  });

  group('composeTeamResponse', () {
    for (final p in _phrases) {
      test('"${p.text}" → ${p.team}${p.motion ? ', animated' : ''}', () {
        final response = LuminaBrain.composeTeamResponse(p.text);
        expect(response, isNotNull, reason: 'fell through to the cloud');

        final result = CloudAIProcessor.parseAiResponseForTest(response!, p.text);
        final wled = result.wledPayload;
        expect(wled, isNotNull);

        // The team's LED colours (ledOptimizedRgb), never the brand hex.
        final team = _team(p.team);
        final expected = [
          for (final rgb in team.ledOptimizedRgb) [rgb[0], rgb[1], rgb[2], 0],
        ];
        expect(_segColors(wled!), expected,
            reason: 'colours must come from the LED table');
        expect(result.responseText, contains(team.officialName));

        final seg = (wled['seg'] as List).first as Map;
        if (p.motion) {
          expect(seg['fx'], isNot(0), reason: 'motion was asked for');
          expect((wled['effect'] as Map)['isStatic'], isFalse);
        } else if (p.solid) {
          // D5 — a negated motion word, "static"/"still", or a bare
          // "<team> colors" is Solid.
          expect(seg['fx'], 0, reason: 'no motion was asked for');
          expect((wled['effect'] as Map)['isStatic'], isTrue);
        } else {
          // "<team> design" / "<team> look" keep the team's own default
          // (Theater Chase for most teams) — the decided behaviour.
          expect(seg['fx'], team.suggestedEffects.first,
              reason: 'no motion word: the team default stands');
        }
        // No manufactured swatches: the colours ARE the payload's.
        expect(result.previewColors.length, team.colors.length);
      });
    }

    group('D5 — motion words and their negations', () {
      test('a negated motion word is not a motion ask', () {
        expect(LuminaBrain.wantsMotion('chiefs design, no motion'), isFalse);
        expect(LuminaBrain.asksStatic('chiefs design, no motion'), isTrue);
        expect(LuminaBrain.wantsMotion('chiefs design with motion'), isTrue);
        expect(LuminaBrain.asksStatic('chiefs design with motion'), isFalse);
        for (final s in const [
          'chiefs without motion',
          'chiefs, not moving',
          'chiefs design, no movement',
          "chiefs, don't move",
          'chiefs static',
          'chiefs colors, still',
        ]) {
          expect(LuminaBrain.asksStatic(s), isTrue, reason: s);
          expect(LuminaBrain.wantsMotion(s), isFalse, reason: s);
        }
      });

      test('"colors" alone is Solid; "colors, make it move" is not', () {
        expect(LuminaBrain.asksColorsOnly('chiefs colors'), isTrue);
        expect(LuminaBrain.asksColorsOnly('royals colours'), isTrue);
        expect(LuminaBrain.asksColorsOnly('chiefs colors, make it move'), isFalse);
        expect(LuminaBrain.asksColorsOnly('chiefs colors with motion'), isFalse);
        expect(LuminaBrain.asksColorsOnly('chiefs design'), isFalse);
      });
    });

    test('a static ask keeps the team\'s own first suggestion', () {
      final r = LuminaBrain.composeTeamResponse('chiefs design')!;
      final result = CloudAIProcessor.parseAiResponseForTest(r, 'chiefs design');
      final seg = (result.wledPayload!['seg'] as List).first as Map;
      expect(seg['fx'], _team('chiefs').suggestedEffects.first);
    });

    test('"solid" stays solid unless motion is asked for', () {
      final r = LuminaBrain.composeTeamResponse('chiefs solid colors')!;
      final result =
          CloudAIProcessor.parseAiResponseForTest(r, 'chiefs solid colors');
      expect((result.wledPayload!['seg'] as List).first['fx'], 0);
      final m = LuminaBrain.composeTeamResponse('chiefs solid colors with motion')!;
      final moving = CloudAIProcessor.parseAiResponseForTest(
          m, 'chiefs solid colors with motion');
      expect((moving.wledPayload!['seg'] as List).first['fx'], isNot(0));
    });
  });

  group('item 3d — sheet and full screen behave identically', () {
    for (final p in _phrases) {
      test('"${p.text}"', () async {
        final response = LuminaBrain.composeTeamResponse(p.text)!;
        final result = CloudAIProcessor.parseAiResponseForTest(response, p.text);

        final outcomes = <LuminaSurface, _Services>{};
        final logs = <LuminaSurface, List<String>>{};
        for (final surface in LuminaSurface.values) {
          final services = _Services(result);
          final log = <String>[];
          final driver = LuminaConversationDriver(
              host: _host(surface, log), services: services);
          await driver.send(p.text);
          outcomes[surface] = services;
          logs[surface] = log;
        }

        final sheet = outcomes[LuminaSurface.sheet]!;
        final screen = outcomes[LuminaSurface.screen]!;
        // Applied live, once, with the same payload.
        expect(sheet.applied, [result.wledPayload]);
        expect(screen.applied, sheet.applied);
        // Same reply, same preview, same label.
        expect(screen.thread.posted.single.text, sheet.thread.posted.single.text);
        expect(screen.thread.posted.single.preview!.colors,
            sheet.thread.posted.single.preview!.colors);
        expect(screen.labels, sheet.labels);
        // The one surface difference is the sheet growing before it scrolls.
        expect(logs[LuminaSurface.sheet], ['clear', 'expand', 'scroll', 'scroll']);
        expect(logs[LuminaSurface.screen], ['clear', 'scroll', 'scroll']);
      });
    }
  });

  group('item 3e — a miss says what was not understood', () {
    test('names the unknown words and the known ones', () {
      final text = LuminaBrain.describeMisunderstanding(
          'give me a red zorblax design with motion');
      expect(text, contains('"zorblax"'));
      expect(text, contains('"red"'));
      expect(text, contains('"motion"'));
      expect(text, isNot(contains('describe the colors or mood')));
    });

    test('nothing recognisable → says so, without inventing', () {
      final text = LuminaBrain.describeMisunderstanding('give me a zorblax');
      expect(text, startsWith("I didn't recognise \"zorblax\""));
    });
  });
}
