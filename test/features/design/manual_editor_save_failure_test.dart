// F6 — a failed Save is no longer silent.
//
// The paint editor's _save() was try/finally with NO catch and DesignService
// rethrows, so a denied write (e.g. an installer on a customer's account, where
// the live `designs` rule was owner-only) showed NOTHING: buttons greyed, came
// back, and the design was not in My Designs.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_save_errors.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

class _ThrowingDesignService implements DesignService {
  _ThrowingDesignService(this.error);
  final Object error;
  CustomDesign? attempted;

  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    attempted = design;
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OkDesignService implements DesignService {
  CustomDesign? saved;
  String? savedUnder;
  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    saved = design;
    savedUnder = userId;
    return 'new-id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpEditor(WidgetTester tester, DesignService service,
    {String? uid = 'customer-uid'}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      designServiceProvider.overrideWithValue(service),
      designsStreamProvider.overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue(uid),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
      houseImageUrlProvider.overrideWithValue(null),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 40, gpioPin: 2),
      ]),
    ],
    child: const MaterialApp(home: Scaffold(body: ManualDesignEditor())),
  ));
  await tester.pump();
}

Future<void> _pressSaveAndName(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
  await tester.pumpAndSettle();
  // "Name This Design" dialog → its own Save.
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('describeDesignSaveError', () {
    FirebaseException fx(String code) => FirebaseException(plugin: 'cloud_firestore', code: code);

    test('permission-denied names the real cause', () {
      final m = describeDesignSaveError(fx('permission-denied'), isEdit: false);
      expect(m, contains("don't have permission"));
      expect(m, contains('nothing was saved'));
    });

    test('not-found on an edit = deleted elsewhere', () {
      expect(describeDesignSaveError(fx('not-found'), isEdit: true),
          contains('deleted on another device'));
    });

    test('network-class errors say to retry', () {
      for (final c in ['unavailable', 'deadline-exceeded']) {
        expect(describeDesignSaveError(fx(c), isEdit: false), contains('connection'));
      }
    });

    test('anything else still says NOTHING WAS SAVED', () {
      expect(describeDesignSaveError(StateError('x'), isEdit: false),
          contains('nothing was saved'));
    });
  });

  testWidgets('a denied save shows an error — and no success toast', (tester) async {
    final service = _ThrowingDesignService(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    await _pumpEditor(tester, service);
    await _pressSaveAndName(tester);

    expect(service.attempted, isNotNull, reason: 'the write was attempted');
    expect(find.textContaining("don't have permission"), findsOneWidget);
    expect(find.textContaining('to My Designs'), findsNothing);
    // The buttons come back (busy flag cleared) so the user can act.
    final save = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Save'));
    expect(save.onPressed, isNotNull);
  });

  testWidgets('a successful save is stamped per-pixel and goes to effectiveUserUid',
      (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service);
    await _pressSaveAndName(tester);

    expect(service.savedUnder, 'customer-uid');
    expect(service.saved!.perPixel, isTrue,
        reason: 'a blank/one-colour painted design must still open in the paint editor');
    expect(find.textContaining('to My Designs'), findsOneWidget);
  });

  testWidgets('signed out → says so instead of silently returning', (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service, uid: null);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sign in to save'), findsOneWidget);
    expect(service.saved, isNull);
  });
}
