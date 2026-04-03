import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/audio/models/audio_reactive_capability.dart';

/// Probes a WLED controller to determine audio-reactive support.
///
/// Checks `/json/info` for SR WLED usermod and mic hardware, then
/// scans the effect list for audio-reactive entries (prefixed with "* ").
class AudioCapabilityDetector {
  static const _timeout = Duration(seconds: 15);

  /// Detect audio-reactive capabilities of the controller at [controllerIp].
  ///
  /// Never throws — returns [AudioReactiveCapability.notSupported] on any error.
  Future<AudioReactiveCapability> detect(String controllerIp) async {
    try {
      final baseUrl = 'http://$controllerIp';

      // 1. Fetch /json/info for usermod & mic detection
      final info = await _fetchJson('$baseUrl/json/info');
      if (info == null) return AudioReactiveCapability.notSupported();

      // 2. Check for SR WLED / audioreactive usermod
      //    SR WLED exposes: info.u.audioreactive  or  info.str (sound reactive flag)
      bool hasUsermod = false;
      String? usermodeVersion;

      // Check info.u (usermods object) for audioreactive key.
      // Case-insensitive: firmware may report "audioreactive",
      // "AudioReactive", "Audioreactive", etc.
      final usermods = info['u'];
      String arKey = '';
      if (usermods is Map<String, dynamic>) {
        arKey = usermods.keys.firstWhere(
          (k) => k.toLowerCase() == 'audioreactive',
          orElse: () => '',
        );
        if (arKey.isNotEmpty) {
          hasUsermod = true;
          final arMod = usermods[arKey];
          if (arMod is Map<String, dynamic> && arMod.containsKey('ver')) {
            usermodeVersion = arMod['ver']?.toString();
          }
        }
      }

      // Fallback: check top-level str field (some SR WLED builds)
      if (!hasUsermod && info['str'] == true) {
        hasUsermod = true;
      }

      // 3. Check for mic hardware
      //    SR WLED reports mic config in info.u.audioreactive or info.mic
      bool hasMic = false;
      if (hasUsermod) {
        // If the usermod is present, check for mic type/pin config
        if (usermods is Map<String, dynamic> && arKey.isNotEmpty) {
          final arMod = usermods[arKey];
          if (arMod is Map<String, dynamic>) {
            // mic type: 0 = none, 1 = analog, 2 = I2S digital (INMP441/SPH0645 etc.)
            final micType = arMod['micType'] ?? arMod['type'];
            if (micType is int && micType > 0) {
              hasMic = true;
            }
            // Some builds use a simple boolean
            if (arMod['mic'] == true) {
              hasMic = true;
            }
          }
        }
        // Fallback: top-level mic field
        if (!hasMic && info['mic'] == true) {
          hasMic = true;
        }
        // If usermod is present but mic detection is ambiguous, assume mic
        // is present — the NGL-CTRL-P1 always has an onboard MEMS mic.
        if (!hasMic) {
          hasMic = true;
        }
      }

      // 4. Fetch effect list and identify audio-reactive effects
      //    SR WLED marks audio-reactive effects with a "* " prefix.
      final List<int> arEffectIds = [];
      final effects = await _fetchJson('$baseUrl/json/effects');
      if (effects == null) {
        // Effects list unavailable — still return what we know
        return AudioReactiveCapability(
          hasAudioReactiveUsermod: hasUsermod,
          hasMicHardware: hasMic,
          audioReactiveEffects: arEffectIds,
          usermodeVersion: usermodeVersion,
        );
      }

      // /json/effects returns a JSON array of effect name strings
      // Index in the array = effect ID
      if (effects is List) {
        // Primary: SR WLED marks audio-reactive effects with "* " prefix
        for (int i = 0; i < effects.length; i++) {
          final name = effects[i];
          if (name is String && name.startsWith('* ')) {
            arEffectIds.add(i);
          }
        }

        // Fallback: some builds (e.g. v0.15.x Dig-Octa Audioreactive)
        // list audio effects by plain name without the asterisk prefix.
        if (arEffectIds.isEmpty && hasUsermod) {
          const arPatterns = [
            'gravimeter', 'geq', 'freqwave', 'dj light', 'waverly',
            'rocktaves', 'audioreactive', 'ripple peak',
            'puddles', 'puddlepeak', 'juggles', 'matripix', 'akemi',
            'blurz', 'funky plank', 'fizzybubbles', 'noisemove',
            'freqmap', 'freqmatrix', 'freqpixels', 'binmap',
            'noisepal', 'plasmoid', 'pixels', 'pixelwave',
            'midnoise', 'noisemeter', 'gravcent', 'gravfreq',
            'waterfall', 'noisefire',
          ];
          for (int i = 0; i < effects.length; i++) {
            final name = effects[i];
            if (name is String) {
              final lower = name.toLowerCase();
              if (arPatterns.any((p) => lower.contains(p))) {
                arEffectIds.add(i);
              }
            }
          }
        }
      }

      return AudioReactiveCapability(
        hasAudioReactiveUsermod: hasUsermod,
        hasMicHardware: hasMic,
        audioReactiveEffects: arEffectIds,
        usermodeVersion: usermodeVersion,
      );
    } catch (e) {
      debugPrint('AudioCapabilityDetector error: $e');
      return AudioReactiveCapability.notSupported();
    }
  }

  /// Fetch and decode JSON from [url]. Returns null on any failure.
  Future<dynamic> _fetchJson(String url) async {
    try {
      final client = HttpClient()..connectionTimeout = _timeout;
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(_timeout);
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(body);
      }
    } catch (e) {
      debugPrint('AudioCapabilityDetector fetch $url failed: $e');
    }
    return null;
  }
}

/// Probes the controller at [ip] for audio-reactive capabilities.
///
/// Usage: `ref.watch(audioCapabilityProvider('192.168.50.91'))`
final audioCapabilityProvider =
    FutureProvider.family<AudioReactiveCapability, String>((ref, ip) {
  return AudioCapabilityDetector().detect(ip);
});

/// Fetches the full effect name list from the controller at [ip].
///
/// Returns an empty list on failure. Index in the list = effect ID.
final wledEffectNamesProvider =
    FutureProvider.family<List<String>, String>((ref, ip) async {
  try {
    final detector = AudioCapabilityDetector();
    final result = await detector._fetchJson('http://$ip/json/effects');
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
  } catch (e) {
    debugPrint('Failed to fetch effect names: $e');
  }
  return [];
});
