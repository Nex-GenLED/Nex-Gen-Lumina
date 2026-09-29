// Item 9c — the two Lumina conversation surfaces this package owns, run
// through the shared text-scale harness at 1.0x, 1.75x and 2.0x with Bold
// Text on (test/helpers/text_scale_harness.dart; docs/ACCESSIBILITY_TEXT_SCALE_TESTING.md).
//
// States covered: the empty surface, a conversation with a reply card, and
// the thinking indicator — for the full screen and for the sheet in each of
// its three sizes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/features/ai/lumina_ai_screen.dart';
import 'package:nexgen_command/features/ai/lumina_bottom_sheet.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/text_scale_harness.dart';

class _SeededSheet extends LuminaSheetController {
  _SeededSheet(this._seed);
  final LuminaSheetState _seed;
  @override
  LuminaSheetState build() => _seed;
}

class _StillWled extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

const _preview = LuminaPatternPreview(
  patternName: 'Harvest Glow Evening Chase',
  colors: [Color(0xFFFF8800), Color(0xFFFFD27F), Color(0xFF7A2E00)],
  colorNames: ['Pumpkin Orange', 'Harvest Gold', 'Deep Amber'],
  effectId: 28,
  effectName: 'Chase',
  speed: 140,
  intensity: 128,
);

// isOpen stays false: showLuminaSheet refuses to open a sheet it believes is
// already open.
LuminaSheetState _conversation({bool thinking = false}) => LuminaSheetState(
      mode: LuminaSheetMode.expanded,
      isThinking: thinking,
      messages: [
        LuminaMessage.user(
            'Make the whole house look like a warm autumn evening with a slow '
            'chase along the roofline'),
        LuminaMessage.assistant(
          "Here's a warm autumn look — pumpkin orange and harvest gold "
          'chasing slowly along your roofline, with a deep amber background.',
          preview: _preview,
          wledPayload: const {
            'on': true,
            'seg': [
              {
                'fx': 28,
                'sx': 140,
                'col': [
                  [255, 136, 0, 0],
                  [255, 210, 127, 0],
                  [122, 46, 0, 0],
                ],
              },
            ],
          },
        ),
        if (thinking) LuminaMessage.user('Can it be a little slower?'),
        if (thinking) LuminaMessage.thinking(),
      ],
    );

List<Override> _overrides(LuminaSheetState seed) => [
      luminaSheetProvider.overrideWith(() => _SeededSheet(seed)),
      wledStateProvider.overrideWith(() => _StillWled()),
      wledRepositoryProvider.overrideWith((ref) => null),
      authStateProvider.overrideWith((ref) => Stream.value(null)),
      demoModeProvider.overrideWith((ref) => false),
    ];

/// Opens the real sheet, the way the dock does, once the host is on screen.
class _SheetHost extends ConsumerStatefulWidget {
  const _SheetHost(this.mode);
  final LuminaSheetMode mode;
  @override
  ConsumerState<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends ConsumerState<_SheetHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final open = showLuminaSheet(
        context,
        ref,
        mode: widget.mode == LuminaSheetMode.listening
            ? LuminaSheetMode.listening
            : LuminaSheetMode.compact,
      );
      if (widget.mode == LuminaSheetMode.expanded) {
        ref.read(luminaSheetProvider.notifier).setMode(LuminaSheetMode.expanded);
      }
      await open;
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

const Duration _defaultSettle = Duration(milliseconds: 500);

/// Long enough, over six frames, for the sheet's entrance animation.
const Duration _routeSettle = Duration(milliseconds: 900);

/// Set when a test should print, not fail — the pre-fix inventory.
const bool _inventoryOnly =
    bool.fromEnvironment('LUMINA_TEXT_SCALE_INVENTORY');

Future<void> _check(
  WidgetTester tester,
  String name,
  Widget widget, {
  TextScaleHost host = TextScaleHost.screen,
  bool opensRoute = false,
}) async {
  if (_inventoryOnly) {
    final reports =
        await pumpAcrossTextScaleMatrix(tester, widget,
            host: host,
            settle: opensRoute ? _routeSettle : _defaultSettle,
            frames: opensRoute ? 6 : 1);
    final failure = describeTextScaleMatrixFailures(reports);
    // ignore: avoid_print
    print('=== $name\n${failure ?? 'clean'}');
    return;
  }
  await expectNoTextScaleDefectsAcrossMatrix(tester, widget,
      host: host,
      settle: opensRoute ? _routeSettle : _defaultSettle,
      frames: opensRoute ? 6 : 1);
}

/// The sheet is a modal ROUTE, pushed onto the app's navigator — above any
/// `home:`. So the ProviderScope must sit above the MaterialApp, which the
/// test therefore owns, with the app-root cap installed as the app does.
Widget _sheetApp(LuminaSheetState seed, LuminaSheetMode mode) => ProviderScope(
      overrides: _overrides(seed),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: nexGenPremiumDarkTheme,
        builder: TextScaleClamp.appBuilder,
        home: _SheetHost(mode),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Lumina full screen', () {
    testWidgets('empty', (tester) async {
      await _check(
        tester,
        'screen / empty',
        ProviderScope(
          overrides: _overrides(const LuminaSheetState()),
          child: const LuminaAIScreen(),
        ),
      );
    });

    testWidgets('a conversation with a reply card', (tester) async {
      await _check(
        tester,
        'screen / conversation',
        ProviderScope(
          overrides: _overrides(_conversation()),
          child: const LuminaAIScreen(),
        ),
      );
    });

    testWidgets('thinking', (tester) async {
      await _check(
        tester,
        'screen / thinking',
        ProviderScope(
          overrides: _overrides(_conversation(thinking: true)),
          child: const LuminaAIScreen(),
        ),
      );
    });
  });

  group('Lumina sheet', () {
    for (final mode in LuminaSheetMode.values) {
      testWidgets('empty, ${mode.name}', (tester) async {
        await _check(
          tester,
          'sheet / empty / ${mode.name}',
          _sheetApp(const LuminaSheetState(), mode),
          host: TextScaleHost.none,
          opensRoute: true,
        );
      });
    }

    testWidgets('a conversation with a reply card, expanded', (tester) async {
      await _check(
        tester,
        'sheet / conversation / expanded',
        _sheetApp(_conversation(), LuminaSheetMode.expanded),
        host: TextScaleHost.none,
        opensRoute: true,
      );
    });

    testWidgets('thinking, expanded', (tester) async {
      await _check(
        tester,
        'sheet / thinking / expanded',
        _sheetApp(_conversation(thinking: true), LuminaSheetMode.expanded),
        host: TextScaleHost.none,
        opensRoute: true,
      );
    });
  });
}
