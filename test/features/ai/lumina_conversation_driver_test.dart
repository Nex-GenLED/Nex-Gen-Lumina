// test/features/ai/lumina_conversation_driver_test.dart
//
// Branch tests for the ONE Lumina conversation driver, run against both host
// kinds (sheet and full screen). The driver touches the surface only through
// LuminaConversationHost and the rest of the app only through
// LuminaConversationServices, so every branch is driven here with recording
// fakes — no widget pump, no Riverpod container, no Firebase.
//
// +110 package E2 rewrote the outcome-dependent branches: rows 74, 105, 106,
// 109, 112 and item 4 (multi-night persistence). The tests that pinned the
// old behaviour "on purpose" are replaced by the new contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_dispatcher.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_intent.dart';
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_conversation_driver.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_flags.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_persistence.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/recurring_sports_autopilot_intent.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
import 'package:nexgen_command/shared/write_result.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _PostedMessage {
  final String text;
  final LuminaPatternPreview? preview;
  final Map<String, dynamic>? wledPayload;
  const _PostedMessage(this.text, this.preview, this.wledPayload);
}

class _FakeThread implements LuminaThread {
  final List<String> userMessages = [];
  final List<String> transcriptions = [];
  final List<_PostedMessage> assistantMessages = [];

  @override
  void addUserMessage(String text) => userMessages.add(text);

  @override
  void updateTranscription(String text) => transcriptions.add(text);

  @override
  void addAssistantMessage(
    String text, {
    LuminaPatternPreview? preview,
    Map<String, dynamic>? wledPayload,
  }) =>
      assistantMessages.add(_PostedMessage(text, preview, wledPayload));
}

class _FakeServices implements LuminaConversationServices {
  final _FakeThread thread = _FakeThread();

  // Inputs
  LuminaCommandResult? routed;
  Object? routeError;
  @override
  bool hasDevice = true;

  /// What [applyToDevice] answers. Defaults to success; a test sets a
  /// blocked or failed result to drive the failure branches.
  WriteResult applyResult = const WriteResult.success();
  Object? applyError;
  @override
  String? currentUserId = 'user-under-test';
  @override
  String displayPatternName = 'Now Playing';
  DispatchResult? dispatchResult;
  ScheduleNightsOutcome? nightsOutcome;
  Object? persistError;
  WriteResult favoriteResult = const WriteResult.success(message: 'Saved');

  // Recorded calls
  final List<String> routedPrompts = [];
  final List<Map<String, dynamic>> applied = [];
  final List<LuminaPatternPreview> metadata = [];
  final List<String> labels = [];
  int labelClears = 0;
  final List<LuminaScheduleFlags> persisted = [];
  final List<int> selectedTabs = [];
  final List<EphemeralSessionIntent> dispatchedEphemeral = [];
  final List<RecurringSportsAutopilotIntent> dispatchedSports = [];
  final List<List<SchedulingIntent>> dispatchedIntents = [];
  final List<LuminaPatternPreview?> intentPreviews = [];
  final List<LuminaPatternPreview> panelSyncs = [];
  final List<(String, Map<String, dynamic>)> savedFavorites = [];

  @override
  LuminaThread openThread() => thread;

  @override
  Future<LuminaCommandResult> route(String prompt) async {
    routedPrompts.add(prompt);
    if (routeError != null) throw routeError!;
    return routed!;
  }

  @override
  Future<WriteResult> applyToDevice(Map<String, dynamic> payload) async {
    if (!hasDevice) {
      return const WriteResult.blocked(
          'No controller is set up yet. Add your controller in Settings to '
          'control your lights.');
    }
    applied.add(payload);
    if (applyError != null) throw applyError!;
    return applyResult;
  }

  @override
  void setPatternMetadata(LuminaPatternPreview preview) =>
      metadata.add(preview);

  @override
  void setActiveLabel(String label) => labels.add(label);

  @override
  void clearActiveLabel() => labelClears++;

  @override
  Future<DispatchResult> dispatchEphemeralSession(
    EphemeralSessionIntent intent,
    String userId,
  ) async {
    dispatchedEphemeral.add(intent);
    return dispatchResult!;
  }

