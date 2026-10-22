// Store window (c): Lumina AI consent, Apple 5.1.2(i).
//
// Fail closed everywhere. No saved grant means no request. These tests pin:
//   * the stored decision (users/{uid}.ai_consent) and what counts as a grant;
//   * the gate: closed by default, opened only by a SAVED grant, and closed
//     at once by a revoke even when saving the revoke fails;
//   * the store: a field UPDATE, so a missing user doc throws;
//   * the prompt: Allow + saved write → open; Allow + failed write →
//     closed; Not now → closed and "declined" recorded;
//   * both chokepoints refuse before any network: LuminaAI and
//     EventLuminaService;
//   * the approved sheet text, word for word.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ai/ai_consent.dart';
import 'package:nexgen_command/features/ai/ai_consent_host.dart';
import 'package:nexgen_command/features/ai/ai_consent_settings_tile.dart';
import 'package:nexgen_command/features/ai/ai_consent_sheet.dart';
import 'package:nexgen_command/lumina_ai/lumina_ai_service.dart';
import 'package:nexgen_command/models/commercial/commercial_brand_profile.dart';
import 'package:nexgen_command/models/commercial/commercial_event.dart';
import 'package:nexgen_command/services/commercial/event_lumina_service.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'u1';
}

/// A store whose writes can be made to fail, recording every write.
class _Store implements AiConsentStore {
  _Store({this.failWrites = false, this.stored});
  bool failWrites;
  final AiConsent? stored;
  final writes = <AiConsentStatus>[];
  @override
  Stream<AiConsent?> watch(String uid) => Stream.value(stored);
  @override
  Future<void> write(String uid, AiConsentStatus status) async {
    writes.add(status);
    if (failWrites) throw FirebaseException(plugin: 'test', code: 'unavailable');
  }
}

/// Any use of Cloud Functions fails the test: the gate must refuse first.
class _NoFunctions extends Fake implements FirebaseFunctions {
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      throw StateError('claudeProxy was called without consent');
}

