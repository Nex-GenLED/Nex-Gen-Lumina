// +126 (g) — the schedule editor sheet, with its new plain-words line under
// the wheels, through the +120 large-text matrix (1.0 / 1.3 / 1.6 / 2.0 at
// 320 / 375 / 390 / 430 pt). The sheet is the tightest surface on the
// schedule tab at 2.0x, and the line wraps freely, so the gate here is the
// matrix's own: no exception and no RenderFlex overflow in any cell.

import 'package:flutter/material.dart';
import 'package:nexgen_command/utils/time_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart'
    show selectedDeviceIpProvider;
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/wled/clock_health_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/large_text_matrix.dart';
import '../../helpers/recording_wled_repository.dart';
import '../../helpers/text_scale_harness.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

ScheduleItem _overnight() => const ScheduleItem(
      id: 's1',
      timeLabel: '5:00 PM',
      offTimeLabel: '6:00 AM',
      repeatDays: _days,
      actionLabel: 'Pattern: Classic Christmas 2',
      enabled: true,
    );

/// A page that opens the editor on [editing] on its first frame.
class _OpensEditor extends ConsumerStatefulWidget {
  const _OpensEditor(this.editing);
  final ScheduleItem editing;

  @override
  ConsumerState<_OpensEditor> createState() => _OpensEditorState();
}

class _OpensEditorState extends ConsumerState<_OpensEditor> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showScheduleEditor(context, ref, editing: widget.editing);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

List<Override> _overrides(ScheduleItem editing) => [
      ...homeDashboardOverrides(repo: RecordingWledRepository()),
      userSchedulesStreamProvider.overrideWith((ref) => Stream.value([editing])),
      gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
      gameDayAutopilotConfigsProvider
          .overrideWith((_) => Stream.value(const <GameDayAutopilotConfig>[])),
      solarSchedulingEnabledProvider.overrideWith((_) => Stream.value(false)),
      clockHealthProvider.overrideWith((_) async => null),
      selectedDeviceIpProvider.overrideWith((ref) => null),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Schedule editor sheet: no overflow across the matrix',
      (tester) async {
    await expectNoOverflowAcrossLargeTextMatrix(
      tester,
      () => largeTextHost(
        overrides: _overrides(_overnight()),
        page: _OpensEditor(_overnight()),
        dock: 1,
      ),
      label: 'schedule editor',
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
    // The matrix tears each cell down; open one more at the tightest cell
    // (320 pt, 2.0x) and check the sheet and the line really were in it.
    await pumpAtTextScale(
      tester,
      largeTextHost(
        overrides: _overrides(_overnight()),
        page: _OpensEditor(_overnight()),
        dock: 1,
      ),
      profile: const TextScaleProfile(
        textScale: 2.0,
        boldText: false,
        screenSize: Size(320, 568),
        devicePixelRatio: 2.0,
        safeArea: EdgeInsets.only(top: 20),
      ),
      host: TextScaleHost.none,
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
    expect(find.byType(BottomSheet), findsOneWidget,
        reason: 'the sheet was open and measured, not the page behind it');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  // The line itself, at the foundation matrix (1.0 / 1.75 / 2.0, Bold Text):
  // the longest wording the helper produces, wrapping freely.
  testWidgets('the plain-words line survives large text', (tester) async {
    final longest = scheduleWindowSentence(
      onLabel: '12:00 PM',
      offLabel: '12:00 AM',
      offNextDay: true,
    );
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(longest, softWrap: true),
      ),
    );
  });
}
