// Relay eligibility (2026-09-30) meeting package E2's apply surfaces.
//
// Away from home with NO paired bridge, the routed repository is null. Every
// E2 surface that applies to the lights must then report the plain-words
// no-bridge sentence as a BLOCKED result — never a crash, a spinner, or a
// silent no-op:
//   • Design Studio — the shared spine behind Apply, the "Preview on lights"
//     toggle (applyCustomDesignDetailed → applyPositionalDesignDetailed) and
//     My Designs;
//   • Lumina — RiverpodLuminaConversationServices.applyToDevice, the one
//     WriteResult the driver turns into its failure reply.
//
// The chain is the REAL one: authStateProvider → connectivity `remote` →
// pairedBridgeProvider `none` → wledRepositoryProvider null →
// applyBlockedReasonProvider noBridge. Only the leaves are faked.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_conversation_driver.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/bridge_pairing.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'account';
  @override
  String? get email => 'someone@example.com';
}

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

const _channels = [
  DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Ch2', start: 100, stop: 200, gpioPin: 3),
];

final _now = DateTime.utc(2026, 9, 30);

/// A design painted on channel 0.
CustomDesign _painted() => CustomDesign(
      id: 'd',
      name: 'Painted',
      ownerId: 'u',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Ch1',
          ledCount: 100,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 9, color: [255, 0, 0, 0]),
            LedColorGroup(startLed: 10, endLed: 99, color: [0, 0, 0, 0]),
          ],
        ),
      ],
    );

/// Away from home, signed in, one registered controller, NO paired bridge.
List<Override> _awayWithNoBridge() => [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(_FakeUser())),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.remote)),
      controllersStreamProvider.overrideWith((ref) => Stream.value([
            ControllerInfo(id: 'front', ip: '192.0.2.10'),
          ])),
      currentUserProfileProvider
          .overrideWith((ref) => Stream<UserModel?>.value(null)),
      pairedBridgeProvider.overrideWith(
          (ref) => Stream.value(const PairedBridgeLookup.none())),
      selectedDeviceIpProvider.overrideWith((ref) => '192.0.2.10'),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
      deviceChannelsProvider.overrideWithValue(_channels),
      participatingChannelIdsProvider.overrideWithValue(null),
      selectedChannelIdsProvider.overrideWith((ref) => null),
    ];

Future<void> _settle(ProviderContainer c) async {
  await c.read(authStateProvider.future);
  await c.read(wledConnectivityStatusProvider.future);
  await c.read(controllersStreamProvider.future);
  await c.read(currentUserProfileProvider.future);
  await c.read(pairedBridgeProvider.future);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('Design Studio apply / Preview on lights / My Designs — away, no bridge',
      () {
    test('the routed chain yields no repository and the no-bridge reason',
        () async {
      final c = ProviderContainer(overrides: _awayWithNoBridge());
      addTearDown(c.dispose);
      await _settle(c);

      expect(c.read(isRemoteModeProvider), isTrue);
      expect(c.read(pairedBridgeStateProvider), PairedBridgeState.none);
      expect(c.read(wledRepositoryProvider), isNull);
      expect(c.read(applyBlockedReasonProvider)?.kind, ApplyBlock.noBridge);
    });

    test('the spine every Studio apply goes through returns the sentence — '
        'blocked, not thrown, not silent', () async {
      final c = ProviderContainer(overrides: _awayWithNoBridge());
      addTearDown(c.dispose);
      await _settle(c);

      final report = await applyPositionalDesignDetailed(c.read, _painted());

      expect(report.ok, isFalse);
      expect(report.wire, SpineWriteResult.noDevice);
      expect(report.message, kNoBridgeAwayMessage);
      expect(report.message, contains('Lumina Bridge'));
      expect(report.message, isNot(contains("remote access isn't set up")));
      expect(report.message, isNot(contains("Couldn't reach")));
    });

    testWidgets('"Preview on lights" uses the same spine through a WidgetRef',
        (tester) async {
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: _awayWithNoBridge(),
        child: Consumer(builder: (context, r, _) {
          ref = r;
          r.watch(wledRepositoryProvider);
          r.watch(pairedBridgeProvider);
          return const SizedBox();
        }),
      ));
      await tester.pump();
      await tester.pump();

      final report = await applyCustomDesignDetailed(ref, _painted());
      expect(report.ok, isFalse);
      expect(report.wire, SpineWriteResult.noDevice);
      expect(report.message, kNoBridgeAwayMessage);
    });
  });

  group('Lumina apply — away, no bridge', () {
    testWidgets('applyToDevice is BLOCKED with the sentence and the driver '
        'reply carries it', (tester) async {
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: _awayWithNoBridge(),
        child: Consumer(builder: (context, r, _) {
          ref = r;
          r.watch(wledRepositoryProvider);
          r.watch(pairedBridgeProvider);
          return const SizedBox();
        }),
      ));
      await tester.pump();
      await tester.pump();

      final services = RiverpodLuminaConversationServices(ref);
      expect(services.hasDevice, isFalse);

      final outcome = await services.applyToDevice(const {'on': false});
      expect(outcome.ok, isFalse);
      expect(outcome.message, kNoBridgeAwayMessage);

      final reply = LuminaConversationDriver.failureReplyFor(
        LuminaCommandResult(
          command: LuminaCommand(
            type: LuminaCommandType.power,
            parameters: const {'on': false},
            confidence: 0.95,
            rawText: 'turn off the lights',
          ),
          responseText: 'Turning your lights off.',
        ),
        outcome,
      );
      expect(reply, startsWith("I couldn't turn your lights off"));
      expect(reply, contains('requires a Lumina Bridge'));
      expect(reply, isNot(contains("remote access isn't set up")));
    });
  });
}
