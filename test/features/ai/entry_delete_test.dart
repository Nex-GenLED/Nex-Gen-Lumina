// Build 128, Step 4 — Lumina deletes dated calendar entries: the model
// proposes, the app confirms.
//
// Fake calendar (a list of CalendarEntry), fake delete services, fake thread;
// no Riverpod container, no Firebase, no controller. Cases from the brief:
// one entry, a range, "everything you created", nothing matching, a Game Day
// entry refused, a recurring schedule refused, Cancel removes nothing, and
// the 31-entry cap — plus the parser, the request detector, the processor
// carry, the prompt assembly and the card's buttons.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/entry_delete_confirm_card.dart';
import 'package:nexgen_command/features/ai/entry_delete_intent.dart';
import 'package:nexgen_command/features/ai/entry_delete_resolver.dart';
import 'package:nexgen_command/features/ai/entry_delete_services.dart';
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_conversation_driver.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/lumina_ai/lumina_ai_service.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

/// Wednesday 2026-11-18, noon.
final _today = DateTime(2026, 11, 18, 12);

CalendarEntry _lumina(int i, String dateKey, {String? name}) => CalendarEntry(
      entryId: 'lumina_1762819200000_$i',
      dateKey: dateKey,
      patternName: name ?? 'Lumina Night ${i + 1}',
      color: const Color(0xFFE31837),
      onTime: '18:00',
      offTime: '23:00',
      brightness: 85,
      type: CalendarEntryType.user,
      autopilot: true,
      sourceTag: CalendarEntrySourceTag.luminaAi,
      note: 'Lumina: Solid',
    );

/// The seven entries Lumina wrote on 2026-11-11, Nov 19 to Nov 25.
List<CalendarEntry> _sevenLumina() => [
      _lumina(0, '2026-11-19', name: 'Warm White Evening'),
      _lumina(1, '2026-11-20', name: 'Chiefs Game Night'),
      _lumina(2, '2026-11-21'),
      _lumina(3, '2026-11-22'),
      _lumina(4, '2026-11-23'),
      _lumina(5, '2026-11-24'),
      _lumina(6, '2026-11-25'),
    ];

const CalendarEntry _handMade = CalendarEntry(
  entryId: 'user_1',
  dateKey: '2026-11-20',
  patternName: 'Birthday Blue',
  color: Color(0xFF0033A0),
  onTime: '19:00',
  offTime: '23:30',
  brightness: 100,
  type: CalendarEntryType.user,
  autopilot: false,
);

CalendarEntry _gameDay(String dateKey) => CalendarEntry(
      entryId: CalendarEntryId.gameDay('nfl_chiefs'),
      dateKey: dateKey,
      patternName: 'Chiefs Colors',
      onTime: '19:00',
      type: CalendarEntryType.autopilot,
      autopilot: true,
      sourceTag: CalendarEntrySourceTag.gameDay,
      endMode: CalendarEntryEndMode.untilGameEnd,
      note: 'Chiefs vs Colts — Game Day autopilot',
    );

const CalendarEntry _autopilot = CalendarEntry(
  entryId: 'ap_1',
  dateKey: '2026-11-21',
  patternName: 'Autopilot Amber',
  onTime: '18:00',
  offTime: '22:00',
  type: CalendarEntryType.autopilot,
  autopilot: true,
  sourceTag: CalendarEntrySourceTag.autopilot,
);

const CalendarEntry _holiday = CalendarEntry(
  entryId: CalendarEntryId.holiday,
  dateKey: '2026-11-26',
  patternName: 'Thanksgiving',
  onTime: '17:30',
  offTime: '23:30',
  type: CalendarEntryType.holiday,
  autopilot: false,
);

