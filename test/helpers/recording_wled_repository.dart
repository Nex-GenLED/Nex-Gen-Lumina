// A recording fake controller for tests. Shared, so a test asserting what the
// app sent does not have to restate the whole WledRepository interface.
//
//   final repo = RecordingWledRepository();
//   ... drive the app ...
//   expect(repo.applied.single['seg'], hasLength(2));

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/audioreactive_health.dart'
    show AudioReactiveConfigSource;
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ClockInfoSource, ControllerClockInfo;
import 'package:nexgen_command/features/wled/wled_payload_utils.dart'
    show normalizeWledCfgPayload;
import 'package:nexgen_command/features/wled/wled_repository.dart';

class RecordingWledRepository
    implements WledRepository, ClockInfoSource, AudioReactiveConfigSource {
  RecordingWledRepository({
    this.succeed = true,
    this.state,
    this.throwOnWrite = false,
    this.clockInfo,
    this.audioReactiveEnabled,
    this.applyConfigSucceeds = false,
    this.simulatedTargetFps,
    this.audioReactiveWriteSticks = true,
  });

  /// When false, a successful AudioReactive disable leaves the device flag ON
  /// (the write that "did not take"), so the healer's readback and backoff
  /// have something to catch.
  bool audioReactiveWriteSticks;

  /// Canned answer for the healer's clock read (null = unreachable).
  ControllerClockInfo? clockInfo;

  /// Canned `cfg.um.AudioReactive.enabled` (null = no usermod / unreadable).
  bool? audioReactiveEnabled;

  /// What [applyConfig] reports. Default false, matching the helper's history
  /// (most schedule tests exercise the refusal paths); set true to drive a
  /// write path to completion.
  bool applyConfigSucceeds;

  /// The device's `hw.led.fps` as the real transports would have cached it
  /// from a cfg read; feeds the wire mirror below.
  int? simulatedTargetFps;

  /// Every cfg body as the CALLER handed it over.
  final List<Map<String, dynamic>> appliedConfigs = [];

  /// Every cfg body as it would reach the controller: the real transports
  /// (WledService._postConfig, the config pusher, the relay) run
  /// [normalizeWledCfgPayload] at the write boundary, so this mirror lets a
  /// test assert the wire shape — gamma and frame rate — without HTTP.
  final List<Map<String, dynamic>> wireConfigs = [];

  /// What every write returns.
  bool succeed;

  /// When set, every write throws instead of returning.
  bool throwOnWrite;

  /// What [getState] returns. Null is "the controller did not answer".
  Map<String, dynamic>? state;

  /// Every `applyJson` payload, deep-copied, in order.
  final List<Map<String, dynamic>> applied = [];

  /// Every `setState` call, in order.
  final List<Map<String, dynamic>> setStates = [];

  /// Every `savePreset` call, in order.
  final List<Map<String, dynamic>> savedPresets = [];

  int getStateCalls = 0;

  int get writeCount => applied.length + setStates.length + savedPresets.length;

  bool _write() {
    if (throwOnWrite) throw StateError('controller write failed');
    return succeed;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applied.add(_copy(payload));
    return _write();
  }

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async {
    setStates.add({
      if (on != null) 'on': on,
      if (brightness != null) 'brightness': brightness,
      if (speed != null) 'speed': speed,
      if (white != null) 'white': white,
    });
    return _write();
  }

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    savedPresets.add({
      'presetId': presetId,
      'presetName': presetName,
      'state': _copy(state),
    });
    return _write();
  }

  @override
  Future<Map<String, dynamic>?> getState() async {
    getStateCalls++;
    return state;
  }

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    appliedConfigs.add(_copy(cfg));
    wireConfigs.add(
        normalizeWledCfgPayload(_copy(cfg), currentFps: simulatedTargetFps));
    if (throwOnWrite) throw StateError('controller write failed');
    if (applyConfigSucceeds &&
        audioReactiveWriteSticks &&
        cfg.containsKey('um')) {
      audioReactiveEnabled = false; // the device honoured the disable
    }
    return applyConfigSucceeds;
  }

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async => clockInfo;

  @override
  Future<bool?> readAudioReactiveEnabled() async => audioReactiveEnabled;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<List<WledSegment>> fetchSegments() async => const [];
  @override
  Future<bool> renameSegment({required int id, required String name}) async =>
      false;
  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async =>
      false;
  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => null;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  void reset() {}
}
