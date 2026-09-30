// +110 package G — rows 14, 15, 16 and 17 of the 2026-09-25 UX defect audit,
// each driven from the real control.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/features/auth/forced_password_reset_screen.dart';
import 'package:nexgen_command/features/auth/join_with_code_screen.dart';
import 'package:nexgen_command/features/auth/login_page.dart';
import 'package:nexgen_command/features/auth/staff_pin_screen.dart';
import 'package:nexgen_command/features/onboarding/first_run_screen.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/route_guards.dart';
import 'package:nexgen_command/services/user_service.dart';

import 'setup_auth_fixtures.dart';

/// Hosts [initial] in a real GoRouter with stub pages for everywhere the
/// screens under test can send the customer.
Widget _app({
  required String initial,
  required Map<String, Widget Function()> screens,
  required List<Override> overrides,
}) {
  Widget stub(String name) => Scaffold(body: Center(child: Text('PAGE:$name')));
  final routes = <String, Widget Function()>{
    AppRoutes.login: () => stub('login'),
    AppRoutes.dashboard: () => stub('dashboard'),
    AppRoutes.demoCode: () => stub('demo'),
    ...screens,
  };
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      for (final e in routes.entries)
        GoRoute(path: e.key, builder: (_, __) => e.value()),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(SessionAccountFlags.resetForTest);

  // ── Row 14 ───────────────────────────────────────────────────────────────
  group('row 14 — forced password reset', () {
    Future<void> fillAndSubmit(WidgetTester tester) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'temp-pass-1');
      await tester.enterText(fields.at(1), 'brand-new-pass');
      await tester.enterText(fields.at(2), 'brand-new-pass');
      await tester.ensureVisible(find.text('SET NEW PASSWORD'));
      await tester.tap(find.text('SET NEW PASSWORD'));
      await tester.pumpAndSettle();
    }

    testWidgets('new password → dashboard, flag cleared on the account',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('users')
          .doc(kTestUid)
          .set({'must_reset_password': true});
      final session = FakeAccountSession();

      await tester.pumpWidget(_app(
        initial: AppRoutes.forcedPasswordReset,
        screens: {
          AppRoutes.forcedPasswordReset: () =>
              const ForcedPasswordResetScreen(),
        },
        overrides: [
          accountSessionProvider.overrideWithValue(session),
          accountFirestoreProvider.overrideWithValue(fs),
        ],
      ));
      await tester.pumpAndSettle();
      await fillAndSubmit(tester);

      expect(session.calls,
          containsAllInOrder(['reauthenticate', 'updatePassword']));
      expect(find.text('PAGE:dashboard'), findsOneWidget);
      final doc = await fs.collection('users').doc(kTestUid).get();
      expect(doc.data()!['must_reset_password'], isFalse);
    });

    testWidgets(
        'a flag write that is refused never strands the customer: '
        'dashboard, and the router stops asking', (tester) async {
      // No user document: the flag update is refused (not-found).
      final fs = FakeFirebaseFirestore();
      final session = FakeAccountSession();

      await tester.pumpWidget(_app(
        initial: AppRoutes.forcedPasswordReset,
        screens: {
          AppRoutes.forcedPasswordReset: () =>
              const ForcedPasswordResetScreen(),
        },
        overrides: [
          accountSessionProvider.overrideWithValue(session),
          accountFirestoreProvider.overrideWithValue(fs),
        ],
      ));
      await tester.pumpAndSettle();
      await fillAndSubmit(tester);

      expect(find.text('PAGE:dashboard'), findsOneWidget);
      // The stored flag still says "must reset", but the redirect honours
      // the reset this session completed.
      expect(mustResetPasswordFor(kTestUid, {'must_reset_password': true}),
          isFalse);
      expect(
          mustResetPasswordFor('someone-else', {'must_reset_password': true}),
          isTrue);
      // The refused write keeps retrying in the background; let the whole
      // retry schedule run out.
      await tester.pump(const Duration(minutes: 30));
    });

    testWidgets('Sign out leaves the screen for the login page',
        (tester) async {
      final session = FakeAccountSession();
      await tester.pumpWidget(_app(
        initial: AppRoutes.forcedPasswordReset,
        screens: {
          AppRoutes.forcedPasswordReset: () =>
              const ForcedPasswordResetScreen(),
        },
        overrides: [
          accountSessionProvider.overrideWithValue(session),
          accountFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        ],
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(session.signOutCalls, 1);
      expect(find.text('PAGE:login'), findsOneWidget);
    });

    testWidgets('a wrong current password keeps the customer here, no flag',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('users')
          .doc(kTestUid)
          .set({'must_reset_password': true});
      final session = FakeAccountSession()
        ..reauthError = Exception('wrong-password');
      await tester.pumpWidget(_app(
        initial: AppRoutes.forcedPasswordReset,
        screens: {
          AppRoutes.forcedPasswordReset: () =>
              const ForcedPasswordResetScreen(),
        },
        overrides: [
          accountSessionProvider.overrideWithValue(session),
          accountFirestoreProvider.overrideWithValue(fs),
        ],
      ));
      await tester.pumpAndSettle();
      await fillAndSubmit(tester);

      expect(find.byType(ForcedPasswordResetScreen), findsOneWidget);
      expect(session.calls, isNot(contains('updatePassword')));
      expect(
          SessionAccountFlags.isCleared(
              kTestUid, AccountFlag.passwordResetDone),
          isFalse);
      final doc = await fs.collection('users').doc(kTestUid).get();
      expect(doc.data()!['must_reset_password'], isTrue);
    });
  });

  group('row 14/15 — bounded flag write with background retry', () {
    test('a write that hangs returns within the bound and keeps retrying',
        () async {
      final hanging = HangingWrite();
      var retries = 0;
      final watch = Stopwatch()..start();
      final outcome = await writeAccountFlag(
        uid: kTestUid,
        flag: AccountFlag.welcomeCompleted,
        write: () {
          if (hanging.calls == 0) return hanging();
          retries++;
          return retries < 2
              ? Future.error(StateError('offline'))
              : Future.value();
        },
        timeout: const Duration(milliseconds: 50),
        retryDelays: const [
          Duration(milliseconds: 10),
          Duration(milliseconds: 10),
          Duration(milliseconds: 10),
        ],
      );
      expect(outcome, AccountFlagWrite.retryingInBackground);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(
          SessionAccountFlags.isCleared(kTestUid, AccountFlag.welcomeCompleted),
          isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(retries, 2,
          reason: 'retried until one attempt landed, then stopped');
    });

    test('a write that lands is reported saved and not retried', () async {
      var calls = 0;
      final outcome = await writeAccountFlag(
        uid: kTestUid,
        flag: AccountFlag.passwordResetDone,
        write: () async => calls++,
      );
      expect(outcome, AccountFlagWrite.saved);
      expect(calls, 1);
    });
  });

  // ── Row 15 ───────────────────────────────────────────────────────────────
  group('row 15 — first run', () {
    List<Override> overrides(FakeFirebaseFirestore fs, FakeAccountSession s) =>
        [
          accountSessionProvider.overrideWithValue(s),
          userServiceProvider.overrideWithValue(UserService(firestore: fs)),
          currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
        ];

    testWidgets('Skip finishes onboarding even before the profile loads',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('users')
          .doc(kTestUid)
          .set({'welcome_completed': false});
      await tester.pumpWidget(_app(
        initial: AppRoutes.firstRun,
        screens: {AppRoutes.firstRun: () => const FirstRunScreen()},
        overrides: overrides(fs, FakeAccountSession()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('first-run-skip')));
      await tester.pumpAndSettle();

      expect(find.text('PAGE:dashboard'), findsOneWidget);
      final doc = await fs.collection('users').doc(kTestUid).get();
      expect(doc.data()!['welcome_completed'], isTrue);
    });

    testWidgets(
        '"Go to my lights" with a refused write still reaches the dashboard, '
        'and the router does not send the customer back', (tester) async {
      final fs = FakeFirebaseFirestore(); // no user doc → update refused
      await tester.pumpWidget(_app(
        initial: AppRoutes.firstRun,
        screens: {
          AppRoutes.firstRun: () => const FirstRunScreen(initialPage: 2),
        },
        overrides: overrides(fs, FakeAccountSession()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('first-run-finish')));
      await tester.pumpAndSettle();

      expect(find.text('PAGE:dashboard'), findsOneWidget);
      expect(
          welcomeCompletedFor(kTestUid, {'welcome_completed': false}), isTrue);
      expect(welcomeCompletedFor('another-uid', {'welcome_completed': false}),
          isFalse);
      await tester.pump(const Duration(minutes: 30)); // retry schedule
    });

    testWidgets('Sign out is offered on first run', (tester) async {
      final session = FakeAccountSession();
      await tester.pumpWidget(_app(
        initial: AppRoutes.firstRun,
        screens: {AppRoutes.firstRun: () => const FirstRunScreen()},
        overrides: overrides(FakeFirebaseFirestore(), session),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(session.signOutCalls, 1);
      expect(find.text('PAGE:login'), findsOneWidget);
    });
  });

  // ── Row 16 ───────────────────────────────────────────────────────────────
  group('row 16 — staff PIN screen closed without a match', () {
    Widget pinApp(FakeAccountSession session) {
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push(AppRoutes.staffPin),
                child: const Text('open staff pin'),
              ),
            ),
          ),
        ),
        GoRoute(
            path: AppRoutes.staffPin,
            builder: (_, __) => const StaffPinScreen()),
      ]);
      return ProviderScope(
        overrides: [accountSessionProvider.overrideWithValue(session)],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('Close signs out the anonymous session the screen created',
        (tester) async {
      final session =
          FakeAccountSession(isSignedIn: false, uid: null, email: null);
      await tester.pumpWidget(pinApp(session));
      await tester.tap(find.text('open staff pin'));
      await tester.pumpAndSettle();
      expect(session.anonymousSignIns, 1);
      expect(session.isAnonymous, isTrue);

      await tester.tap(find.byKey(const ValueKey('staff-pin-close')));
      await tester.pumpAndSettle();

      expect(session.signOutCalls, 1);
      expect(session.isSignedIn, isFalse);
      expect(find.text('open staff pin'), findsOneWidget);
    });

    testWidgets('system back also signs it out', (tester) async {
      final session =
          FakeAccountSession(isSignedIn: false, uid: null, email: null);
      await tester.pumpWidget(pinApp(session));
      await tester.tap(find.text('open staff pin'));
      await tester.pumpAndSettle();

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      expect(session.signOutCalls, 1);
    });

    testWidgets("a customer's own session is never touched", (tester) async {
      final session = FakeAccountSession(); // signed in with email
      await tester.pumpWidget(pinApp(session));
      await tester.tap(find.text('open staff pin'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('staff-pin-close')));
      await tester.pumpAndSettle();

      expect(session.anonymousSignIns, 0);
      expect(session.signOutCalls, 0);
    });

    testWidgets(
        'login offers no way to create an account (Lumina is professionally '
        'installed)', (tester) async {
      final session =
          FakeAccountSession(isAnonymous: true, uid: 'uid-anon', email: null);
      await tester.pumpWidget(_app(
        initial: '/login-screen',
        screens: {'/login-screen': () => const LoginScreen()},
        overrides: [accountSessionProvider.overrideWithValue(session)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Create One'), findsNothing);
      expect(find.textContaining("Don't have an account"), findsNothing);
      expect(find.text('Experience Nex-Gen Demo'), findsOneWidget);
    });
  });

  // ── Row 17 ───────────────────────────────────────────────────────────────
  group('row 17 — join with invitation code', () {
    Future<FakeFirebaseFirestore> seeded({bool withProfile = true}) async {
      final fs = FakeFirebaseFirestore();
      if (withProfile) {
        await fs.collection('users').doc(kTestUid).set({
          'id': kTestUid,
          'owner_id': kTestUid,
          'installation_role': 'unlinked',
        });
      }
      await fs.collection('invitations').doc('inv-1').set({
        'installation_id': 'inst-1',
        'primary_user_id': 'uid-owner',
        'invitee_email': kTestEmail,
        'token': 'ABC123',
        'status': 'pending',
        'expires_at':
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
        'permissions': <String, dynamic>{},
      });
      return fs;
    }

    Widget joinApp(FakeFirebaseFirestore fs, FakeAccountSession session) =>
        _app(
          initial: AppRoutes.joinWithCode,
          screens: {AppRoutes.joinWithCode: () => const JoinWithCodeScreen()},
          overrides: [
            accountSessionProvider.overrideWithValue(session),
            accountFirestoreProvider.overrideWithValue(fs),
          ],
        );

    Future<String> inviteStatus(FakeFirebaseFirestore fs) async =>
        (await fs.collection('invitations').doc('inv-1').get())
            .data()!['status'] as String;

    testWidgets(
        'a join that fails part-way never consumes the code; the '
        'retry succeeds', (tester) async {
      // The profile update is refused (no profile document yet).
      final fs = await seeded(withProfile: false);
      await tester.pumpWidget(joinApp(fs, FakeAccountSession()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'abc123');
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to join'), findsOneWidget);
      expect(find.textContaining('has not been used'), findsOneWidget);
      expect(await inviteStatus(fs), 'pending',
          reason: 'the code must survive a failed join');

      // The profile appears (e.g. the redirect's skeleton write lands); the
      // same code now works.
      await fs.collection('users').doc(kTestUid).set({
        'id': kTestUid,
        'owner_id': kTestUid,
        'installation_role': 'unlinked',
      });
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.text('PAGE:dashboard'), findsOneWidget);
      expect(await inviteStatus(fs), 'accepted');
      final profile =
          (await fs.collection('users').doc(kTestUid).get()).data()!;
      expect(profile['installation_role'], 'subUser');
      expect(profile['installation_id'], 'inst-1');
    });

    testWidgets('a code sent to another email is refused without touching it',
        (tester) async {
      final fs = await seeded();
      await tester.pumpWidget(
          joinApp(fs, FakeAccountSession(email: 'other@example.com')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'ABC123');
      await tester.pumpAndSettle();

      expect(find.textContaining('other@example.com'), findsOneWidget);
      expect(await inviteStatus(fs), 'pending');
      final profile =
          (await fs.collection('users').doc(kTestUid).get()).data()!;
      expect(profile['installation_role'], 'unlinked');
    });

    testWidgets('auto-submit and a Join tap run one join, not two',
        (tester) async {
      final fs = await seeded();
      await tester.pumpWidget(joinApp(fs, FakeAccountSession()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'ABC123');
      await tester.tap(find.text('Join'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('PAGE:dashboard'), findsOneWidget);
      expect(await inviteStatus(fs), 'accepted');
    });
  });
}