/// The calendar as the phone holds it: the seven Lumina nights, a hand-made
/// entry sharing Nov 20, a Game Day sharing Nov 23 and another alone on
/// Nov 28, an autopilot entry on Nov 21, a past Lumina night, and a holiday
/// default.
List<CalendarEntry> _calendar() => [
      ..._sevenLumina(),
      _handMade,
      _gameDay('2026-11-23'),
      _gameDay('2026-11-28'),
      _autopilot,
      _lumina(99, '2026-11-10', name: 'Past Night'),
      _holiday,
    ];

EntryDeleteIntent _date(String d, {String? name}) => EntryDeleteIntent(
    target: EntryDeleteTarget.dated,
    scope: EntryDeleteScope.date,
    date: d,
    nameFilter: name);

EntryDeleteIntent _range(String a, String b) => EntryDeleteIntent(
    target: EntryDeleteTarget.dated,
    scope: EntryDeleteScope.range,
    startDate: a,
    endDate: b);

const EntryDeleteIntent _all = EntryDeleteIntent(
    target: EntryDeleteTarget.dated, scope: EntryDeleteScope.luminaAll);

List<String> _ids(Iterable<CalendarEntry> es) =>
    es.map((e) => e.entryId).toList();

// ── Fakes for the driver ────────────────────────────────────────────────────

class _FakeThread implements LuminaThread {
  final List<String> assistantMessages = [];
  @override
  void addUserMessage(String text) {}
  @override
  void updateTranscription(String text) {}
  @override
  void addAssistantMessage(String text,
          {LuminaPatternPreview? preview, Map<String, dynamic>? wledPayload}) =>
      assistantMessages.add(text);
}

