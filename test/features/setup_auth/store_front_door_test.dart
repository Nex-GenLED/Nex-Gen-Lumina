// +110 package G, follow-up 3 — the store front door.
//
// Lumina is professionally installed. Nobody signs themselves up from the
// store listing (1), and a signed-in but unlinked customer is told plainly
// what is going on, who to contact, and offered the demo (2).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/features/auth/link_account_screen.dart';
import 'package:nexgen_command/features/auth/login_page.dart';
import 'package:nexgen_command/features/auth/staff_pin_screen.dart';
import 'package:nexgen_command/features/auth/support_contact.dart';
import 'package:nexgen_command/features/dashboard/main_scaffold.dart'
    show showDemoExitSheet;
import 'package:nexgen_command/features/demo/demo_code_screen.dart';
import 'package:nexgen_command/features/demo/demo_completion_screen.dart';
import 'package:nexgen_command/features/demo/demo_lead_service.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/dealer_demo_code.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:nexgen_command/services/demo_code_service.dart';

import 'setup_auth_fixtures.dart';

class _StillWled extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _FakeDemoCodes extends DemoCodeService {
  @override
  Future<DealerDemoCode?> validateCode(String code) async =>
      code.trim().toUpperCase() == 'DEMO01'
          ? DealerDemoCode(
              code: 'DEMO01',
              dealerCode: 'DLR',
              dealerName: 'Test Dealer',
              market: 'Test',
              createdAt: DateTime.utc(2026, 9, 29),
            )
          : null;
}

UserModel _unlinked({
  String? dealerCode,
  String? dealerName,
  String? dealerPhone,
  String? dealerEmail,
}) =>
    UserModel(
      id: kTestUid,
      email: kTestEmail,
      displayName: 'Pat',
      ownerId: kTestUid,
      createdAt: DateTime.utc(2026, 9, 29),
      updatedAt: DateTime.utc(2026, 9, 29),
      installationRole: InstallationRole.unlinked,
      dealerCode: dealerCode,
      dealerName: dealerName,
      dealerPhone: dealerPhone,
      dealerEmail: dealerEmail,
    );

