// Pure models of WLED's timer table, TRANSCRIBED FROM THE WLED SOURCE — not
// bench-verified. Tests built on these assert the behaviour the source
// describes; their names say so ("per WLED source").
//
// 0.15.1 / 0.15.4 (identical timer code), tag v0.15.1 @ 4f3992b:
//   parse      wled00/cfg.cpp:564-595   (positional fill, jump to slot 8 at the
//                                        first hour==255 row, dow/en quirk)
//   serialize  wled00/cfg.cpp:1054-1070 (all-zero slots are skipped)
//   boot       wled00/cfg.cpp:642-671   (cfg.json re-parsed by the same code)
//   evaluate   wled00/ntp.cpp:374-425   (clock 0-7, then sunrise 8, then sunset 9;
//                                        applyPreset only records → last match wins)
// 16.0.1, tag v16.0.1 @ 29b389d:
//   parse      wled00/cfg.cpp:695-727   (clearTimers(); type by hour 255/254;
//                                        legacy 255→254 only when vid < 2605010)
//   addTimer   wled00/ntp.cpp:580-615
//   serialize  wled00/cfg.cpp:1222-1238
//   evaluate   wled00/ntp.cpp:416-451   (list order; date range on every row)
//
// Simplifications, all irrelevant to what the app sends: no start/end parsing
// beyond the defaults, no hour-24 ("every hour") rows, no day wrap of a sun
// offset, ArduinoJson conversions reduced to "an int in range is taken,
// anything else keeps the previous value".

/// One minute of local time as checkTimers sees it.
class FwMinute {
  /// 1 = Monday … 7 = Sunday (`weekdayMondayFirst()`).
  final int weekday;
  final int hour;
  final int minute;

  /// Minutes after local midnight of today's computed sunrise / sunset, or
  /// null when the firmware has not computed them (coordinates 0,0).
  final int? sunrise;
  final int? sunset;

  const FwMinute(this.weekday, this.hour, this.minute,
      {this.sunrise, this.sunset});
}

abstract class WledTimerFirmware {
  /// POST /json/cfg `{"timers":{"ins": ins}}`.
  void post(List<Map<String, dynamic>> ins);

  /// What GET /json/cfg returns for `timers.ins` (and what cfg.json holds).
  List<Map<String, dynamic>> readback();

  /// Power cycle: cfg.json is re-parsed into fresh defaults.
  void reboot();

  /// The preset checkTimers applies in [m], or null when nothing fires.
  int? presetAt(FwMinute m);
}

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
bool _has(Map<String, dynamic> t, String k) => _int(t[k]) != null;

/// WLED 0.15.1 / 0.15.4.
class Wled015Timers implements WledTimerFirmware {
  final hours = List<int>.filled(10, 0);
  final minutes = List<int>.filled(10, 0); // int8_t
  final macros = List<int>.filled(10, 0);
  final weekday = List<int>.filled(10, 255); // (dow << 1) | en; wled.h default 255

  @override
  void post(List<Map<String, dynamic>> ins) {
    var it = 0;
    for (final t in ins) {
      if (it > 9) break;
      if (it < 8 && _int(t['hour']) == 255) it = 8; // hour==255 -> sunrise/sunset
      final h = _int(t['hour']);
      if (h != null && h >= 0 && h <= 255) hours[it] = h;
      final mi = _int(t['min']);
      if (mi != null && mi >= -128 && mi <= 127) minutes[it] = mi;
      final ma = _int(t['macro']);
      if (ma != null && ma >= 0 && ma <= 255) macros[it] = ma;

      final dowPrev = weekday[it];
      final actPrev = weekday[it] & 0x01;
      final dow = _int(t['dow']);
      if (dow != null && dow >= 0 && dow <= 255) weekday[it] = dow;
      if (weekday[it] != dowPrev) {
        // "present in JSON" — compares the RAW dow with the stored SHIFTED
        // byte (cfg.cpp:578). Equal → nothing below runs (the quirk).
        weekday[it] = (weekday[it] << 1) & 0xFF;
        final act = _has(t, 'en') ? _int(t['en'])! : actPrev;
        if (act != 0) weekday[it]++;
      }
      it++;
    }
  }

  @override
  List<Map<String, dynamic>> readback() => [
        for (var i = 0; i < 10; i++)
          if (!(macros[i] == 0 && hours[i] == 0 && minutes[i] == 0))
            {
              'en': weekday[i] & 0x01,
              'hour': hours[i],
              'min': minutes[i],
              'macro': macros[i],
              'dow': weekday[i] >> 1,
              if (i < 8) 'start': {'mon': 1, 'day': 1},
              if (i < 8) 'end': {'mon': 12, 'day': 31},
            },
      ];

  @override
  void reboot() {
    final file = readback();
    for (var i = 0; i < 10; i++) {
      hours[i] = 0;
      minutes[i] = 0;
      macros[i] = 0;
      weekday[i] = 255;
    }
    post(file);
  }

  bool _onDay(int slot, int weekdayMonFirst) =>
      ((weekday[slot] >> weekdayMonFirst) & 0x01) == 1;

