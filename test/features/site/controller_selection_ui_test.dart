// #118 — the controls for choosing a controller.
//
// "Set as Active" is now "Use this controller", offered only when there is a
// choice (two or more records), with the active record marked by its id. The
// "Which controller should this phone use?" prompt appears only when two or
// more controllers answer and nothing else says which one this phone uses.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controller_choice_prompt.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/manage_controllers_page.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/system_management_screen.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

import '../../helpers/home_dashboard_harness.dart' show SeededWledNotifier;
import '../../helpers/text_scale_harness.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'account-a';
  @override
  String? get email => null;
}

class _MemoryStore implements ControllerSelectionStore {
  _MemoryStore([this.saved]);
  String? saved;
  @override
  Future<String?> readSelected(String uid) async => saved;
  @override
  Future<void> writeSelected(String uid, String? id) async => saved = id;
  @override
  Future<Map<String, DateTime>> readConnected(String uid) async => {};
  @override
  Future<void> writeConnected(String uid, Map<String, DateTime> s) async {}
}

// Plain record ids and documentation addresses.
const _front = ControllerInfo(id: 'front', ip: '192.0.2.10', name: 'Front');
const _back = ControllerInfo(id: 'back', ip: '192.0.2.11', name: 'Back');

/// The app shell arms auto-selection, as MainScaffold does.
class _Shell extends ConsumerWidget {
  const _Shell(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoConnectControllerProvider);
    return child;
  }
}

List<Override> _overrides({
  required List<ControllerInfo> records,
  String? saved,
  Set<String> answering = const {},
}) =>
    [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(_User())),
      // Per account, as the real stream is: it re-delivers when the signed-in
      // account changes (the selection discards the previous account's list).
      controllersStreamProvider.overrideWith((ref) {
        ref.watch(effectiveUserUidProvider);
        return Stream.value(records);
      }),
      controllersFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
      controllerSelectionStoreProvider.overrideWithValue(_MemoryStore(saved)),
      controllerReachabilityProbeProvider
          .overrideWithValue((ip) async => answering.contains(ip)),
      wledStateProvider
          .overrideWith(() => SeededWledNotifier(WledStateModel.initial())),
    ];

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget page, {
  required List<ControllerInfo> records,
  String? saved,
  Set<String> answering = const {},
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides:
        _overrides(records: records, saved: saved, answering: answering),
    child: MaterialApp(home: _Shell(page)),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return ProviderScope.containerOf(tester.element(find.byWidget(page)));
}

Finder _tileOf(String name, Type tile) =>
    find.ancestor(of: find.text(name), matching: find.byType(tile)).first;

