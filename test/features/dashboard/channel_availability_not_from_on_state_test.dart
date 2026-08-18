// #95 PIN — a channel being OFF must never read as a channel being GONE.
//
// THE REGRESSION THIS EXISTS TO CATCH (found in +78 post-smoke hardware
// testing, and release-blocking):
//
// #89 made the #67 full partition interactive, so a design that leaves a
// channel out now correctly writes `{id, on:false}` for it — the channel goes
// DARK instead of silently keeping its old look. Correct on the wire, and the
// bench confirmed the device state was healthy (seg present, bounds 128/290/162
// intact, rev:true intact, exactly on:false).
//
// But the dashboard chip for a NON-PARTICIPATING channel rendered greyed, with
// a strikethrough, no selection tap, AND — the actual lockout — its power icon
// suppressed by `&& !disabled`. Dark plus no control of any kind reads as "this
// channel is gone", and there was no way back except applying another design
// that happened to target it.
//
// So the pin is about AFFORDANCE, not about the write: whatever a channel's
// on-state or participation, the device reported that channel, so the user must
// always be able to wake it by hand.
//
// A test's value is its ability to fail. Re-adding `&& !disabled` to the power
// icon, or deriving the chip's interactivity from `channelOn`, fails this.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _twoChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];

/// Channel 0 lit, channel 1 dark — exactly the post-single-channel-apply state
/// the bench produced.
List<Override> _overrides({required List<int>? participating}) => [
      deviceChannelsProvider.overrideWithValue(_twoChannels),
      participatingChannelIdsProvider.overrideWithValue(participating),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
      // Returned synchronously (FutureProvider takes a FutureOr) so the chips
      // see resolved power states on their first build — an unresolved map
      // yields channelOn:null, which hides the power icon for an unrelated
      // reason and would make these pins pass vacuously.
      channelPowerStatesProvider.overrideWith((ref) => const {0: true, 1: false}),
    ];

Future<void> _pumpExpanded(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ChannelSelectorBar())),
    ),
  );
  await tester.pumpAndSettle();

  // Expand the bar so the chips render. The power-state provider is only
  // watched from inside the chip builder, so it does not resolve until here.
  //
  // textContaining, not text: the header now appends "· N of M in shows"
  // whenever participation narrows (#95 item 3), which is precisely the
  // participating:[0] case two of these pins run. An exact-match finder here
  // made those two fail for a reason that has nothing to do with affordances.
  await tester.tap(find.textContaining('All Channels'));
  await tester.pumpAndSettle();

  // Guard against a vacuous pass: if the chips or the power states are missing,
  // "0 icons" would look like a UI regression when it is really a broken setup.
  expect(find.text('Channel 2'), findsOneWidget,
      reason: 'chips must be rendered before asserting on their affordances');
  expect(c.read(channelPowerStatesProvider).valueOrNull, isNotNull,
      reason: 'power states must be resolved or these pins prove nothing');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
      'an OFF channel keeps its power control — off is not gone',
      (tester) async {
    final c = ProviderContainer(overrides: _overrides(participating: null));
    addTearDown(c.dispose);

    await _pumpExpanded(tester, c);

    // Both channels expose a power control, including the dark one.
    expect(
      find.byIcon(Icons.power_settings_new),
      findsNWidgets(2),
      reason: 'channel 1 is off, not absent — it must still be wakeable',
    );
  });

  testWidgets(
      'a NON-PARTICIPATING channel still keeps its power control',
      (tester) async {
    // Channel 1 is out of shows AND dark — the exact bench combination.
    final c = ProviderContainer(overrides: _overrides(participating: [0]));
    addTearDown(c.dispose);

    await _pumpExpanded(tester, c);

    expect(
      find.byIcon(Icons.power_settings_new),
      findsNWidgets(2),
      reason: 'participation scopes SHOWS; it must not remove manual control '
          'of hardware the device reports (#95 — the release-blocking lockout '
          'was `&& !disabled` on this icon)',
    );
  });

  // #95 item 3 — "All Zones" was a LIE whenever participation narrowed.
  // effectiveChannelIdsProvider intersects the selector with participation even
  // in the null-selector "All" case, so an apply labelled "All Zones" silently
  // skipped a channel: no seg emitted, no warning, "Applied: <design>" after.
  // These two pins are a pair — the second is what makes the first mean
  // something, by proving the suffix is not simply always present.
  testWidgets('the header admits when participation narrows an "All" apply',
      (tester) async {
    final c = ProviderContainer(overrides: _overrides(participating: [0]));
    addTearDown(c.dispose);

    await _pumpExpanded(tester, c);

    expect(
      find.textContaining('1 of 2 in shows'),
      findsOneWidget,
      reason: '"All Channels" with a channel gated out is a claim the apply '
          'path does not honour — the count is the truth it acts on',
    );
  });

  testWidgets('...and says nothing extra when it does not', (tester) async {
    final c = ProviderContainer(overrides: _overrides(participating: null));
    addTearDown(c.dispose);

    await _pumpExpanded(tester, c);

    expect(find.text('All Channels'), findsOneWidget);
    expect(find.textContaining('in shows'), findsNothing,
        reason: 'no narrowing, no caveat — otherwise the caveat is noise and '
            'stops being read');
  });

  testWidgets(
      'no channel label is ever struck through — that is the typography of DELETED',
      (tester) async {
    final c = ProviderContainer(overrides: _overrides(participating: [0]));
    addTearDown(c.dispose);

    await _pumpExpanded(tester, c);

    final struck = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.style?.decoration == TextDecoration.lineThrough)
        .toList();

    expect(
      struck,
      isEmpty,
      reason: 'a non-participating channel is out of scope for shows, not '
          'deleted; strikethrough claims the channel is gone (#95)',
    );
  });
}