  @override
  int? presetAt(FwMinute m) {
    int? fired;
    for (var i = 0; i < 8; i++) {
      if (macros[i] != 0 &&
          (weekday[i] & 0x01) == 1 &&
          (hours[i] == m.hour || hours[i] == 24) &&
          minutes[i] == m.minute &&
          _onDay(i, m.weekday)) {
        fired = macros[i];
      }
    }
    for (final (slot, sun) in [(8, m.sunrise), (9, m.sunset)]) {
      if (sun == null) continue; // `if (sunrise)` — never computed
      final at = sun + minutes[slot];
      if (macros[slot] != 0 &&
          at ~/ 60 == m.hour &&
          at % 60 == m.minute &&
          (weekday[slot] & 0x01) == 1 &&
          _onDay(slot, m.weekday)) {
        fired = macros[slot];
      }
    }
    return fired;
  }
}

class Wled16Timer {
  final int preset, hour, minute, weekdays;
  const Wled16Timer(this.preset, this.hour, this.minute, this.weekdays);
  bool get isEnabled => (weekdays & 0x01) == 1 && preset != 0;
  bool get isSunrise => hour == 255; // TH_SUNRISE
  bool get isSunset => hour == 254; // TH_SUNSET
}

/// WLED 16.0.1 (vid 2605010).
class Wled16Timers implements WledTimerFirmware {
  final List<Wled16Timer> timers = [];

  /// The `vid` the parser sees. A POST from the app carries none, so it is the
  /// running VERSION (cfg.cpp:52); a cfg.json written by 16.x carries 2605010.
  void postWithVid(List<Map<String, dynamic>> ins, {required int vid}) {
    timers.clear(); // clearTimers(): any present ins replaces the whole list
    var legacySunriseLoaded = false;
    for (final t in ins) {
      var h = _int(t['hour']) ?? 0;
      if (vid < 2605010 && h == 255) {
        if (legacySunriseLoaded) {
          h = 254;
        } else {
          legacySunriseLoaded = true;
        }
      }
      var m = _int(t['min']) ?? 0;
      m = ((m + 128) & 0xFF) - 128; // int8_t narrowing
      final p = (_int(t['macro']) ?? 0) & 0xFF;
      final dow = (_int(t['dow']) ?? 127) & 0xFF;
      final en = t['en'] is int ? t['en'] as int : 0; // a JSON bool is not an int
      final wd = ((dow << 1) | (en != 0 ? 1 : 0)) & 0xFF;
      _addTimer(p, h & 0xFF, m, wd);
    }
  }

  void _addTimer(int preset, int hour, int minute, int weekdays) {
    if (hour > 24 && hour != 254 && hour != 255) return; // invalid hour
    if (hour == 254 || hour == 255) {
      minute = minute.clamp(-120, 120);
    } else if (minute < 0 || minute > 59) {
      return;
    }
    if (timers.length >= 64) return; // WLED_MAX_TIMERS on ESP32
    timers.add(Wled16Timer(preset, hour, minute, weekdays));
  }

  @override
  void post(List<Map<String, dynamic>> ins) => postWithVid(ins, vid: 2605010);

  @override
  List<Map<String, dynamic>> readback() => [
        for (final t in timers)
          if (!(t.preset == 0 && t.hour == 0 && t.minute == 0))
            {
              'en': t.isEnabled ? 1 : 0,
              'hour': t.hour,
              'min': t.minute,
              'macro': t.preset,
              'dow': t.weekdays >> 1,
              'start': {'mon': 1, 'day': 1},
              'end': {'mon': 12, 'day': 31},
            },
      ];

  @override
  void reboot() => postWithVid(readback(), vid: 2605010);

  @override
  int? presetAt(FwMinute m) {
    int? fired;
    for (final t in timers) {
      if (!t.isEnabled) continue;
      int at;
      if (t.isSunrise) {
        if (m.sunrise == null) continue;
        at = m.sunrise! + t.minute;
      } else if (t.isSunset) {
        if (m.sunset == null) continue;
        at = m.sunset! + t.minute;
      } else {
        at = t.hour * 60 + t.minute;
      }
      if (at ~/ 60 == m.hour && at % 60 == m.minute) {
        if (((t.weekdays >> m.weekday) & 0x01) == 0) continue;
        fired = t.preset;
      }
    }
    return fired;
  }
}

/// A preset firing on the simulated timeline.
class FwEvent {
  final int day; // 0-based day of the run
  final int weekday; // 1 = Mon … 7 = Sun
  final int hour;
  final int minute;
  final int preset;
  const FwEvent(this.day, this.weekday, this.hour, this.minute, this.preset);

  static const _names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  String get at =>
      '${_names[weekday]} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  @override
  String toString() => '$at → $preset';
}

/// Run every minute of [days] days through [fw], starting at Monday 00:00
/// unless [startWeekday] says otherwise, with fixed sun times.
List<FwEvent> runDays(
  WledTimerFirmware fw, {
  int days = 7,
  int startWeekday = 1,
  int? sunrise = 6 * 60 + 46, // bench location, Nov 3 2026
  int? sunset = 17 * 60 + 14,
}) {
  final out = <FwEvent>[];
  for (var d = 0; d < days; d++) {
    final wd = (startWeekday - 1 + d) % 7 + 1;
    for (var mm = 0; mm < 24 * 60; mm++) {
      final p = fw.presetAt(
          FwMinute(wd, mm ~/ 60, mm % 60, sunrise: sunrise, sunset: sunset));
      if (p != null) out.add(FwEvent(d, wd, mm ~/ 60, mm % 60, p));
    }
  }
  return out;
}

/// Light state at the end of each [FwEvent]: preset 2 = master OFF.
/// Returns, for every event, whether the lights are on afterwards.
bool lightsOnAfter(List<FwEvent> events, int index) => events[index].preset != 2;
