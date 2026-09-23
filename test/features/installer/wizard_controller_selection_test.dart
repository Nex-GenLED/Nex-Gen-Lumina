// P0 REGRESSION GATE — the installer wizard must reach Steps 5 and 6 with the
// controller the installer selected in Step 2.
//
// The defect (residential path audit 2026-09-23 §4.4): Step 5 (Hardware Config)
// and Step 6 (Map Roofline) both resolve their device through
// `selectedDeviceIpProvider`. The ONLY writer of that provider from a
// controllers collection is `autoConnectControllerProvider`, whose sole watcher
// is `MainScaffold`. The wizard runs on the root navigator, outside that shell,
// so the provider stayed null for the whole install: Step 5 said "No controller
// selected — go back and pick one" (going back changed nothing, there was no
// writer) and Step 6 said "No controller connected" with no channel chips. The
// installer's only way forward was "Skip for now" and "Map later" — every
// single install, which is the forced skip the owner reported.
//
// These pin the wizard's own selection path: the pure resolver, the provider
// over the live controllers stream, and the fact that Step 5 and Step 6 both
// end up pointed at that controller.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';

ControllerInfo _ctrl(String id, String ip) => ControllerInfo(id: id, ip: ip);

/// A container whose controllers stream is the wizard's staff-uid collection
/// and whose device selection starts empty — i.e. the wizard's real starting
/// state, with no MainScaffold mounted to auto-connect anything.
ProviderContainer _container(List<ControllerInfo> controllers) {
  return ProviderContainer(
    overrides: [
      controllersStreamProvider
          .overrideWith((ref) => Stream.value(controllers)),
    ],
  );
}

void main() {
  group('resolveInstallerControllerIp', () {
    test('returns null when nothing is selected', () {
      expect(
        resolveInstallerControllerIp(
          [_ctrl('a', '192.168.1.173')],
          <String>{},
        ),
        isNull,
      );
    });

    test('returns null when the selected controller has no IP', () {
      expect(
        resolveInstallerControllerIp([_ctrl('a', '')], {'a'}),
        isNull,
      );
    });

    test('returns the selected controller IP', () {
      expect(
        resolveInstallerControllerIp(
          [_ctrl('a', '192.168.1.173'), _ctrl('b', '192.168.1.150')],
          {'a'},
        ),
        '192.168.1.173',
      );
    });

    test('ignores controllers that were NOT selected', () {
      expect(
        resolveInstallerControllerIp(
          [_ctrl('leftover', '10.0.0.9'), _ctrl('mine', '192.168.1.173')],
          {'mine'},
        ),
        '192.168.1.173',
        reason: 'Step 2 lists the shared staff uid collection, so a previous '
            'install\'s leftovers are visible and must not be picked up',
      );
    });

    test('prefers a selected controller the step has probed as online', () {
      expect(
        resolveInstallerControllerIp(
          [_ctrl('offline', '192.168.1.99'), _ctrl('online', '192.168.1.173')],
          {'offline', 'online'},
          statusById: {'offline': false, 'online': true},
        ),
        '192.168.1.173',
      );
    });

    test('an unprobed controller is not treated as offline', () {
      // null status = the per-card probe has not answered yet. Falling back to
      // the first selected one is right; refusing to pick anything is not.
      expect(
        resolveInstallerControllerIp(
          [_ctrl('a', '192.168.1.173')],
          {'a'},
          statusById: const {'a': null},
        ),
        '192.168.1.173',
      );
    });
  });

  group('installerSelectedControllerIpProvider', () {
    test('is null before the installer selects anything', () async {
      final c = _container([_ctrl('a', '192.168.1.173')]);
      addTearDown(c.dispose);
      // Let the stream deliver.
      await c.read(controllersStreamProvider.future);
      expect(c.read(installerSelectedControllerIpProvider), isNull);
    });

    test('resolves the wizard selection off the live controllers stream',
        () async {
      final c = _container([
        _ctrl('a', '192.168.1.173'),
        _ctrl('b', '192.168.1.150'),
      ]);
      addTearDown(c.dispose);
      await c.read(controllersStreamProvider.future);

      c.read(installerSelectedControllersProvider.notifier).state = {'b'};

      expect(c.read(installerSelectedControllerIpProvider), '192.168.1.150');
    });
  });

  group('Steps 5 and 6 see the wizard controller', () {
    // Step 2's Continue (`_saveAndContinue`) performs exactly this hand-off.
    // Reproduced here rather than pumping the whole wizard so the assertion is
    // about the state contract, not about widget plumbing.
    void stepTwoContinue(ProviderContainer c) {
      final ip = c.read(installerSelectedControllerIpProvider);
      if (ip != null) {
        c.read(selectedDeviceIpProvider.notifier).state = ip;
      }
    }

    test('THE REGRESSION: selectedDeviceIpProvider is null until the wizard '
        'sets it, and both later steps then resolve the controller', () async {
      final c = _container([_ctrl('a', '192.168.1.173')]);
      addTearDown(c.dispose);
      await c.read(controllersStreamProvider.future);

      c.read(installerSelectedControllersProvider.notifier).state = {'a'};

      // Before the fix this stayed null for the entire install — Step 5's
      // `ref.read(selectedDeviceIpProvider)` and Step 6's repository lookup
      // both fell to their "no controller" branches.
      expect(c.read(selectedDeviceIpProvider), isNull,
          reason: 'nothing outside MainScaffold sets this on its own');

      stepTwoContinue(c);

      // Step 5 (hardware_config_step._resolveIp) and Step 6
      // (map_roofline_step, via wledRepositoryProvider) both read this.
      expect(c.read(selectedDeviceIpProvider), '192.168.1.173');
    });

    test('Step 5 falls back to the wizard selection when the wizard is '
        're-entered past Step 2', () async {
      final c = _container([_ctrl('a', '192.168.1.173')]);
      addTearDown(c.dispose);
      await c.read(controllersStreamProvider.future);
      c.read(installerSelectedControllersProvider.notifier).state = {'a'};

      // Step 2's Continue never ran (resumed draft, deep link, back-navigation
      // that rebuilt the step). hardware_config_step._resolveIp latches it.
      String? resolveIp() {
        final existing = c.read(selectedDeviceIpProvider);
        if (existing != null) return existing;
        final fromWizard = c.read(installerSelectedControllerIpProvider);
        if (fromWizard != null) {
          c.read(selectedDeviceIpProvider.notifier).state = fromWizard;
        }
        return fromWizard;
      }

      expect(resolveIp(), '192.168.1.173');
      expect(c.read(selectedDeviceIpProvider), '192.168.1.173',
          reason: 'latched, so the custom hardware editor and Step 6 see it');
    });

    test('a changed selection re-points the device', () async {
      final c = _container([
        _ctrl('a', '192.168.1.173'),
        _ctrl('b', '192.168.1.150'),
      ]);
      addTearDown(c.dispose);
      await c.read(controllersStreamProvider.future);

      c.read(installerSelectedControllersProvider.notifier).state = {'a'};
      stepTwoContinue(c);
      expect(c.read(selectedDeviceIpProvider), '192.168.1.173');

      // Installer goes back and picks the other controller.
      c.read(installerSelectedControllersProvider.notifier).state = {'b'};
      stepTwoContinue(c);
      expect(c.read(selectedDeviceIpProvider), '192.168.1.150');
    });
  });
}