  @override
  Future<void> dispatchRecurringSportsAutopilot({
    required RecurringSportsAutopilotIntent intent,
    required LuminaCommandResult result,
    VoidCallback? onMessagePosted,
  }) async {
    dispatchedSports.add(intent);
    onMessagePosted?.call();
  }

  @override
  Future<void> dispatchSchedulingIntents({
    required List<SchedulingIntent> intents,
    required LuminaCommandResult result,
    required LuminaPatternPreview? preview,
    VoidCallback? onMessagePosted,
  }) async {
    dispatchedIntents.add(intents);
    intentPreviews.add(preview);
    onMessagePosted?.call();
  }

  @override
  Future<ScheduleNightsOutcome> persistScheduleNights(
      LuminaScheduleFlags flags) async {
    persisted.add(flags);
    if (persistError != null) throw persistError!;
    return nightsOutcome ??
        ScheduleNightsOutcome(
            requested: flags.schedule.length,
            persisted: flags.schedule.length);
  }

  @override
  Future<WriteResult> saveFavorite({
    required String patternName,
    required Map<String, dynamic> wledPayload,
  }) async {
    savedFavorites.add((patternName, wledPayload));
    return favoriteResult;
  }

  @override
  void selectTab(int tabIndex) => selectedTabs.add(tabIndex);

  @override
  void syncAdjustmentPanel({
    required String responseText,
    required LuminaPatternPreview preview,
    Map<String, dynamic>? wledPayload,
  }) =>
      panelSyncs.add(preview);
}

/// Records every host callback in call order.
class _HostLog {
  final LuminaSurface surface;
  bool mounted = true;
  final List<String> calls = [];

  _HostLog(this.surface);

  LuminaConversationHost get host => LuminaConversationHost(
        surface: surface,
        isMounted: () => mounted,
        clearInput: () => calls.add('clearInput'),
        // Only the sheet grows on send — the full screen passes nothing.
        onUserMessagePosted: surface == LuminaSurface.sheet
            ? () => calls.add('expand')
            : null,
        scrollToEnd: () => calls.add('scroll'),
        closeSurface: () => calls.add('close'),
        goRoute: (route) => calls.add('go:$route'),
        pushRoute: (route) => calls.add('push:$route'),
        showSnackBar: (message) => calls.add('snack:$message'),
      );
}

class _Rig {
  final _FakeServices services = _FakeServices();
  final _HostLog log;
  late final LuminaConversationDriver driver =
      LuminaConversationDriver(host: log.host, services: services);

  _Rig(LuminaSurface surface) : log = _HostLog(surface);

  _FakeThread get thread => services.thread;

  Future<LuminaResultBranch> handle(
    LuminaCommandResult result, {
    String prompt = 'prompt under test',
  }) =>
      driver.handleResult(result, prompt: prompt, thread: thread);
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _designWled = <String, dynamic>{
  'on': true,
  'bri': 200,
  'patternName': 'Royal Blue Wash',
  'seg': [
    {
      'fx': 0,
      'col': [
        [0, 70, 255, 0],
      ],
    },
  ],
};

const _refused = WriteResult.failed(WriteFailureKind.unreachable,
    message: "Couldn't reach your lights — check your connection");

Map<String, dynamic> _night(int index, int fx) => {
      'dayIndex': index,
      'date': DateTime(2026, 12, 20 + index).toIso8601String(),
      'patternName': 'Christmas night ${index + 1}',
      'effectId': fx,
      'effectName': ['Twinkle', 'Breathe', 'Running'][index % 3],
      'startTrigger': 'sunset',
      'endTrigger': 'sunrise',
      'wled': {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
            ],
          },
        ],
      },
    };

LuminaCommandResult _scheduleResult({int nights = 3}) => LuminaCommandResult(
      responseText: "I've scheduled $nights nights of Christmas colors.",
      wledPayload: const {
        'on': true,
        'patternName': 'Christmas — 3-Night Schedule',
        'seg': [
          {
            'fx': 43,
            'col': [
              [255, 0, 0, 0],
            ],
          },
        ],
      },
      tier: ProcessingTier.cloud,
      scheduleFlags: LuminaScheduleFlags.fromResponseJson({
        'isSchedule': true,
        'scheduleType': 'multi_day',
        'dayCount': nights,
        'hasVariety': true,
        'patternName': 'Christmas — $nights-Night Schedule',
        'themeName': 'Christmas',
        'startTrigger': 'sunset',
        'endTrigger': 'sunrise',
        'schedule': [for (int i = 0; i < nights; i++) _night(i, 43 + i)],
      }),
    );

