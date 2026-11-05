// lib/features/wled/design_schedule_pick.dart
//
// Roofline slice 2 — the picker's side of "may this painted design be
// scheduled nightly?": the pure verdict (design_api_preset.dart) over the
// live providers, plus the one device read it needs that no provider holds,
// the controller's firmware version.
//
// Kept out of the picker widget so the wiring is testable without pumping the
// library browser: which repository counts as "on the LAN", when the firmware
// is read, and which provider feeds each gate.

import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart'
    show ProviderReader;
import 'package:nexgen_command/features/schedule/design_api_preset.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// The controller's firmware version (`/json/info` `ver`) from a direct-LAN
/// service, or null for any other repository or a failed read. The same read
/// the installer's controller check and the restart watch make; nothing is
/// cached, so the verdict judges the controller the app is talking to now.
Future<String?> controllerFirmwareVersion(WledRepository? repo) async {
  if (repo is! WledService) return null;
  try {
    final info = await repo.getInfo();
    return info?.ver;
  } catch (_) {
    return null;
  }
}

/// The eligibility verdict for [design] from the picker, over the live
/// providers:
///
/// * on the LAN = the repository is a direct-LAN [WledService] AND the app is
///   not in remote mode (a relay of either mode has no bus facts, no firmware
///   read and no read-back, so it is off-LAN here);
/// * the bus list from `deviceChannelsProvider`, the selected controller's
///   record id only when there are buses to compare against;
/// * the firmware version read ONLY on the LAN (one GET), after the stamp and
///   LAN checks would already have refused, so an off-LAN pick costs nothing.
///
/// The per-account count is left to the save path, which knows which
/// schedule is being edited; the picker never refuses on it.
Future<DesignScheduleEligibility> designSchedulePickVerdict(
  ProviderReader read,
  CustomDesign design,
) async {
  final repo = read(wledRepositoryProvider);
  final onLan = repo is WledService && !read(isRemoteModeProvider);
  final live = read(deviceChannelsProvider);
  final firmware = onLan && design.isPositional && design.layoutStamp != null
      ? await controllerFirmwareVersion(repo)
      : null;
  return designScheduleEligibility(
    design: design,
    onLan: onLan,
    liveChannels: live,
    liveControllerId: live.isEmpty ? null : read(selectedControllerIdProvider),
    firmwareVersion: firmware,
  );
}
