import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;
import 'package:nexgen_command/features/wled/wled_models.dart';

/// A fingerprinted intent record persisted by [ActivePresetLabelNotifier].
///
/// Stores the user-facing label alongside enough device-state fingerprint
/// to detect whether the persisted label still matches what the controller
/// is actually playing. On cold start the notifier loads this record into
/// escrow and reconciles it against the freshly-polled WLED state before
/// committing it to UI — eliminating the "Now Playing shows Warm White
/// regardless of device state" bug.
///
/// Fingerprint composition: effectId (WLED fx), presetId (WLED ps), and a
/// 12-char hex slice of the first three segment colors. A match on all
/// three fields means the device is almost certainly still playing what
/// the label says; a mismatch on any field means the device has drifted
/// (manual web-UI tap, schedule fired, controller rebooted to a default,
/// etc.) and the persisted label is stale.
class LabelIntent {
  final String label;
  final int effectId;
  final int presetId;
  final String colorFingerprint;
  final DateTime writtenAt;

  const LabelIntent({
    required this.label,
    required this.effectId,
    required this.presetId,
    required this.colorFingerprint,
    required this.writtenAt,
  });

  /// Build a [LabelIntent] from a label string and the device state that
  /// was active when the label was written.
  factory LabelIntent.fromDeviceState({
    required String label,
    required WledStateModel deviceState,
    DateTime? now,
  }) {
    return LabelIntent(
      label: label,
      effectId: deviceState.effectId,
      presetId: deviceState.presetId,
      colorFingerprint: fingerprintForState(deviceState),
      writtenAt: now ?? DateTime.now(),
    );
  }

  /// Hex slice of the first three segment colors, joined and truncated to
  /// 12 characters. Order matters; same colors in a different order produce
  /// a different fingerprint. Stable across cold-restart because both the
  /// stored and recomputed sides read from the same WledStateModel fields.
  ///
  /// 1 color  → 6 chars
  /// 2 colors → 12 chars
  /// 3+ colors → 12 chars (first 12)
  /// 0 colors → '' (empty — degenerate, only happens before first poll)
  static String fingerprintForState(WledStateModel state) {
    final List<Color> colors = state.colorSequence.isNotEmpty
        ? state.colorSequence
        : <Color>[state.color];
    final hexParts = <String>[];
    for (var i = 0; i < math.min(3, colors.length); i++) {
      final c = colors[i];
      final r = (c.r * 255).round().clamp(0, 255);
      final g = (c.g * 255).round().clamp(0, 255);
      final b = (c.b * 255).round().clamp(0, 255);
      hexParts.add(_h2(r) + _h2(g) + _h2(b));
    }
    final joined = hexParts.join();
    return joined.length > 12 ? joined.substring(0, 12) : joined;
  }

  static String _h2(int v) => v.toRadixString(16).padLeft(2, '0');

  /// Match if and only if all three fingerprint components agree. We do NOT
  /// require [writtenAt] to match — the persisted timestamp is informational.
  bool matches(WledStateModel deviceState) {
    return effectId == deviceState.effectId &&
        presetId == deviceState.presetId &&
        colorFingerprint == fingerprintForState(deviceState);
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'effectId': effectId,
        'presetId': presetId,
        'colorFingerprint': colorFingerprint,
        'writtenAt': writtenAt.toIso8601String(),
      };

  /// Parse from a JSON object. Returns null if the shape is invalid — the
  /// caller treats null as "no usable persisted intent."
  static LabelIntent? fromJson(Map<String, dynamic> json) {
    try {
      final label = json['label'];
      final effectId = json['effectId'];
      final presetId = json['presetId'];
      final colorFingerprint = json['colorFingerprint'];
      final writtenAt = json['writtenAt'];
      if (label is! String || label.isEmpty) return null;
      if (effectId is! int) return null;
      if (presetId is! int) return null;
      if (colorFingerprint is! String) return null;
      if (writtenAt is! String) return null;
      return LabelIntent(
        label: label,
        effectId: effectId,
        presetId: presetId,
        colorFingerprint: colorFingerprint,
        writtenAt: DateTime.parse(writtenAt),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse from a JSON-encoded string. Returns null on any decode failure.
  static LabelIntent? decode(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  @override
  String toString() =>
      'LabelIntent(label: $label, fx: $effectId, ps: $presetId, color: $colorFingerprint)';
}