void main() {
  group('Settings → Controllers (ManageControllersPage)', () {
    testWidgets('one record: no "Use this controller" anywhere; the record is '
        'marked active', (tester) async {
      final c = await _pump(tester, const ManageControllersPage(),
          records: const [_front]);
      expect(c.read(selectedControllerIdProvider), 'front');
      expect(find.text('Active'), findsOneWidget);
      expect(find.text(kUseThisControllerLabel), findsNothing);
      expect(find.text('Set as Active'), findsNothing);

      await tester.tap(find.byTooltip('Details'));
      await tester.pumpAndSettle();
      expect(find.text(kUseThisControllerLabel), findsNothing,
          reason: 'one controller is not a choice');
    });

    testWidgets('two records: the active one is marked by id; the other offers '
        '"Use this controller", which switches', (tester) async {
      final c = await _pump(tester, const ManageControllersPage(),
          records: const [_front, _back], saved: 'back');
      expect(c.read(selectedControllerIdProvider), 'back',
          reason: 'the saved choice, not the newest record');
      final backTile = _tileOf('Back', ListTile);
      expect(
          find.descendant(of: backTile, matching: find.text('Active')),
          findsOneWidget);

      // The active one's details offer no switch.
      await tester.tap(find.descendant(
          of: backTile, matching: find.byTooltip('Details')));
      await tester.pumpAndSettle();
      expect(find.text(kUseThisControllerLabel), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: _tileOf('Front', ListTile), matching: find.byTooltip('Details')));
      await tester.pumpAndSettle();
      expect(find.text(kUseThisControllerLabel), findsOneWidget);
      expect(find.text('Set as Active'), findsNothing);
      await tester.tap(find.text(kUseThisControllerLabel));
      await tester.pumpAndSettle();
      expect(c.read(selectedControllerIdProvider), 'front');
      expect(
          find.descendant(
              of: _tileOf('Front', ListTile), matching: find.text('Active')),
          findsOneWidget);
    });
  });

  group('System & Device Management → Controllers', () {
    testWidgets('one record: marked ACTIVE, no "Use this controller"',
        (tester) async {
      await _pump(tester, const SystemManagementScreen(),
          records: const [_front]);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text(kUseThisControllerLabel), findsNothing);
      expect(find.text('Set as Active'), findsNothing);
    });

    testWidgets('two records: "Use this controller" on the other one switches',
        (tester) async {
      final c = await _pump(tester, const SystemManagementScreen(),
          records: const [_front, _back], saved: 'front');
      expect(c.read(selectedControllerIdProvider), 'front');
      expect(find.text('ACTIVE'), findsOneWidget);

      // Tapping the other tile uses it.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(c.read(selectedControllerIdProvider), 'back');
      expect(find.text('Set as Active'), findsNothing);
    });
  });

  group('"Which controller should this phone use?"', () {
    Widget host() => const ControllerChoicePromptHost(
          child: Scaffold(body: SizedBox.expand()),
        );

    testWidgets('two answer → the prompt, and the choice is used',
        (tester) async {
      await _pump(tester, host(),
          records: const [_front, _back],
          answering: {_front.ip, _back.ip});
      await tester.pumpAndSettle();
      expect(find.text('Which controller should this phone use?'),
          findsOneWidget);
      expect(find.text(kUseThisControllerLabel), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('controller-choice-use-back')));
      await tester.pumpAndSettle();
      expect(find.text('Which controller should this phone use?'),
          findsNothing);
      final c = ProviderScope.containerOf(
          tester.element(find.byType(ControllerChoicePromptHost)));
      expect(c.read(selectedControllerIdProvider), 'back');
    });

    testWidgets('one answers → no prompt; that one is used', (tester) async {
      final c = await _pump(tester, host(),
          records: const [_front, _back], answering: {_back.ip});
      await tester.pumpAndSettle();
      expect(find.text('Which controller should this phone use?'),
          findsNothing);
      expect(c.read(selectedControllerIdProvider), 'back');
    });

    testWidgets('none answers (away) → no prompt; the newest is used',
        (tester) async {
      final c = await _pump(tester, host(), records: const [_front, _back]);
      await tester.pumpAndSettle();
      expect(find.text('Which controller should this phone use?'),
          findsNothing);
      expect(c.read(selectedControllerIdProvider), 'front');
    });

    testWidgets('one record → no prompt, whatever answers', (tester) async {
      final c = await _pump(tester, host(),
          records: const [_front], answering: {_front.ip});
      await tester.pumpAndSettle();
      expect(find.text('Which controller should this phone use?'),
          findsNothing);
      expect(c.read(selectedControllerIdProvider), 'front');
    });
  });

  group('large text (1.0 / 1.75 / 2.0, Bold Text on)', () {
    testWidgets('the prompt', (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        ProviderScope(
          overrides: _overrides(
              records: const [_front, _back],
              answering: {_front.ip, _back.ip}),
          child: const _Shell(ControllerChoiceSheet()),
        ),
        settle: const Duration(milliseconds: 300),
        frames: 6,
      );
    });

    testWidgets('the "Use this controller" button in a controller\'s details',
        (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        ProviderScope(
          overrides: _overrides(
              records: const [_front, _back], saved: 'back'),
          child: const _Shell(_OpenFrontDetails(child: ManageControllersPage())),
        ),
        host: TextScaleHost.screen,
        settle: const Duration(milliseconds: 900),
        frames: 6,
      );
    });
  });
}

/// Opens the real details dialog of the "Front" tile on the first frame, the
/// way a tap would, so the harness measures the dialog and its button.
class _OpenFrontDetails extends StatefulWidget {
  const _OpenFrontDetails({required this.child});
  final Widget child;
  @override
  State<_OpenFrontDetails> createState() => _OpenFrontDetailsState();
}

class _OpenFrontDetailsState extends State<_OpenFrontDetails> {
  @override
  void initState() {
    super.initState();
    // After the controller list has arrived and the tiles are built.
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      final details = find.descendant(
        of: find.ancestor(of: find.text('Front'), matching: find.byType(ListTile)),
        matching: find.byTooltip('Details'),
      );
      final candidates = details.evaluate();
      if (candidates.isEmpty) return;
      final button = candidates.first.findAncestorWidgetOfExactType<IconButton>();
      button?.onPressed?.call();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
