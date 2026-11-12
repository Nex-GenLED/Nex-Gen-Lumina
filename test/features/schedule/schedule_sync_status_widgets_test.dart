// +126 (c) — the status row on My Schedule and the chip on Home, in every
// state, with Retry, and through the text-scale matrix at 1.0 / 1.75 / 2.0.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync_status.dart';
import 'package:nexgen_command/features/schedule/widgets/schedule_sync_status_row.dart';
import 'package:nexgen_command/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/text_scale_harness.dart';

class _Seeded extends ScheduleSyncStatusNotifier {
  _Seeded(ScheduleSyncStatus? s)
      : super(const ScheduleSyncStatusStore(), null) {
    state = s;
  }
}

ScheduleSyncStatus _status(ScheduleSyncState s) => ScheduleSyncStatus(
      state: s,
      at: DateTime.now().subtract(const Duration(minutes: 5)),
      unconvergedPresetIds:
          s == ScheduleSyncState.writtenNotVerified ? const [10] : const [],
      scheduleCount: 2,
    );

List<Override> _overrides(ScheduleSyncStatus? s) => [
      scheduleSyncStatusProvider.overrideWith((ref) => _Seeded(s)),
      effectiveUserUidProvider.overrideWithValue('u1'),
    ];

Widget _host(ScheduleSyncStatus? s, Widget child) => ProviderScope(
      overrides: _overrides(s),
      child: MaterialApp(
        theme: nexGenPremiumDarkTheme,
        home: Scaffold(body: Column(children: [child])),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('status row', () {
    testWidgets('renders nothing before the account has ever synced',
        (tester) async {
      await tester.pumpWidget(_host(null, const ScheduleSyncStatusRow()));
      expect(find.byKey(const ValueKey('schedule-sync-status-row')),
          findsNothing);
    });

    for (final s in ScheduleSyncState.values) {
      testWidgets('state ${s.name}: headline, detail, time and Retry',
          (tester) async {
        final copy = ScheduleSyncCopy.forState(s);
        await tester.pumpWidget(_host(_status(s), const ScheduleSyncStatusRow()));
        final text =
            tester.widget<Text>(find.descendant(
              of: find.byKey(const ValueKey('schedule-sync-status-row')),
              matching: find.byType(Text),
            ).first).data!;
        expect(text, contains(copy.headline));
        if (copy.detail.isNotEmpty) expect(text, contains(copy.detail));
        expect(text, contains('5m ago'));
        expect(find.byKey(const ValueKey('schedule-sync-retry')),
            copy.showsRetry ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('Retry runs the manual sync', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_host(
        _status(ScheduleSyncState.failed),
        ScheduleSyncStatusRow(onRetry: (_) async => retries++),
      ));
      await tester.tap(find.byKey(const ValueKey('schedule-sync-retry')));
      await tester.pump();
      expect(retries, 1);
    });
  });

  group('Home chip', () {
    testWidgets('renders nothing before the account has ever synced',
        (tester) async {
      await tester.pumpWidget(_host(null, const ScheduleSyncHomeChip()));
      expect(find.byKey(const ValueKey('schedule-sync-home-chip')),
          findsNothing);
    });

    for (final s in ScheduleSyncState.values) {
      testWidgets('state ${s.name}: headline and Retry', (tester) async {
        final copy = ScheduleSyncCopy.forState(s);
        await tester.pumpWidget(_host(_status(s), const ScheduleSyncHomeChip()));
        expect(find.text(copy.headline), findsOneWidget);
        expect(find.byKey(const ValueKey('schedule-sync-chip-retry')),
            copy.showsRetry ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('Retry runs the manual sync', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_host(
        _status(ScheduleSyncState.deferredOffLan),
        ScheduleSyncHomeChip(onRetry: (_) async => retries++),
      ));
      await tester.tap(find.byKey(const ValueKey('schedule-sync-chip-retry')));
      await tester.pump();
      expect(retries, 1);
    });
  });

  group('text scale (1.0 / 1.75 / 2.0, Bold Text)', () {
    for (final s in ScheduleSyncState.values) {
      testWidgets('row — ${s.name}', (tester) async {
        await expectNoTextScaleDefectsAcrossMatrix(
          tester,
          ProviderScope(
            overrides: _overrides(_status(s)),
            child: const ScheduleSyncStatusRow(),
          ),
        );
      });

      testWidgets('chip — ${s.name}', (tester) async {
        await expectNoTextScaleDefectsAcrossMatrix(
          tester,
          ProviderScope(
            overrides: _overrides(_status(s)),
            child: const ScheduleSyncHomeChip(),
          ),
        );
      });
    }
  });
}
