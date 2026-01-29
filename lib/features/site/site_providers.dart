import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';

/// Current site mode: Residential (single controller) or Commercial (Zones)
final siteModeProvider = StateProvider<SiteMode>((ref) => SiteMode.residential);

/// Manages user Property Areas. Always exposes at least one default area.
class PropertyAreasNotifier extends Notifier<List<PropertyArea>> {
  static const PropertyArea _defaultArea = PropertyArea(name: 'Main Home', type: PropertyType.residential);

  @override
  List<PropertyArea> build() => <PropertyArea>[_defaultArea];

  void setAll(List<PropertyArea> areas) {
    if (areas.isEmpty) {
      state = <PropertyArea>[_defaultArea];
    } else {
      state = areas;
    }
  }

  void add(PropertyArea area) => state = [...state, area];

  void removeByName(String name) {
    final next = state.where((a) => a.name != name).toList(growable: false);
    state = next.isEmpty ? <PropertyArea>[_defaultArea] : next;
  }

  void updateArea(String name, PropertyArea updated) {
    final next = state.map((a) => a.name == name ? updated : a).toList(growable: false);
    state = next.isEmpty ? <PropertyArea>[_defaultArea] : next;
  }

  void setLinkedControllers(String name, Set<String> ids) {
    final next = state.map((a) => a.name == name ? a.copyWith(linkedControllerIds: ids) : a).toList(growable: false);
    state = next;
  }
}

final propertyAreasProvider = NotifierProvider<PropertyAreasNotifier, List<PropertyArea>>(PropertyAreasNotifier.new);

/// Currently selected Property Area (nullable selection)
final selectedPropertyAreaProvider = StateProvider<PropertyArea?>((ref) => null);

/// Safe active Property Area that never returns null.
final activePropertyAreaProvider = Provider<PropertyArea>((ref) {
  final selected = ref.watch(selectedPropertyAreaProvider);
  final areas = ref.watch(propertyAreasProvider);
  if (areas.isEmpty) {
    // Safety: should not happen due to default in notifier, but guard anyway
    return const PropertyArea(name: 'Main Home', type: PropertyType.residential);
  }
  if (selected == null) {
    // Default to the first area
    return areas.first;
  }
  return selected;
});

/// A simple Zones manager for Commercial mode
class ZonesNotifier extends Notifier<List<ZoneModel>> {
  @override
  List<ZoneModel> build() => const [];

  void addZone(String name) {
    state = [...state, ZoneModel(name: name, primaryIp: null, members: const [])];
  }

  void removeZone(String name) {
    state = state.where((z) => z.name != name).toList(growable: false);
  }

  void addMember(String zoneName, String ip) {
    state = state
        .map((z) => z.name == zoneName && !z.members.contains(ip) ? z.copyWith(members: [...z.members, ip]) : z)
        .toList(growable: false);
  }

  void removeMember(String zoneName, String ip) {
    state = state
        .map((z) => z.name == zoneName ? z.copyWith(members: z.members.where((m) => m != ip).toList(growable: false), primaryIp: z.primaryIp == ip ? null : z.primaryIp) : z)
        .toList(growable: false);
  }

  void setPrimary(String zoneName, String ip) {
    state = state.map((z) => z.name == zoneName ? z.copyWith(primaryIp: ip) : z).toList(growable: false);
  }

  void setDdpEnabled(String zoneName, bool enabled) {
    state = state.map((z) => z.name == zoneName ? z.copyWith(ddpSyncEnabled: enabled) : z).toList(growable: false);
  }

  void setDdpPort(String zoneName, int port) {
    state = state.map((z) => z.name == zoneName ? z.copyWith(ddpPort: port) : z).toList(growable: false);
  }
}

final zonesProvider = NotifierProvider<ZonesNotifier, List<ZoneModel>>(ZonesNotifier.new);

/// Performs a best-effort configuration for DDP/UDP sync: enable sending on primary and
/// receiving on secondaries. Returns true if all requests succeeded.
final ddpSyncControllerProvider = Provider<DDPSyncController>((ref) => DDPSyncController(ref));

class DDPSyncController {
  final Ref ref;
  const DDPSyncController(this.ref);

