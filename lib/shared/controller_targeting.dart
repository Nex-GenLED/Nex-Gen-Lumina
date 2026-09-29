import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/shared/write_result.dart';

export 'package:nexgen_command/features/wled/wled_providers.dart'
    show ControllerTarget, controllerRepositoryProvider;

/// The controllers a whole-home command goes to.
///
/// The SAME set the Home power circle has always used
/// (`activeAreaControllerIpsProvider`), as targets that carry the account
/// record id the relay needs rather than as bare addresses:
///
///  * Residential with linked controllers → the linked ones.
///  * Otherwise → every registered controller.
///  * No registered controllers → the selected device alone, if there is one
///    (first-run discovery, demo). One address, no record id.
///
/// Controllers with no address are left out: there is nowhere to send.
final linkedControllerTargetsProvider = Provider<List<ControllerTarget>>((ref) {
  final controllers = ref.watch(controllersStreamProvider).maybeWhen(
        data: (v) => v,
        orElse: () => const <ControllerInfo>[],
      );

  if (controllers.isEmpty) {
    final selected = ref.watch(selectedDeviceIpProvider);
    if (selected == null || selected.isEmpty) return const <ControllerTarget>[];
    return [ControllerTarget(ip: selected)];
  }

  List<ControllerTarget> targetsOf(Iterable<ControllerInfo> list) => [
        for (final c in list)
          if (c.ip.isNotEmpty)
            ControllerTarget(ip: c.ip, controllerId: c.id, name: c.name),
      ];

  final mode = ref.watch(siteModeProvider);
  final linked = ref.watch(linkedControllersProvider);
  if (mode == SiteMode.residential && linked.isNotEmpty) {
    final targets = targetsOf(controllers.where((c) => linked.contains(c.id)));
    if (targets.isNotEmpty) return targets;
  }
  return targetsOf(controllers);
});

/// What happened on one controller of a fan-out.
class ControllerWriteOutcome {
  final ControllerTarget target;
  final WriteResult result;
  const ControllerWriteOutcome(this.target, this.result);
}

/// Runs [write] against every linked controller, each through its own ROUTED
/// repository — direct on the home network, relayed away from home, with the
/// identity check either way. No raw per-address requests.
///
/// All controllers run at once; one that fails or throws does not stop the
/// others, and every controller comes back with its own outcome. A controller
/// that cannot be reached at all right now (offline, or away from home with no
/// relay for it) is reported as blocked rather than skipped silently.
///
/// [includeSelected] — pass `false` when the selected controller has already
/// been written through the notifier, which also owns its optimistic state and
/// failure reporting. The default sends to every linked controller.
///
/// Pass `ref.read` for [read].
Future<List<ControllerWriteOutcome>> forEachLinkedController(
  T Function<T>(ProviderListenable<T> provider) read,
  Future<bool> Function(WledRepository repo, ControllerTarget target) write, {
  bool includeSelected = true,
}) {
  final selectedIp = read(selectedDeviceIpProvider);
  final targets = [
    for (final t in read(linkedControllerTargetsProvider))
      if (includeSelected || t.ip != selectedIp) t,
  ];

  return Future.wait(targets.map((target) async {
    final repo = read(controllerRepositoryProvider(target));
    if (repo == null) {
      return ControllerWriteOutcome(
        target,
        const WriteResult.failed(WriteFailureKind.blocked),
      );
    }
    try {
      final ok = await write(repo, target);
      return ControllerWriteOutcome(target, WriteResult.fromBool(ok));
    } catch (e) {
      debugPrint('forEachLinkedController: $target threw — $e');
      return ControllerWriteOutcome(
        target,
        WriteResult.failed(WriteFailureKind.error, error: e),
      );
    }
  }));
}

/// One result for a whole fan-out, with a sentence that counts the misses.
///
/// Success only when every controller took the write. An empty fan-out is a
/// success: there was nothing else to send to.
WriteResult summarizeFanOut(List<ControllerWriteOutcome> outcomes) {
  final missed = outcomes.where((o) => o.result.failed).length;
  if (missed == 0) return const WriteResult.success();
  final total = outcomes.length;
  final allBlocked = outcomes.every((o) => o.result.wasBlocked);
  return WriteResult.failed(
    allBlocked ? WriteFailureKind.blocked : WriteFailureKind.unreachable,
    message: total == 1
        ? "Couldn't reach your other controller"
        : missed == total
            ? "Couldn't reach your other controllers"
            : "Couldn't reach $missed of your other $total controllers",
  );
}
