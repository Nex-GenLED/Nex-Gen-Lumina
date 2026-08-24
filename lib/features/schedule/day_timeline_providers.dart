// lib/features/schedule/day_timeline_providers.dart
//
// Scheduling V3 A2/A3 — the ONE provider every surface reads for a day.
//
// The Tonight card, the day hero and the week cell each used to open-code their
// own resolution (audit/SCHEDULING_V3_AUDIT.md §3.1 lists all three, plus the
// fourth that silently dropped recurring entirely). `resolveDay` unified the
// LOGIC but each surface still assembled its own inputs. This unifies the
// inputs too: one family provider, one policy, one answer per date.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/widgets/channel_scope_picker.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

/// The timeline for one `'YYYY-MM-DD'`.
///
/// Watches recurring schedules, dated entries and the user's coordinates, so a
/// surface rebuilds when any of them changes.
///
/// The policy is [kActiveSchedulePrecedence] — passed here and NOWHERE else, so
/// there is exactly one place to flip when the firing layer changes.
final dayTimelineProvider =
    Provider.family<DayTimeline, String>((ref, dateKey) {
  final schedules = ref.watch(schedulesProvider);
  final calendar = ref.watch(calendarScheduleProvider);

  final profile = ref.watch(currentUserProfileProvider).valueOrNull;
  final lat = profile?.latitude;
  final lon = profile?.longitude;

  String? sunrise;
  String? sunset;
  if (lat != null && lon != null) {
    try {
      final day = DateTime.parse(dateKey);
      sunrise = _hhmm(SunUtils.sunriseLocal(lat, lon, day));
      sunset = _hhmm(SunUtils.sunsetLocal(lat, lon, day));
    } catch (_) {
      // Unparseable dateKey or a sun-time failure. Leave both null: a solar
      // label then resolves to null and its row is flagged time-unresolved
      // rather than being placed at an invented hour.
    }
  }

  return resolveDayTimeline(
    DayTimelineInputs(
      dateKey: dateKey,
      recurringSchedules: schedules,
      datedEntries: calendar.forDate(dateKey),
      sunriseHhmm: sunrise,
      sunsetHhmm: sunset,
    ),
    kActiveSchedulePrecedence,
  );
});

/// Today's timeline — what the dashboard's upcoming-schedule card reads.
final todayTimelineProvider = Provider<DayTimeline>((ref) {
  final now = DateTime.now();
  return ref.watch(dayTimelineProvider(calendarDateKey(now)));
});

String? _hhmm(DateTime? dt) => dt == null
    ? null
    : '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

/// D4 — resolves a timeline row's channel-scope label and (only in a
/// multi-controller home) its controller name.
///
/// Bundled into one provider so every surface asks the same question once and
/// gets the same answer, instead of each deciding when a controller name is
/// worth showing.
final timelineScopeLabellerProvider = Provider<TimelineScopeLabeller>((ref) {
  final channels = ref.watch(deviceChannelsProvider);
  final controllers = ref.watch(controllersStreamProvider).maybeWhen(
        data: (list) => list,
        orElse: () => const <ControllerInfo>[],
      );
  return TimelineScopeLabeller(
    channels: channels,
    controllerNames: {
      for (final c in controllers) c.id: c.name ?? 'Controller',
    },
    multiController: controllers.length > 1,
  );
});

/// Pure label resolver — see [timelineScopeLabellerProvider].
class TimelineScopeLabeller {
  final List<DeviceChannel> channels;
  final Map<String, String> controllerNames;

  /// P5: the controller name is shown ONLY when there is more than one. With a
  /// single controller it is noise on every scoped row.
  final bool multiController;

  const TimelineScopeLabeller({
    required this.channels,
    required this.controllerNames,
    required this.multiController,
  });

  String? scopeFor(TimelineEntry e) =>
      channelScopeLabel(_channelsOf(e), channels);

  String? controllerFor(TimelineEntry e) {
    if (!multiController) return null;
    if (_channelsOf(e) == null) return null;
    final id = e.recurring?.controllerId ?? e.dated?.controllerId;
    return id == null ? null : controllerNames[id];
  }

  static List<int>? _channelsOf(TimelineEntry e) =>
      e.recurring?.channels ?? e.dated?.channels;
}
