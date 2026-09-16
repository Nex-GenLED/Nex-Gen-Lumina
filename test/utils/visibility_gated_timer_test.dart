import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/utils/visibility_gated_timer.dart';

/// #112 — the gated timer must stop in every "not on screen" condition and
/// resume when the screen comes back.
class _Harness extends StatefulWidget {
  const _Harness({required this.onTick, this.wanted = true});
  final VoidCallback onTick;
  final bool wanted;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with WidgetsBindingObserver {
  late final VisibilityGatedTimer timer = VisibilityGatedTimer(
    period: const Duration(seconds: 30),
    onTick: () => widget.onTick(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer.setWanted(widget.wanted);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    timer.updateFromContext(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      timer.setAppLifecycleState(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('harness');
}

void main() {
  test('shouldRun requires all four conditions', () {
    for (final wanted in [true, false]) {
      for (final resumed in [true, false]) {
        for (final ticker in [true, false]) {
          for (final current in [true, false]) {
            expect(
              VisibilityGatedTimer.shouldRun(
                wanted: wanted,
                appResumed: resumed,
                tickerEnabled: ticker,
                routeIsCurrent: current,
              ),
              wanted && resumed && ticker && current,
            );
          }
        }
      }
    }
  });

  testWidgets('ticks every period while visible', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(MaterialApp(home: _Harness(onTick: () => ticks++)));
    await tester.pump(const Duration(seconds: 29));
    expect(ticks, 0, reason: 'no immediate tick');
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TAB SWITCHED AWAY (TickerMode off) stops it; returning resumes',
      (tester) async {
    var ticks = 0;
    final active = ValueNotifier<bool>(true);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (_, on, __) =>
            TickerMode(enabled: on, child: _Harness(onTick: () => ticks++)),
      ),
    ));
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 1);

    active.value = false;
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(ticks, 1, reason: 'no ticks while the tab is inactive');

    active.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('BACKGROUNDED stops it; resumed restarts it', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(MaterialApp(home: _Harness(onTick: () => ticks++)));

    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(minutes: 5));
    expect(ticks, 0, reason: 'no ticks while backgrounded');

    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('COVERED by another route stops it; popping back resumes',
      (tester) async {
    var ticks = 0;
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: _Harness(onTick: () => ticks++),
    ));

    navKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const Text('other')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 5));
    expect(ticks, 0, reason: 'no ticks while another route is on top');

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SCREEN CLOSED cancels it for good', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(MaterialApp(home: _Harness(onTick: () => ticks++)));
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
    expect(ticks, 1);
  });

  testWidgets('not wanted → never ticks, even when visible', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(
        MaterialApp(home: _Harness(onTick: () => ticks++, wanted: false)));
    await tester.pump(const Duration(minutes: 5));
    expect(ticks, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