LuminaCommandResult _navigate(Map<String, dynamic> parameters) =>
    LuminaCommandResult(
      command: LuminaCommand(
        type: LuminaCommandType.navigate,
        parameters: parameters,
        confidence: 0.95,
        rawText: 'open it',
      ),
      responseText: 'Opening that now.',
    );

LuminaCommandResult _power({required bool on}) => LuminaCommandResult(
      command: LuminaCommand(
        type: LuminaCommandType.power,
        parameters: {'on': on},
        confidence: 0.98,
        rawText: on ? 'turn on' : 'turn off',
      ),
      responseText: on ? 'Turning your lights on.' : 'Turning your lights off.',
      wledPayload: {'on': on},
    );

const _ephemeralJson = <String, dynamic>{
  'type': 'post_game_revert',
  'teamSlug': 'team_under_test',
  'gameAnchor': {'type': 'tonight'},
  'revertWledPayload': {'on': true},
  'revertLabel': 'Warm White',
};

DispatchResult _dispatch({
  List<String> sessionIds = const [],
  List<String> labels = const [],
  String? noGameFoundMessage,
  String? errorMessage,
}) =>
    DispatchResult(
      createdSessionIds: sessionIds,
      sessionLabels: labels,
      teamDisplayName: 'Team Under Test',
      revertLabel: 'Warm White',
      noGameFoundMessage: noGameFoundMessage,
      success: errorMessage == null,
      errorMessage: errorMessage,
    );