/// [screen] at `/screen`, with stubs (or real screens) where it sends people.
Widget _app(
  Widget screen,
  ProviderContainer container, {
  Map<String, Widget Function()> real = const {},
}) {
  Widget stub(String name) => Scaffold(body: Center(child: Text('PAGE:$name')));
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final path in [
        AppRoutes.dashboard,
        AppRoutes.login,
        AppRoutes.demoCode,
        AppRoutes.demoWelcome,
        AppRoutes.demoPhoto,
        AppRoutes.demoComplete,
        AppRoutes.joinWithCode,
        AppRoutes.staffPin,
        AppRoutes.forgotPassword,
      ])
        GoRoute(
          path: path,
          builder: (_, __) => real[path]?.call() ?? stub(path),
        ),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  // ── 1. No self-signup anywhere ────────────────────────────────────────────
  group('1 — nobody can create an account from the app', () {
    testWidgets(
        'login keeps sign in, forgot password and the demo; no "Create One"',
        (tester) async {
      final container = ProviderContainer(overrides: [
        accountSessionProvider
            .overrideWithValue(FakeAccountSession(isSignedIn: false)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(const LoginScreen(), container));
      await tester.pumpAndSettle();

      expect(find.text('ENTER LUMINA'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Experience Nex-Gen Demo'), findsOneWidget);
      expect(find.text('Create One'), findsNothing);
      expect(find.textContaining("Don't have an account"), findsNothing);
      expect(find.textContaining('Create an account'), findsNothing);
      expect(find.textContaining('Sign up'), findsNothing);
    });

    testWidgets('the demo exit sheet offers a consultation, not an account',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showDemoExitSheet(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Request a free consultation'), findsOneWidget);
      expect(find.textContaining('Create an account'), findsNothing);
    });

    testWidgets('the demo completion screen has no "Create an account"',
        (tester) async {
      final container = ProviderContainer(overrides: [
        wledStateProvider.overrideWith(_StillWled.new),
        demoLeadServiceProvider.overrideWithValue(
            DemoLeadService(firestore: FakeFirebaseFirestore())),
      ]);
      addTearDown(container.dispose);
      // The screen lives inside a running demo; its providers short-circuit
      // to demo state only while one is active.
      container.read(demoSessionProvider.notifier).startDemo();
      await tester.pumpWidget(_app(const DemoCompletionScreen(), container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Request Free Consultation'), findsOneWidget);
      expect(find.text('Return to Login'), findsOneWidget);
      expect(find.textContaining('Create an account'), findsNothing);
    });
  });

  // ── 2. The unlinked customer's screen ─────────────────────────────────────
  group('2 — a signed-in but unlinked customer', () {
    late List<Uri> opened;

    ProviderContainer scope({
      UserModel? profile,
      bool openerFails = false,
      FakeAccountSession? session,
    }) {
      opened = [];
      // The store holds no /dealers record on purpose: the screen must
      // resolve the contact from the profile alone.
      final fs = FakeFirebaseFirestore();
      final c = ProviderContainer(overrides: [
        accountSessionProvider
            .overrideWithValue(session ?? FakeAccountSession()),
        accountFirestoreProvider.overrideWithValue(fs),
        currentUserProfileProvider
            .overrideWith((ref) => Stream.value(profile ?? _unlinked())),
        externalLinkOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return !openerFails;
        }),
        demoCodeServiceProvider.overrideWithValue(_FakeDemoCodes()),
        demoLeadServiceProvider.overrideWithValue(
            DemoLeadService(firestore: FakeFirebaseFirestore())),
        wledStateProvider.overrideWith(_StillWled.new),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> open(WidgetTester tester, ProviderContainer c,
        {Map<String, Widget Function()> real = const {}}) async {
      await tester.pumpWidget(_app(const LinkAccountScreen(), c, real: real));
      await tester.pumpAndSettle();
    }

    /// The page scrolls; bring [finder] on screen, then tap it.
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
    }

    testWidgets(
        'sees the explanation, a contact, and the demo; nothing about '
        'setting up a controller', (tester) async {
      await open(tester, scope());

      expect(find.byKey(const ValueKey('link-explanation')), findsOneWidget);
      expect(find.text(LinkAccountScreen.explanation), findsOneWidget);
      expect(find.byKey(const ValueKey('link-contact-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('link-demo')), findsOneWidget);
      expect(find.text('Explore the demo'), findsOneWidget);
      expect(find.byKey(const ValueKey('link-invitation-code')), findsOneWidget);
      expect(find.text('Installer'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);

      expect(find.textContaining('Set up'), findsNothing);
      expect(find.textContaining('set up my own'), findsNothing);
      expect(find.textContaining('controller'), findsNothing);
      // No blame.
      expect(find.textContaining('wrong'), findsNothing);
      expect(find.textContaining('invalid'), findsNothing);
    });

    testWidgets(
        'with no dealer contact on the profile, the card is Nex-Gen LED: '
        'Call 816-408-0177 and general@nex-genled.com', (tester) async {
      await open(tester, scope());

      expect(find.text(kNexGenCorporateContact.name), findsOneWidget);
      expect(find.text('Call $kNexGenCorporatePhone'), findsOneWidget);
      expect(find.text('Email $kNexGenCorporateEmail'), findsOneWidget);
      expect(find.byKey(const ValueKey('link-contact-web')), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey('link-contact-call')));
      await tester.pump();
      expect(opened.single.toString(), 'tel:8164080177');

      await tapVisible(tester, find.byKey(const ValueKey('link-contact-email')));
      await tester.pump();
      expect(opened.last.toString(), 'mailto:general@nex-genled.com');
    });

    testWidgets(
        "with the dealer's contact on the profile, the card is the dealer's, "
        'by phone and email; no /dealers read', (tester) async {
      await open(
        tester,
        scope(
          profile: _unlinked(
            dealerCode: '07',
            dealerName: 'Bright Homes LED',
            dealerPhone: '(555) 010-0100',
            dealerEmail: 'hello@example.com',
          ),
        ),
      );

      expect(find.text('Your installer'), findsOneWidget);
      expect(find.text('Bright Homes LED'), findsOneWidget);
      expect(find.text(kNexGenCorporateContact.name), findsNothing);
      expect(find.text('Call (555) 010-0100'), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey('link-contact-call')));
      await tester.pump();
      expect(opened.single.toString(), 'tel:5550100100');

      await tapVisible(tester, find.byKey(const ValueKey('link-contact-email')));
      await tester.pump();
      expect(opened.last.toString(), 'mailto:hello@example.com');
    });

    testWidgets(
        'a dealer_code alone (every profile provisioned before +110) shows '
        'Nex-Gen LED', (tester) async {
      await open(tester, scope(profile: _unlinked(dealerCode: '01')));
      expect(find.text(kNexGenCorporateContact.name), findsOneWidget);
      expect(find.text('Your installer'), findsNothing);
    });

    testWidgets(
        'a dealer name with neither phone nor email (the incomplete live '
        'record) shows Nex-Gen LED', (tester) async {
      await open(
        tester,
        scope(profile: _unlinked(dealerCode: '02', dealerName: 'No Contact')),
      );
      expect(find.text(kNexGenCorporateContact.name), findsOneWidget);
      expect(find.text('No Contact'), findsNothing);
    });

    testWidgets('an unlinked customer is never offered Manage Family Members',
        (tester) async {
      await open(tester, scope());
      expect(find.textContaining('Family'), findsNothing);
      expect(find.textContaining('Manage'), findsNothing);
    });

    testWidgets("a failed open leaves the contact on screen and says so",
        (tester) async {
      await open(tester, scope(openerFails: true));
      await tapVisible(tester, find.byKey(const ValueKey('link-contact-email')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining("Couldn't open that"), findsOneWidget);
      expect(find.textContaining(kNexGenCorporateContact.email!),
          findsWidgets);
    });

    testWidgets('demo mode opens from here and starts a demo session',
        (tester) async {
      final c = scope();
      await open(tester, c,
          real: {AppRoutes.demoCode: () => const DemoCodeScreen()});

      await tapVisible(tester, find.byKey(const ValueKey('link-demo')));
      await tester.pumpAndSettle();
      expect(find.text('Start Demo'), findsOneWidget, reason: 'demo gate');

      await tester.enterText(find.byType(TextField), 'DEMO01');
      await tester.tap(find.text('Start Demo'));
      await tester.pumpAndSettle();

      expect(find.text('PAGE:${AppRoutes.demoWelcome}'), findsOneWidget);
      expect(c.read(demoSessionProvider), isTrue);
      expect(c.read(demoExperienceActiveProvider), isTrue);
    });

    testWidgets(
        'row 16 stays fixed: opening and closing the staff PIN screen never '
        "touches the customer's session, and the demo still opens after",
        (tester) async {
      final session = FakeAccountSession();
      final c = scope(session: session);
      await open(tester, c, real: {
        AppRoutes.staffPin: () => const StaffPinScreen(),
        AppRoutes.demoCode: () => const DemoCodeScreen(),
      });

      await tapVisible(tester, find.text('Installer'));
      await tester.pumpAndSettle();
      expect(find.text('Staff Access'), findsOneWidget);
      expect(session.anonymousSignIns, 0,
          reason: 'a signed-in customer needs no anonymous session');

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(session.signOutCalls, 0);
      expect(find.text('Welcome to Lumina'), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey('link-demo')));
      await tester.pumpAndSettle();
      expect(find.text('Start Demo'), findsOneWidget);
    });
  });
}