void main() {
  setUp(AiConsentGate.resetForTest);
  tearDown(AiConsentGate.resetForTest);

  group('stored decision', () {
    test('only a current-version grant for the named provider allows requests', () {
      expect(const AiConsent(status: AiConsentStatus.granted).allowsRequests, isTrue);
      expect(const AiConsent(status: AiConsentStatus.declined).allowsRequests, isFalse);
      expect(const AiConsent(status: AiConsentStatus.revoked).allowsRequests, isFalse);
      expect(const AiConsent(status: AiConsentStatus.granted, version: 0).allowsRequests, isFalse,
          reason: 'an older consent version must ask again');
      expect(const AiConsent(status: AiConsentStatus.granted, provider: 'other').allowsRequests,
          isFalse);
    });

    test('unreadable data reads as "not asked"', () {
      expect(AiConsent.fromJson(null), isNull);
      expect(AiConsent.fromJson('granted'), isNull);
      expect(AiConsent.fromJson({'status': 'yes'}), isNull);
      final c = AiConsent.fromJson({'status': 'granted', 'version': 1, 'provider': 'anthropic'});
      expect(c!.allowsRequests, isTrue);
    });
  });

  group('gate', () {
    test('closed by default; with no prompter, ensure() is false', () async {
      expect(AiConsentGate.isGranted, isFalse);
      expect(await AiConsentGate.ensure(), isFalse);
    });

    test('opens only from a stored grant for the signed-in account', () {
      AiConsentGate.syncFromStore('u1', null);
      expect(AiConsentGate.isGranted, isFalse);
      AiConsentGate.syncFromStore('u1', const AiConsent(status: AiConsentStatus.granted));
      expect(AiConsentGate.isGranted, isTrue);
      AiConsentGate.syncFromStore(null, const AiConsent(status: AiConsentStatus.granted));
      expect(AiConsentGate.isGranted, isFalse, reason: 'signed out');
    });

    test('a revoke closes at once and stays closed despite a stale stored grant', () {
      AiConsentGate.syncFromStore('u1', const AiConsent(status: AiConsentStatus.granted));
      AiConsentGate.markRevoked();
      AiConsentGate.syncFromStore('u1', const AiConsent(status: AiConsentStatus.granted));
      expect(AiConsentGate.isGranted, isFalse);
      // A different account starts clean.
      AiConsentGate.syncFromStore('u2', const AiConsent(status: AiConsentStatus.granted));
      expect(AiConsentGate.isGranted, isTrue);
    });

    test('concurrent requests share one prompt', () async {
      var prompts = 0;
      AiConsentGate.registerPrompter(() async {
        prompts++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        AiConsentGate.markGranted();
        return true;
      });
      final r = await Future.wait([AiConsentGate.ensure(), AiConsentGate.ensure()]);
      expect(r, [true, true]);
      expect(prompts, 1);
    });

    test('a prompter that throws reads as no', () async {
      AiConsentGate.registerPrompter(() async => throw StateError('boom'));
      expect(await AiConsentGate.ensure(), isFalse);
      expect(AiConsentGate.isGranted, isFalse);
    });
  });

  group('Firestore store (field update, never create)', () {
    test('updates ai_consent on an existing user doc', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('u1').set({'id': 'u1', 'display_name': 'Keep me'});
      await FirestoreAiConsentStore(db).write('u1', AiConsentStatus.granted);
      final data = (await db.collection('users').doc('u1').get()).data()!;
      expect((data['ai_consent'] as Map)['status'], 'granted');
      expect(data['display_name'], 'Keep me', reason: 'other fields untouched');
    });

    test('a missing user doc THROWS, so the grant fails closed', () async {
      final db = FakeFirebaseFirestore();
      await expectLater(
        FirestoreAiConsentStore(db).write('nobody', AiConsentStatus.granted),
        throwsA(anything),
      );
    });
  });

  group('prompt flow', () {
    Future<(Future<bool>, ProviderContainer)> open(
        WidgetTester tester, _Store store) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late WidgetRef captured;
      late BuildContext ctx;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(_User())),
          aiConsentStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            captured = ref;
            ctx = context;
            ref.watch(authStateProvider);
            return const Scaffold(body: SizedBox());
          }),
        ),
      ));
      await tester.pump();
      final result = promptForAiConsent(captured, context: ctx);
      await tester.pumpAndSettle();
      return (result, ProviderScope.containerOf(ctx));
    }

    testWidgets('Allow + saved write: open', (tester) async {
      final store = _Store();
      final (result, _) = await open(tester, store);
      expect(find.text(kAiConsentTitle), findsOneWidget);
      await tester.ensureVisible(find.text(kAiConsentAllow));
      await tester.tap(find.text(kAiConsentAllow));
      await tester.pumpAndSettle();
      expect(find.text(kAiConsentTitle), findsNothing, reason: 'sheet closed');
      expect(await result, isTrue);
      expect(store.writes, [AiConsentStatus.granted]);
      expect(AiConsentGate.isGranted, isTrue);
    });

    testWidgets('Allow + FAILED write: closed, nothing may be sent', (tester) async {
      final store = _Store(failWrites: true);
      final (result, _) = await open(tester, store);
      await tester.ensureVisible(find.text(kAiConsentAllow));
      await tester.tap(find.text(kAiConsentAllow));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(AiConsentGate.isGranted, isFalse);
    });

    testWidgets('Not now: closed, and "declined" is recorded', (tester) async {
      final store = _Store();
      final (result, _) = await open(tester, store);
      await tester.ensureVisible(find.text(kAiConsentNotNow));
      await tester.tap(find.text(kAiConsentNotNow));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(store.writes, [AiConsentStatus.declined]);
      expect(AiConsentGate.isGranted, isFalse);
    });
  });

  group('chokepoints refuse before any network', () {
    test('LuminaAI (chat, schedule card, refinement all go through _callClaude)',
        () async {
      AiConsentGate.syncFromStore('u1', null); // signed in, not granted
      await expectLater(
        LuminaAI.chatDirect('warm white tonight', systemPrompt: 'test'),
        throwsA(isA<AiConsentRequiredException>()
            .having((e) => e.signedOut, 'signedOut', isFalse)
            .having((e) => e.userMessage, 'userMessage', kAiConsentOffMessage)),
      );
    });

    test('signed out (the REVIEW showroom demo): no sheet, the account message',
        () async {
      var prompted = false;
      AiConsentGate.registerPrompter(() async => prompted = true);
      AiConsentGate.syncFromStore(null, null);
      await expectLater(
        LuminaAI.chatDirect('warm white tonight', systemPrompt: 'test'),
        throwsA(isA<AiConsentRequiredException>()
            .having((e) => e.signedOut, 'signedOut', isTrue)
            .having((e) => e.userMessage, 'userMessage', kAiSignInRequiredMessage)),
      );
      expect(prompted, isFalse, reason: 'no sheet when there is no account');
      expect(kAiSignInRequiredMessage, isNot(contains('Settings')),
          reason: 'a signed-out user cannot turn it on in Settings');
    });

    test('EventLuminaService (bypasses _callClaude)', () async {
      AiConsentGate.syncFromStore('u1', null);
      final service = EventLuminaService(functions: _NoFunctions());
      await expectLater(
        service.generateEventDesigns(
          eventDescription: 'Spring sale',
          eventType: EventType.values.first,
          brand: CommercialBrandProfile(
              companyName: 'Test Co', createdAt: DateTime(2026)),
        ),
        throwsA(isA<AiConsentRequiredException>()),
      );
    });
  });

  test('the sheet carries the approved text, word for word', () {
    expect(kAiConsentTitle, 'Lumina AI uses Anthropic');
    expect(
        kAiConsentIntro,
        'To answer your requests, Lumina AI sends them to Anthropic, the '
        "company that makes the Claude AI model. Nex-Gen doesn't sell this "
        'information or use it for advertising.');
    expect(kAiConsentSentHeading, 'Each time you ask Lumina AI, we send:');
    expect(kAiConsentSentItems, [
      'What you type, or the words you say. Your voice recording stays on '
          'your phone; only the text is sent.',
      'The current date, time and your time zone.',
      'Your general location (city and state) from your profile.',
      "Interests and dislikes you've saved in your profile.",
      'A description of your lights: how many there are, your roofline '
          'section names and where they are, and which effects your '
          'controller supports.',
      "When it helps: your current design, today's sunrise and sunset "
          'times, and the name of a favorite or scene you mention.',
      'For business accounts: your business name, brand colors, and the '
          'event you describe.',
    ]);
    expect(
        kAiConsentNotSent,
        "We don't send your name, email, phone number, account ID, exact "
        "location, or your controllers' network addresses.");
    expect(
        kAiConsentKept,
        "Nex-Gen doesn't keep your requests or Lumina's replies. We keep only "
        'a record of when you used Lumina AI and how much it processed, and '
        "it's deleted if you delete your account.");
    expect(kAiConsentTurnOff,
        'You can turn Lumina AI off at any time in Settings → Lumina AI.');
    expect(kAiConsentAllow, 'Allow Lumina AI');
    expect(kAiConsentNotNow, 'Not now');
    // No statement about the provider's retention or training in the app.
    final all = [
      kAiConsentIntro, ...kAiConsentSentItems, kAiConsentNotSent,
      kAiConsentKept, kAiConsentTurnOff,
    ].join(' ').toLowerCase();
    for (final word in const ['train', 'retain', 'retention', '30 days']) {
      expect(all, isNot(contains(word)), reason: word);
    }
  });

  testWidgets('Settings: switching off with a FAILED save still closes the gate',
      (tester) async {
    final store = _Store(
        failWrites: true,
        stored: const AiConsent(status: AiConsentStatus.granted));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(_User())),
        aiConsentStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: AiConsentSettingsTile()))),
    ));
    await tester.pumpAndSettle();
    AiConsentGate.syncFromStore('u1', store.stored);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(store.writes, [AiConsentStatus.revoked]);
    expect(AiConsentGate.isGranted, isFalse, reason: 'off on this phone at once');
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    expect(find.text(kAiConsentRevokeNotSaved), findsOneWidget);
    expect(await AiConsentGate.ensure(), isFalse,
        reason: 'no prompter here, and the gate stays closed');
  });
}