  Future<bool> applyZoneSync(ZoneModel zone) async {
    final isDemo = ref.read(demoModeProvider);
    if (isDemo) {
      // No-op, simulate success in Demo Mode
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return true;
    }
    final primaryIp = zone.primaryIp;
    if (primaryIp == null || primaryIp.isEmpty) return false;
    final secondaries = zone.members.where((ip) => ip != primaryIp).toList(growable: false);

    bool ok = true;

    // Configure receivers to listen for UDP/DDP sync
    for (final ip in secondaries) {
      final svc = WledService('http://'+ip);
      final r = await svc.configureSyncReceiver();
      ok = ok && r;
    }

    // Configure primary to send UDP/DDP sync to network
    final primary = WledService('http://'+primaryIp);
    final sendRes = await primary.configureSyncSender(targets: secondaries, ddpPort: zone.ddpPort);
    ok = ok && sendRes;

    return ok;
  }
}

/// Linked controllers for Residential mode (acts as a single logical system)
class LinkedControllersNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String id) {
    final next = Set<String>.from(state);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
  }

  void setAll(Iterable<String> ids) => state = ids.toSet();

  void clear() => state = <String>{};
}

final linkedControllersProvider = NotifierProvider<LinkedControllersNotifier, Set<String>>(LinkedControllersNotifier.new);

/// Active Property Area controller IPs
///
/// Logic:
/// - Residential: if user linked specific controllers, use those; otherwise fallback to all controllers.
/// - Commercial: until a Zone selector exists in the top bar, fallback to all controllers.
final activeAreaControllerIpsProvider = Provider<List<String>>((ref) {
  final mode = ref.watch(siteModeProvider);
  final linked = ref.watch(linkedControllersProvider);
  final controllers = ref.watch(controllersStreamProvider).maybeWhen(data: (v) => v, orElse: () => const <ControllerInfo>[]);

  if (controllers.isEmpty) return const <String>[];

  // Residential: respect linked set if not empty
  if (mode == SiteMode.residential && linked.isNotEmpty) {
    final ips = controllers.where((c) => linked.contains(c.id)).map((c) => c.ip).where((ip) => ip.isNotEmpty).toList(growable: false);
    if (ips.isNotEmpty) return ips;
  }
  // Fallback: all devices
  return controllers.map((c) => c.ip).where((ip) => ip.isNotEmpty).toList(growable: false);
});

/// Whether to show 2D matrix effects in the pattern library.
/// Default is false since most installations are 1D LED strips.
/// Users with 2D matrix setups can enable this in Settings > System > Hardware.
final show2DEffectsProvider = StateProvider<bool>((ref) => false);

/// Whether to show audio-reactive effects in the pattern library.
/// Default is false since these require a microphone/line-in on the controller.
/// Users with audio-reactive setups can enable this in Settings > System > Hardware.
final showAudioEffectsProvider = StateProvider<bool>((ref) => false);

/// Computes whether any controller in the active area is currently ON.
/// Best-effort: queries /json/state from each IP in parallel once per read.
/// If no controllers are defined, falls back to the current single-device state.
final areaAnyOnProvider = FutureProvider<bool>((ref) async {
  final ips = ref.watch(activeAreaControllerIpsProvider);
  // If no known controllers, reflect the single connected device state (e.g., first-time user/demo)
  if (ips.isEmpty) {
    try {
      final singleOn = ref.read(wledStateProvider.select((s) => s.isOn));
      return singleOn;
    } catch (_) {
      return false;
    }
  }

  try {
    final futures = <Future<Map<String, dynamic>?>>[];
    for (final ip in ips) {
      final svc = WledService('http://'+ip);
      futures.add(svc.getState());
    }
    final results = await Future.wait(futures.map((f) async {
      try {
        return await f.timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('areaAnyOnProvider: state query failed: $e');
        return null;
      }
    }));
    for (final m in results) {
      if (m == null) continue;
      final on = m['on'];
      final bri = m['bri'];
      final isOn = (on is bool && on) || (bri is int && bri > 0);
      if (isOn) return true;
    }
  } catch (e) {
    debugPrint('areaAnyOnProvider error: $e');
  }
  return false;
});