void main() {
  // Every branch runs on both host kinds — the point of one driver.
  for (final surface in LuminaSurface.values) {
    group('on the ${surface.name}', () {
      late _Rig rig;
      setUp(() => rig = _Rig(surface));

      // ── Schedule branch (UX audit row 7 / item 4) ───────────────────────

      group('schedule branch', () {
        test('fires for a result carrying the flags', () async {
          final branch = await rig.handle(_scheduleResult(nights: 3));

          expect(branch, LuminaResultBranch.schedule);
        });

        test('applies night 1, persists every night, labels, posts honestly',
            () async {
          final result = _scheduleResult(nights: 3);
          await rig.handle(result);

          // Night 1 is the live apply.
          expect(rig.services.applied.length, 1);
          expect(
              (rig.services.applied.single['seg'] as List).first['fx'], 43);

          // The whole plan goes to the calendar.
          expect(rig.services.persisted.length, 1);
          expect(rig.services.persisted.single.schedule.length, 3);

          expect(rig.services.labels, ['Christmas — 3-Night Schedule']);

          expect(rig.thread.assistantMessages.length, 1);
          final posted = rig.thread.assistantMessages.single;
          // Not the plan's own "I've scheduled 3 nights" prose — a reply
          // composed from what happened.
          expect(posted.text, isNot(result.responseText));
          expect(posted.text,
              contains("Tonight's Christmas look is on your lights now."));
          expect(posted.text, contains('other 2 nights are in your Schedule'));
          expect(posted.preview, isNotNull);
          expect(posted.preview!.colors.first, const Color(0xFFFF0000));
          expect(posted.wledPayload, result.wledPayload);

          expect(rig.log.calls, ['scroll']);
        });

        test('fires end to end from a parsed reply', () async {
          const response = "I've scheduled 2 nights of Christmas colors. "
              '{"patternName":"Christmas — 2-Night Schedule",'
              '"wled":{"on":true,"seg":[{"fx":43,"col":[[255,0,0,0]]}]},'
              '"isSchedule":true,"scheduleType":"multi_day","dayCount":2,'
              '"hasVariety":true,"schedule":['
              '{"dayIndex":0,"date":"2026-12-24T00:00:00.000","effectId":43,'
              '"wled":{"on":true,"seg":[{"fx":43,"col":[[255,0,0,0]]}]}},'
              '{"dayIndex":1,"date":"2026-12-25T00:00:00.000","effectId":2,'
              '"wled":{"on":true,"seg":[{"fx":2,"col":[[0,255,0,0]]}]}}]}';
          final parsed = CloudAIProcessor.parseAiResponseForTest(
              response, 'christmas tonight and tomorrow');

          final branch = await rig.handle(parsed);

          expect(branch, LuminaResultBranch.schedule);
          expect(rig.services.persisted.single.schedule.length, 2);
        });

        test('takes precedence over an ephemeral session on the same reply',
            () async {
          final flagged = _scheduleResult();
          final result = LuminaCommandResult(
            responseText: flagged.responseText,
            wledPayload: flagged.wledPayload,
            scheduleFlags: flagged.scheduleFlags,
            ephemeralSession: _ephemeralJson,
          );

          expect(await rig.handle(result), LuminaResultBranch.schedule);
          expect(rig.services.dispatchedEphemeral, isEmpty);
        });

        test('with no device: the reply says tonight did not land, the '
            'nights still persist', () async {
          rig.services.hasDevice = false;

          await rig.handle(_scheduleResult());

          expect(rig.services.applied, isEmpty);
          expect(rig.services.persisted.length, 1);
          expect(rig.services.labels, isEmpty);
          final text = rig.thread.assistantMessages.single.text;
          expect(text, startsWith("I couldn't put tonight's Christmas look"));
          expect(text, contains('No controller is set up yet.'));
          expect(text, contains('other 2 nights are in your Schedule'));
        });

        test('nights that could not be saved: only tonight, said plainly',
            () async {
          rig.services.nightsOutcome = const ScheduleNightsOutcome(
              requested: 3, persisted: 0, message: 'sign in first.');

          await rig.handle(_scheduleResult());

          final text = rig.thread.assistantMessages.single.text;
          expect(text, contains('Only tonight was applied'));
          expect(text, contains('sign in first.'));
          expect(text, isNot(contains("I've scheduled")));
        });

        test('a persistence that throws is reported, not claimed', () async {
          rig.services.persistError = StateError('firestore down');

          await rig.handle(_scheduleResult());

          expect(rig.thread.assistantMessages.single.text,
              contains('Only tonight was applied'));
        });

        test('a night-1 apply that throws does not stop the persistence',
            () async {
          rig.services.applyError = StateError('controller unreachable');

          await rig.handle(_scheduleResult());

          expect(rig.services.persisted.length, 1);
          final text = rig.thread.assistantMessages.single.text;
          expect(text, startsWith("I couldn't put tonight's Christmas look"));
          expect(text, contains('other 2 nights are in your Schedule'));
        });

        test('flags with NO plan (season_fill) fall through to the apply',
            () async {
          final result = LuminaCommandResult(
            responseText: 'Christmas all month.',
            wledPayload: _designWled,
            scheduleFlags: LuminaScheduleFlags.fromResponseJson(const {
              'isSchedule': true,
              'scheduleType': 'season_fill',
              'seasonId': 'christmas_season',
            }),
          );

          final branch = await rig.handle(result);

          // Same as before the flags were carried: the design is applied.
          expect(branch, LuminaResultBranch.apply);
          expect(rig.services.applied, [_designWled]);
          expect(rig.services.persisted, isEmpty);
        });
      });

      // ── Navigation ──────────────────────────────────────────────────────

      group('navigation branch', () {
        test('a tab index closes the surface and switches tab', () async {
          final branch =
              await rig.handle(_navigate({'route': '/settings', 'tabIndex': 3}));

          expect(branch, LuminaResultBranch.navigation);
          expect(rig.log.calls, ['close']);
          expect(rig.services.selectedTabs, [3]);
          expect(rig.thread.assistantMessages.single.text, 'Opening that now.');
        });

        test('a nested /dashboard route uses go()', () async {
          await rig.handle(_navigate({'route': '/dashboard/my-designs'}));

          expect(rig.log.calls, ['close', 'go:/dashboard/my-designs']);
        });

        test('a route outside the shell uses push()', () async {
          await rig.handle(_navigate({'route': '/my-scenes'}));

          expect(rig.log.calls, ['close', 'push:/my-scenes']);
        });

        test('an unmounted surface is closed but not navigated', () async {
          rig.log.mounted = false;

          await rig.handle(_navigate({'route': '/my-scenes'}));

          expect(rig.log.calls, ['close']);
          expect(rig.thread.assistantMessages.length, 1);
        });
      });

      // ── Plain apply ─────────────────────────────────────────────────────

      group('apply branch', () {
        const result = LuminaCommandResult(
          responseText: 'Applying Royal Blue Wash now.',
          wledPayload: _designWled,
        );

        test('applies, records what is playing, posts the reply', () async {
          final branch = await rig.handle(result);

          expect(branch, LuminaResultBranch.apply);
          expect(rig.services.applied, [_designWled]);
          expect(rig.services.metadata.length, 1);
          expect(rig.services.labels, ['Royal Blue Wash']);
          expect(rig.thread.assistantMessages.single.text,
              'Applying Royal Blue Wash now.');
          expect(rig.services.panelSyncs.length, 1);
        });

        test('row 74: a refused apply posts the failure, not the prose',
            () async {
          rig.services.applyResult = _refused;

          await rig.handle(result);

          expect(rig.services.metadata, isEmpty);
          expect(rig.services.labels, isEmpty);
          final text = rig.thread.assistantMessages.single.text;
          expect(text, isNot('Applying Royal Blue Wash now.'));
          expect(text, startsWith("I couldn't apply that"));
          expect(text, contains("Couldn't reach your lights"));
          // The card keeps the design so it can be retried.
          expect(rig.thread.assistantMessages.single.wledPayload, _designWled);
        });

        test('row 74: no device → the shared reason, no completion prose',
            () async {
          rig.services.hasDevice = false;

          await rig.handle(result);

          expect(rig.services.applied, isEmpty);
          final text = rig.thread.assistantMessages.single.text;
          expect(text, contains('No controller is set up yet.'));
          expect(text, isNot(contains('Applying')));
        });

        test('row 74: "turn off" that went nowhere is not "Turning your '
            'lights off."', () async {
          rig.services.hasDevice = false;

          await rig.handle(_power(on: false));

          final text = rig.thread.assistantMessages.single.text;
          expect(text, startsWith("I couldn't turn your lights off"));
        });

        test('an apply that throws is a failure reply, not a crash',
            () async {
          rig.services.applyError = StateError('controller unreachable');

          await rig.handle(result);

          expect(rig.services.labels, isEmpty);
          expect(rig.thread.assistantMessages.single.text,
              startsWith("I couldn't apply that"));
        });

        test('row 112: a power command leaves Now Playing alone', () async {
          await rig.handle(_power(on: true));

          expect(rig.services.applied, [
            {'on': true}
          ]);
          expect(rig.services.labels, isEmpty);
          expect(rig.services.labelClears, 0);
          expect(rig.services.metadata, isEmpty);
          // No manufactured swatches: no preview at all.
          expect(rig.thread.assistantMessages.single.preview, isNull);
          expect(rig.thread.assistantMessages.single.text,
              'Turning your lights on.');
        });

        test('no pattern name → the label is built from the prompt words',
            () async {
          await rig.handle(
            const LuminaCommandResult(
              responseText: 'Here you go.',
              wledPayload: {
                'on': true,
                'seg': [
                  {
                    'fx': 0,
                    'col': [
                      [255, 0, 0, 0],
                    ],
                  },
                ],
              },
            ),
            prompt: 'porch party red',
          );

          expect(rig.services.labels, ['Porch Party Red']);
        });

        test('a text-only reply applies nothing and shows no card', () async {
          final branch = await rig
              .handle(const LuminaCommandResult(responseText: 'Happy to help.'));

          expect(branch, LuminaResultBranch.apply);
          expect(rig.services.applied, isEmpty);
          expect(rig.thread.assistantMessages.single.preview, isNull);
          expect(rig.services.panelSyncs, isEmpty);
        });

        test('preview colors alone still build a card', () async {
          await rig.handle(const LuminaCommandResult(
            responseText: 'Something like this?',
            previewColors: [Color(0xFF00FF00)],
          ));

          expect(rig.services.applied, isEmpty);
          expect(rig.thread.assistantMessages.single.preview!.colors,
              const [Color(0xFF00FF00)]);
        });
      });

      // ── Ephemeral session ───────────────────────────────────────────────

      group('ephemeral session branch', () {
        const result = LuminaCommandResult(
          responseText: 'Team colors tonight, back to warm white after.',
          wledPayload: _designWled,
          ephemeralSession: _ephemeralJson,
        );

        test('applies the design and appends the revert confirmation',
            () async {
          rig.services.dispatchResult = _dispatch(
            sessionIds: const ['session-1'],
            labels: const ['Team Under Test — 7:00 PM'],
          );

          final branch = await rig.handle(result);

          expect(branch, LuminaResultBranch.ephemeralSession);
          expect(rig.services.applied, [_designWled]);
          expect(rig.services.dispatchedEphemeral.length, 1);
          expect(
            rig.thread.assistantMessages.single.text,
            'Team colors tonight, back to warm white after.\n\n'
            '✓ Will revert to Warm White when Team Under Test — 7:00 PM ends.',
          );
          // This branch has never scrolled — kept as found.
          expect(rig.log.calls, isEmpty);
        });

        test('row 109: a failed dispatch says the revert was not set',
            () async {
          rig.services.dispatchResult =
              _dispatch(errorMessage: 'service unavailable');

          await rig.handle(result);

          final text = rig.thread.assistantMessages.single.text;
          expect(text, startsWith('Team colors tonight, back to warm white after.'));
          expect(text, contains("I couldn't set the post-game revert"));
        });

        test('row 109: signed out says the revert was not set', () async {
          rig.services.currentUserId = null;

          await rig.handle(result);

          expect(rig.services.dispatchedEphemeral, isEmpty);
          expect(rig.thread.assistantMessages.single.text,
              contains("I couldn't set the post-game revert — sign in"));
        });

        test('row 105: the no-game sentence reflects a refused apply',
            () async {
          rig.services.applyResult = _refused;
          rig.services.dispatchResult = _dispatch(
            noGameFoundMessage:
                "There's no game tonight, but I've applied the colors anyway.",
          );

          await rig.handle(result);

          final text = rig.thread.assistantMessages.single.text;
          expect(text, isNot(contains("I've applied the colors anyway")));
          expect(text, contains("I couldn't apply the colors"));
          expect(text, contains("Couldn't reach your lights"));
        });

        test('row 105: the no-game sentence keeps "applied anyway" when it '
            'did apply', () async {
          rig.services.dispatchResult = _dispatch(
            noGameFoundMessage:
                "There's no game tonight, but I've applied the colors anyway.",
          );

          await rig.handle(result);

          expect(rig.thread.assistantMessages.single.text,
              contains("I've applied the colors anyway."));
        });

        test('an unmounted surface posts nothing', () async {
          rig.services.dispatchResult = _dispatch(
            sessionIds: const ['session-1'],
            labels: const ['Team Under Test — 7:00 PM'],
          );
          rig.log.mounted = false;

          await rig.handle(result);

          expect(rig.thread.assistantMessages, isEmpty);
        });
      });

      // ── Shared handlers ─────────────────────────────────────────────────

      test('recurring sports autopilot goes to the shared handler', () async {
        final branch = await rig.handle(const LuminaCommandResult(
          responseText: 'Every game, all season.',
          recurringSportsAutopilot: {'teamSlug': 'team_under_test'},
        ));

        expect(branch, LuminaResultBranch.recurringSportsAutopilot);
        expect(rig.services.dispatchedSports.single.teamSlug,
            'team_under_test');
        expect(rig.services.applied, isEmpty);
        expect(rig.log.calls, ['scroll']);
      });

      test('scheduling intents go to the shared handler with a preview',
          () async {
        final intent = SchedulingIntent.fromJson({
          'action': 'add',
          'timeLabel': 'Sunset',
          'offTimeLabel': 'Sunrise',
          'repeatDays': ['Fri'],
          'patternName': 'Royal Blue Wash',
        });

        final branch = await rig.handle(LuminaCommandResult(
          responseText: 'Every Friday at sunset.',
          wledPayload: _designWled,
          schedulingIntents: [intent],
        ));

        expect(branch, LuminaResultBranch.schedulingIntents);
        expect(rig.services.dispatchedIntents.single, [intent]);
        expect(rig.services.intentPreviews.single, isNotNull);
        // The schedule is a proposal — nothing is applied now.
        expect(rig.services.applied, isEmpty);
      });

      // ── Send ────────────────────────────────────────────────────────────

      group('send', () {
        test('a blank message does nothing', () async {
          await rig.driver.send('   ');

          expect(rig.log.calls, isEmpty);
          expect(rig.thread.userMessages, isEmpty);
          expect(rig.services.routedPrompts, isEmpty);
        });

        test('posts the trimmed prompt, routes it and scrolls', () async {
          rig.services.routed =
              const LuminaCommandResult(responseText: 'Happy to help.');

          await rig.driver.send('  hello lumina  ');

          expect(rig.thread.userMessages, ['hello lumina']);
          expect(rig.thread.transcriptions, ['']);
          expect(rig.services.routedPrompts, ['hello lumina']);
          expect(rig.thread.assistantMessages.single.text, 'Happy to help.');
          // The one surface difference: the sheet grows before it scrolls.
          expect(
            rig.log.calls,
            surface == LuminaSurface.sheet
                ? ['clearInput', 'expand', 'scroll', 'scroll']
                : ['clearInput', 'scroll', 'scroll'],
          );
        });

        test('a pipeline failure posts the snag message, without internals',
            () async {
          rig.services.routeError = StateError('offline');

          await rig.driver.send('warm white');

          final text = rig.thread.assistantMessages.single.text;
          expect(text, startsWith('I hit a snag'));
          expect(text, isNot(contains('offline')));
          expect(rig.log.calls.last, 'scroll');
        });

        test('reaches the schedule branch', () async {
          rig.services.routed = _scheduleResult(nights: 3);

          await rig.driver.send('christmas for the next three nights');

          expect(rig.services.persisted.length, 1);
          expect(rig.thread.assistantMessages.length, 1);
        });
      });

      // ── Bubble-tap apply ────────────────────────────────────────────────

      group('applyFromBubble', () {
        test('applies, labels and confirms with a snackbar', () async {
          await rig.driver.applyFromBubble(_designWled, null,
              originalPrompt: 'royal blue');

          expect(rig.services.applied, [_designWled]);
          expect(rig.services.labels, ['Royal Blue Wash']);
          expect(rig.log.calls, ['snack:Now Playing applied!']);
        });

        test('a refused apply shows why', () async {
          rig.services.applyResult = _refused;

          await rig.driver.applyFromBubble(_designWled, null);

          expect(rig.services.labels, isEmpty);
          expect(rig.log.calls,
              ["snack:Couldn't reach your lights — check your connection"]);
        });

        test('no device: nothing is sent, the reason is shown', () async {
          rig.services.hasDevice = false;

          await rig.driver.applyFromBubble(_designWled, null);

          expect(rig.services.applied, isEmpty);
          expect(rig.log.calls.single, startsWith('snack:No controller'));
        });
      });

      // ── Save as favourite (row 106) ─────────────────────────────────────

      group('saveFavorite', () {
        test('saves the device payload under the design name and says so',
            () async {
          final result = await rig.driver.saveFavorite(
            _designWled,
            const LuminaPatternPreview(
                patternName: 'Royal Blue Wash', colors: [Color(0xFF0046FF)]),
          );

          expect(result.ok, isTrue);
          final (name, payload) = rig.services.savedFavorites.single;
          expect(name, 'Royal Blue Wash');
          // Device keys only — no Lumina display metadata.
          expect(payload.keys, containsAll(['on', 'bri', 'seg']));
          expect(payload.containsKey('patternName'), isFalse);
          expect(rig.log.calls, ['snack:Saved']);
        });

        test('a failed save says so', () async {
          rig.services.favoriteResult = const WriteResult.failed(
              WriteFailureKind.error, message: "Couldn't save that");

          final result = await rig.driver.saveFavorite(_designWled, null,
              originalPrompt: 'royal blue');

          expect(result.ok, isFalse);
          expect(rig.log.calls, ["snack:Couldn't save that"]);
        });
      });
    });
  }

  group('helpers', () {
    test('luminaFavoriteId is stable for the same design', () {
      expect(luminaFavoriteId(_designWled), luminaFavoriteId(_designWled));
      expect(luminaFavoriteId(_designWled), startsWith('lumina_'));
    });

    test('extractLuminaPreview: no colours → no preview (row 112)', () {
      expect(extractLuminaPreview(const {'on': true}), isNull);
      expect(extractLuminaPreview(const {'on': true, 'bri': 128}), isNull);
      expect(extractLuminaPreview(_designWled), isNotNull);
    });
  });
}
