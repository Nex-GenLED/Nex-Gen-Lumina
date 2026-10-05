// #118 — the blocked-apply sentence for a selection that is not this
// account's controller.
//
// Away from home, an address that matched none of the account's records gave
// the relay no record id, so no repository was built — and the customer was
// told remote access was not set up, or that a bridge was needed. Neither was
// the problem; the selection was. "Set as Active" fixed it, which is how the
// owner learned to press it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/bridge_pairing.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _front = ControllerInfo(id: 'front', ip: '192.0.2.10', name: 'Front');
const _back = ControllerInfo(id: 'back', ip: '192.0.2.11', name: 'Back');

class _Fixed extends ControllerSelectionNotifier {
  _Fixed(this.value);
  final ControllerSelection value;
  @override
  ControllerSelection build() => value;
}

Future<ProviderContainer> _container({
  required List<ControllerInfo> records,
  String? selectedIp,
  ControllerSelection selection = ControllerSelection.none,
  ConnectivityStatus network = ConnectivityStatus.remote,
  PairedBridgeLookup paired = const PairedBridgeLookup.none(),
}) async {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => null),
    wledConnectivityStatusProvider
        .overrideWith((ref) => Stream<ConnectivityStatus>.value(network)),
    controllersStreamProvider.overrideWith((ref) => Stream.value(records)),
    pairedBridgeProvider.overrideWith((ref) => Stream.value(paired)),
    controllerSelectionProvider.overrideWith(() => _Fixed(selection)),
  ]);
  addTearDown(c.dispose);
  c.read(selectedDeviceIpProvider.notifier).state = selectedIp;
  await c.read(wledConnectivityStatusProvider.future);
  await c.read(controllersStreamProvider.future);
  await c.read(pairedBridgeProvider.future);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('an address that is none of this account\'s records', () {
    for (final paired in const [
      PairedBridgeLookup.none(),
      PairedBridgeLookup.unknown(),
    ]) {
      test('away, bridge ${paired.state.name}: says the selection is wrong — '
          'not remote access, not a bridge', () async {
        final c = await _container(
          records: const [_front],
          selectedIp: '192.0.2.99',
          paired: paired,
        );
        final reason = c.read(applyBlockedReasonProvider);
        expect(reason?.kind, ApplyBlock.notThisAccount);
        expect(reason!.message, contains('isn\'t on your account'));
        expect(reason.message, contains(
            'Settings → System & Device Management → Controllers'));
        expect(reason.message.toLowerCase(), isNot(contains('remote access')));
        expect(reason.message.toLowerCase(), isNot(contains('bridge')));
      });
    }

    test('offline still comes first: the phone has no network', () async {
      final c = await _container(
        records: const [_front],
        selectedIp: '192.0.2.99',
        network: ConnectivityStatus.offline,
      );
      expect(c.read(applyBlockedReasonProvider)?.kind, ApplyBlock.offline);
    });
  });

  group('an address that IS this account\'s record', () {
    test('away with no bridge: the bridge sentence, as before', () async {
      final c = await _container(
        records: const [_front],
        selectedIp: _front.ip,
      );
      expect(c.read(applyBlockedReasonProvider)?.kind, ApplyBlock.noBridge);
    });
  });

  group('nothing selected', () {
    test('two or more answered: choose which one', () async {
      final c = await _container(
        records: const [_front, _back],
        selection: const ControllerSelection(choices: ['front', 'back']),
      );
      final reason = c.read(applyBlockedReasonProvider);
      expect(reason?.kind, ApplyBlock.chooseController);
      expect(reason!.message, contains('Choose'));
    });

    test('no records: no controller is set up yet, as before', () async {
      final c = await _container(records: const []);
      expect(c.read(applyBlockedReasonProvider)?.kind, ApplyBlock.noController);
    });
  });
}