/// Only what the delete branch touches; everything else is unreachable here.
class _FakeServices implements LuminaConversationServices {
  final _FakeThread thread = _FakeThread();
  @override
  LuminaThread openThread() => thread;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDelete implements LuminaEntryDeleteServices {
  _FakeDelete(this.calendar, {this.failIds = const {}});
  List<CalendarEntry> calendar;
  final Set<String> failIds;
  final List<(String, EntryDeleteProposal)> posted = [];
  final List<CalendarEntry> deleted = [];
  int decided = 0;

  @override
  List<CalendarEntry> calendarEntries() => List.of(calendar);
  @override
  DateTime now() => _today;
  @override
  void postProposal(String text, EntryDeleteProposal proposal) =>
      posted.add((text, proposal));
  @override
  Future<int> deleteEntries(List<CalendarEntry> entries) async {
    var n = 0;
    for (final e in entries) {
      if (failIds.contains(e.entryId)) continue;
      deleted.add(e);
      calendar = calendar.where((c) => c.entryId != e.entryId).toList();
      n++;
    }
    return n;
  }

  @override
  void proposalDecided(EntryDeleteProposal proposal) => decided++;
}

LuminaConversationHost _host() => LuminaConversationHost(
      surface: LuminaSurface.screen,
      isMounted: () => true,
      clearInput: () {},
      scrollToEnd: () {},
      closeSurface: () {},
      goRoute: (_) {},
      pushRoute: (_) {},
      showSnackBar: (_) {},
    );

LuminaCommandResult _cloud(Map<String, dynamic> intent) => LuminaCommandResult(
      responseText: "Here's what I found — confirm below.",
      tier: ProcessingTier.cloud,
      deleteCalendarEntries: intent,
    );

void main() {
  group('EntryDeleteIntent.fromJson', () {
    test('absent → null; dated date / range / lumina_all parse', () {
      expect(EntryDeleteIntent.fromJson(null), isNull);
      final d = EntryDeleteIntent.fromJson(
          {'target': 'dated', 'scope': 'date', 'date': '2026-11-20'})!;
      expect(d.scope, EntryDeleteScope.date);
      expect(d.date, '2026-11-20');
      final r = EntryDeleteIntent.fromJson({
        'scope': 'range',
        'startDate': '2026-11-27',
        'endDate': '2026-11-20',
        'nameFilter': ' Chiefs ',
      })!;
      expect(r.scope, EntryDeleteScope.range);
      expect((r.startDate, r.endDate), ('2026-11-20', '2026-11-27'),
          reason: 'a reversed range is swapped, not guessed at');
      expect(r.nameFilter, 'Chiefs');
      final a = EntryDeleteIntent.fromJson({'scope': 'lumina_all'})!;
      expect(a.scope, EntryDeleteScope.luminaAll);
      expect(a.target, EntryDeleteTarget.dated);
    });

    test('a missing or malformed date is unclear — never invented', () {
      expect(EntryDeleteIntent.fromJson({'scope': 'date'})!.scope,
          EntryDeleteScope.unclear);
      expect(
          EntryDeleteIntent.fromJson({'scope': 'date', 'date': '2026-2-30'})!
              .scope,
          EntryDeleteScope.unclear);
      expect(
          EntryDeleteIntent.fromJson({'scope': 'date', 'date': '2026-02-30'})!
              .scope,
          EntryDeleteScope.unclear,
          reason: 'rollover dates are rejected');
      expect(
          EntryDeleteIntent.fromJson(
                  {'scope': 'range', 'startDate': '2026-11-20'})!
              .scope,
          EntryDeleteScope.unclear);
      expect(EntryDeleteIntent.fromJson({'scope': 'tomorrowish'})!.scope,
          EntryDeleteScope.unclear);
    });

    test('target recurring is kept so the app can refuse it', () {
      final i = EntryDeleteIntent.fromJson(
          {'target': 'recurring', 'scope': 'unclear'})!;
      expect(i.target, EntryDeleteTarget.recurring);
    });
  });

  group('isEntryDeleteRequest', () {
    test('a delete verb with a schedule noun', () {
      for (final p in const [
        'delete the seven entries you created for me',
        "Remove Friday's entry",
        'cancel what you set up for Nov 20 to Nov 27',
        'clear everything you made',
        'get rid of the nights you scheduled this week',
        'delete my nightly warm white schedule',
      ]) {
        expect(isEntryDeleteRequest(p), isTrue, reason: p);
      }
    });

    test('a lighting command is not one', () {
      for (final p in const [
        'remove the red',
        'clear blue lights',
        'turn off the lights',
        'make it brighter',
        'chiefs colors for the game tonight',
        'warm white every night at sunset',
      ]) {
        expect(isEntryDeleteRequest(p), isFalse, reason: p);
      }
    });
  });

  group('resolveEntryDeletion', () {
    test('one day with one entry → a one-entry proposal', () {
      final r =
          resolveEntryDeletion(_date('2026-11-19'), _calendar(), today: _today);
      expect(r.kind, EntryDeleteResolutionKind.propose);
      final p = r.proposal!;
      expect(_ids(p.entries), ['lumina_1762819200000_0']);
      expect(p.leadText,
          'Delete this entry? Nothing is removed until you tap Delete.');
      expect(p.lines, ['Thu, Nov 19 · Warm White Evening']);
      expect(p.scopeLabel, 'on Thu, Nov 19');
    });

    test('one day with a Lumina entry and a hand-made entry → both', () {
      final p =
          resolveEntryDeletion(_date('2026-11-20'), _calendar(), today: _today)
              .proposal!;
      expect(_ids(p.entries), ['lumina_1762819200000_1', 'user_1'],
          reason: 'date, then on time, then id');
      expect(p.leadText,
          'Delete these 2 entries? Nothing is removed until you tap Delete.');
    });

    test('a name filter narrows the day', () {
      final p = resolveEntryDeletion(
              _date('2026-11-20', name: 'chiefs'), _calendar(),
              today: _today)
          .proposal!;
      expect(_ids(p.entries), ['lumina_1762819200000_1']);
      final none = resolveEntryDeletion(
          _date('2026-11-20', name: 'Halloween'), _calendar(),
          today: _today);
      expect(none.kind, EntryDeleteResolutionKind.nothing);
      expect(none.reply,
          'I couldn\'t find an entry called "Halloween" on Fri, Nov 20.');
    });

    test('a range: deletable entries in, Game Day and autopilot left alone',
        () {
      final p = resolveEntryDeletion(
              _range('2026-11-19', '2026-11-23'), _calendar(),
              today: _today)
          .proposal!;
      expect(_ids(p.entries), [
        'lumina_1762819200000_0',
        'lumina_1762819200000_1',
        'user_1',
        'lumina_1762819200000_2',
        'lumina_1762819200000_3',
        'lumina_1762819200000_4',
      ]);
      expect(p.gameDaySkipped, 1, reason: 'the Chiefs night on Nov 23');
      expect(p.autoSkipped, 1, reason: 'the autopilot entry on Nov 21');
      expect(p.scopeLabel, 'from Nov 19 to Nov 23');
      expect(
          p.leadText,
          'Delete these 6 entries? Nothing is removed until you tap Delete. '
          '1 Game Day entry stays; manage it in Game Day settings.');
    });

    test('"everything you created" → the seven Lumina nights, today on', () {
      final p =
          resolveEntryDeletion(_all, _calendar(), today: _today).proposal!;
      expect(p.count, 7);
      expect(_ids(p.entries), _ids(_sevenLumina()));
      expect(_ids(p.entries), isNot(contains('lumina_1762819200000_99')),
          reason: 'the past night is not offered');
      expect(_ids(p.entries), isNot(contains('user_1')),
          reason: 'a hand-made entry is not something Lumina created');
      expect(p.scopeLabel, 'that I created');
    });

    test('nothing matching says so, naming the window', () {
      final r =
          resolveEntryDeletion(_date('2026-11-30'), _calendar(), today: _today);
      expect(r.kind, EntryDeleteResolutionKind.nothing);
      expect(r.reply, "I couldn't find any entries to delete on Mon, Nov 30.");
      final none =
          resolveEntryDeletion(_all, [_handMade, _holiday], today: _today);
      expect(none.kind, EntryDeleteResolutionKind.nothing);
      expect(
          none.reply, "I couldn't find any entries to delete that I created.");
    });

    test('a holiday default is never offered', () {
      final r =
          resolveEntryDeletion(_date('2026-11-26'), _calendar(), today: _today);
      expect(r.kind, EntryDeleteResolutionKind.nothing);
    });

    test(
        'a day that holds only a Game Day entry is refused and pointed at '
        'Game Day settings', () {
      final r =
          resolveEntryDeletion(_date('2026-11-28'), _calendar(), today: _today);
      expect(r.kind, EntryDeleteResolutionKind.gameDayRefused);
      expect(r.reply, kEntryDeleteGameDayRefused);
      expect(r.proposal, isNull);
    });

    test('an edited Game Day row (type user, tag kept) is still refused', () {
      final edited = _gameDay('2026-11-28')
          .copyWith(type: CalendarEntryType.user, brightness: 70);
      expect(isEntryDeletableByLumina(edited), isFalse);
      final r =
          resolveEntryDeletion(_date('2026-11-28'), [edited], today: _today);
      expect(r.kind, EntryDeleteResolutionKind.gameDayRefused);
    });

    test('a repeating schedule is refused, whatever the scope', () {
      const i = EntryDeleteIntent(
          target: EntryDeleteTarget.recurring,
          scope: EntryDeleteScope.luminaAll);
      final r = resolveEntryDeletion(i, _calendar(), today: _today);
      expect(r.kind, EntryDeleteResolutionKind.recurringRefused);
      expect(r.reply, kEntryDeleteRecurringRefused);
      expect(r.proposal, isNull);
    });

    test('unclear asks and offers nothing', () {
      const i = EntryDeleteIntent(
          target: EntryDeleteTarget.dated, scope: EntryDeleteScope.unclear);
      final r = resolveEntryDeletion(i, _calendar(), today: _today);
      expect(r.kind, EntryDeleteResolutionKind.unclear);
      expect(r.reply, kEntryDeleteUnclear);
    });

    test('at most 31 entries per confirmed request; the rest is named', () {
      final forty = [
        for (var i = 0; i < 40; i++)
          _lumina(i, dateKeyOf(DateTime(2026, 11, 19 + i)))
      ];
      final p = resolveEntryDeletion(_all, forty, today: _today).proposal!;
      expect(p.count, kEntryDeleteMaxPerRequest);
      expect(p.count, 31);
      expect(p.overflow, 9);
      expect(p.entries.first.dateKey, '2026-11-19');
      expect(p.entries.last.dateKey, '2026-12-19',
          reason: 'the earliest 31 by date');
      expect(
          p.leadText,
          'Delete these 31 entries? Nothing is removed until you tap Delete. '
          'I can remove up to 31 at a time; 9 more match. Ask again '
          'afterwards for the rest.');
    });

    test('outcome text', () {
      expect(
          entryDeleteOutcomeText(requested: 1, deleted: 1), 'Deleted 1 entry.');
      expect(entryDeleteOutcomeText(requested: 7, deleted: 7),
          'Deleted 7 entries.');
      expect(
          entryDeleteOutcomeText(requested: 7, deleted: 5),
          "Deleted 5 of 7 entries; 2 couldn't be removed. Check your "
          'connection and try again.');
    });
  });

  group('LuminaConversationDriver — the delete branch', () {
    test('a proposal posts the card and removes nothing', () async {
      final svc = _FakeServices();
      final del = _FakeDelete(_calendar());
      final driver = LuminaConversationDriver(
          host: _host(), services: svc, entryDelete: del);
      final branch = await driver.handleResult(
        _cloud({'target': 'dated', 'scope': 'lumina_all'}),
        prompt: 'delete the seven entries you created for me',
        thread: svc.thread,
      );
      expect(branch, LuminaResultBranch.entryDelete);
      expect(del.posted, hasLength(1));
      final (text, proposal) = del.posted.single;
      expect(proposal.count, 7);
      expect(text, proposal.leadText);
      expect(del.deleted, isEmpty, reason: 'nothing until Delete is tapped');
      expect(svc.thread.assistantMessages, isEmpty,
          reason: 'the card is the reply; no second bubble');
      expect(proposal.decision, EntryDeleteDecision.pending);
    });

    test(
        'Delete removes exactly the proposal\'s entries through the service '
        'and says how many went', () async {
      final svc = _FakeServices();
      final del = _FakeDelete(_calendar());
      final driver = LuminaConversationDriver(
          host: _host(), services: svc, entryDelete: del);
      await driver.handleResult(
        _cloud({'target': 'dated', 'scope': 'lumina_all'}),
        prompt: 'delete everything you created',
        thread: svc.thread,
      );
      final proposal = del.posted.single.$2;
      await driver.confirmEntryDelete(proposal);
      expect(_ids(del.deleted), _ids(_sevenLumina()));
      expect(_ids(del.calendar), contains('user_1'),
          reason: 'the hand-made entry on a shared night stays');
      expect(_ids(del.calendar), contains('gd_nfl_chiefs'));
      expect(proposal.decision, EntryDeleteDecision.deleted);
      expect(del.decided, 1);
      expect(svc.thread.assistantMessages, ['Deleted 7 entries.']);
      // A second tap is a no-op.
      await driver.confirmEntryDelete(proposal);
      expect(del.deleted, hasLength(7));
      expect(svc.thread.assistantMessages, hasLength(1));
    });

    test('a partial failure is reported honestly', () async {
      final svc = _FakeServices();
      final del = _FakeDelete(_calendar(),
          failIds: {'lumina_1762819200000_3', 'lumina_1762819200000_5'});
      final driver = LuminaConversationDriver(
          host: _host(), services: svc, entryDelete: del);
      await driver.handleResult(
          _cloud({'target': 'dated', 'scope': 'lumina_all'}),
          prompt: 'delete everything you created',
          thread: svc.thread);
      await driver.confirmEntryDelete(del.posted.single.$2);
      expect(svc.thread.assistantMessages, [
        "Deleted 5 of 7 entries; 2 couldn't be removed. Check your "
            'connection and try again.'
      ]);
    });

    test('Cancel removes nothing and says so; Delete afterwards is a no-op',
        () async {
      final svc = _FakeServices();
      final del = _FakeDelete(_calendar());
      final driver = LuminaConversationDriver(
          host: _host(), services: svc, entryDelete: del);
      await driver.handleResult(
          _cloud({
            'target': 'dated',
            'scope': 'range',
            'startDate': '2026-11-19',
            'endDate': '2026-11-25'
          }),
          prompt: 'cancel what you set up for next week',
          thread: svc.thread);
      final proposal = del.posted.single.$2;
      expect(proposal.count, 8);
      driver.cancelEntryDelete(proposal);
      expect(del.deleted, isEmpty);
      expect(del.calendar, hasLength(_calendar().length));
      expect(proposal.decision, EntryDeleteDecision.cancelled);
      expect(svc.thread.assistantMessages, [kEntryDeleteCancelled]);
      await driver.confirmEntryDelete(proposal);
      expect(del.deleted, isEmpty);
    });

    test('a Game Day day is refused in the thread; no card', () async {
      final svc = _FakeServices();
      final del = _FakeDelete(_calendar());
      final driver = LuminaConversationDriver(
          host: _host(), services: svc, entryDelete: del);
      final branch = await driver.handleResult(
          _cloud({'target': 'dated', 'scope': 'date', 'date': '2026-11-28'}),
          prompt: 'delete the entry on the 28th',
          thread: svc.thread);
      expect(branch, LuminaResultBranch.entryDelete);
      expect(del.posted, isEmpty);
      expect(svc.thread.assistantMessages, [kEntryDeleteGameDayRefused]);
      expect(del.deleted, isEmpty);
    });

    test('a recurring schedule is refused in the thread; no card', () async {
      final svc = _FakeServices();
      final del = _FakeDelete(_calendar());
      final driver = LuminaConversationDriver(
          host: _host(), services: svc, entryDelete: del);
      await driver.handleResult(
          _cloud({
            'target': 'recurring',
            'scope': 'unclear',
            'nameFilter': 'warm white'
          }),
          prompt: 'delete my nightly warm white schedule',
          thread: svc.thread);
      expect(del.posted, isEmpty);
      expect(svc.thread.assistantMessages, [kEntryDeleteRecurringRefused]);
      expect(del.deleted, isEmpty);
    });

    test('nothing matching and unclear both answer in words', () async {
      final svc = _FakeServices();
      final del = _FakeDelete(_calendar());
      final driver = LuminaConversationDriver(
          host: _host(), services: svc, entryDelete: del);
      await driver.handleResult(
          _cloud({'target': 'dated', 'scope': 'date', 'date': '2026-11-30'}),
          prompt: 'delete the entry on the 30th',
          thread: svc.thread);
      await driver.handleResult(_cloud({'target': 'dated', 'scope': 'unclear'}),
          prompt: 'delete that entry', thread: svc.thread);
      expect(svc.thread.assistantMessages, [
        "I couldn't find any entries to delete on Mon, Nov 30.",
        kEntryDeleteUnclear,
      ]);
      expect(del.posted, isEmpty);
    });

    test('a surface without the delete service degrades to the manual route',
        () async {
      final svc = _FakeServices();
      final driver = LuminaConversationDriver(host: _host(), services: svc);
      final branch = await driver.handleResult(
          _cloud({'target': 'dated', 'scope': 'lumina_all'}),
          prompt: 'delete everything you created',
          thread: svc.thread);
      expect(branch, LuminaResultBranch.entryDelete);
      expect(svc.thread.assistantMessages, [kEntryDeleteNotAvailable]);
    });
  });

  group('CloudAIProcessor carries deleteCalendarEntries', () {
    test('from the reply JSON to the typed accessor; no payload, no schedule',
        () {
      const reply = "Here's what I found — confirm below.\n"
          '{"message":"Here\'s what I found — confirm below.","wled":null,'
          '"deleteCalendarEntries":{"target":"dated","scope":"lumina_all",'
          '"date":null,"startDate":null,"endDate":null,"nameFilter":null}}';
      final r = CloudAIProcessor.parseAiResponseForTest(reply, 'delete them');
      expect(r.deleteCalendarEntries, isNotNull);
      final intent = r.entryDeleteIntent!;
      expect(intent.scope, EntryDeleteScope.luminaAll);
      expect(r.wledPayload, isNull);
      expect(r.hasSchedulingIntents, isFalse);
      expect(r.responseText, "Here's what I found — confirm below.");
    });

    test('absent → null, as before', () {
      const reply = 'Running Solid in red.\n{"wled":{"on":true}}';
      final r = CloudAIProcessor.parseAiResponseForTest(reply, 'red');
      expect(r.deleteCalendarEntries, isNull);
      expect(r.entryDeleteIntent, isNull);
    });
  });

  group('Smart system prompt', () {
    final smart = LuminaAI.debugSmartSystemPrompt;

    test('embeds the delete fragment verbatim and declares the key', () {
      expect(smart.contains(EntryDeleteIntent.schemaPromptFragment), isTrue);
      expect(smart, contains('═══ DELETING DATED CALENDAR ENTRIES ═══'));
      expect(smart,
          contains('"deleteCalendarEntries":{"target":"dated"|"recurring"'));
      expect(smart, contains('YOU DO NOT DELETE ANYTHING'));
      expect(smart, contains('NEVER guess a date'));
    });
  });

  group('EntryDeleteConfirmCard', () {
    EntryDeleteProposal proposal() => EntryDeleteProposal(
          entries: _sevenLumina().take(2).toList(),
          scopeLabel: 'that I created',
        );

    Widget host(EntryDeleteProposal p,
            {VoidCallback? onDelete, VoidCallback? onCancel}) =>
        MaterialApp(
          home: Scaffold(
            body: EntryDeleteConfirmCard(
              text: p.leadText,
              proposal: p,
              onDelete: onDelete,
              onCancel: onCancel,
            ),
          ),
        );

    testWidgets(
        'shows the count, the dates and the names, with Delete and '
        'Cancel', (tester) async {
      final p = proposal();
      await tester.pumpWidget(host(p));
      expect(find.text(p.leadText), findsOneWidget);
      expect(find.text('Thu, Nov 19 · Warm White Evening'), findsOneWidget);
      expect(find.text('Fri, Nov 20 · Chiefs Game Night'), findsOneWidget);
      expect(find.byKey(EntryDeleteConfirmCard.deleteKey), findsOneWidget);
      expect(find.byKey(EntryDeleteConfirmCard.cancelKey), findsOneWidget);
    });

    testWidgets('Delete and Cancel call back; a decided card has no buttons',
        (tester) async {
      final p = proposal();
      var deletes = 0, cancels = 0;
      await tester.pumpWidget(
          host(p, onDelete: () => deletes++, onCancel: () => cancels++));
      await tester.tap(find.byKey(EntryDeleteConfirmCard.cancelKey));
      await tester.tap(find.byKey(EntryDeleteConfirmCard.deleteKey));
      expect((deletes, cancels), (1, 1));

      p.decision = EntryDeleteDecision.cancelled;
      await tester.pumpWidget(host(p));
      expect(find.byKey(EntryDeleteConfirmCard.deleteKey), findsNothing);
      expect(find.byKey(EntryDeleteConfirmCard.cancelKey), findsNothing);
      expect(find.text('Cancelled'), findsOneWidget);
    });
  });
}
