import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #118 — WHICH CONTROLLER THIS PHONE DRIVES.
///
/// The selection used to be an in-memory address that auto-connect filled
/// only while it was empty. Nothing ever checked it again, so it went stale
/// when the account changed, when a record's address changed (an installer
/// re-add or a discovery re-save on another phone), when a cold start read an
/// old address from the local cache, or when the active record was deleted —
/// and the only way out was "Set as Active".
///
/// A selection is now a controller RECORD, by its document id, and its
/// address is always that record's CURRENT address. [ControllerSelectionNotifier]
/// re-resolves on every change to the account or its records, not only when
/// the selection is empty; `selectedDeviceIpProvider` is derived from it.
///
/// A [transient] selection is an address that is not (yet) one of the
/// account's records: a device being set up through discovery, Bluetooth or
/// the installer wizard. The resolver never moves a transient selection; it
/// becomes the record once a record with that address appears.
@immutable
class ControllerSelection {
  const ControllerSelection({
    this.controllerId,
    this.ip,
    this.transient = false,
    this.choices = const [],
  });

  /// Nothing selected.
  static const none = ControllerSelection();

  /// The selected record's document id. Null for none and for a transient
  /// address.
  final String? controllerId;

  /// The address in use: the selected record's current address, or the
  /// transient address.
  final String? ip;

  /// An address that is not one of this account's records.
  final bool transient;

  /// Record ids the customer must choose between ("Which controller should
  /// this phone use?"). Non-empty only when two or more controllers answered
  /// and nothing else says which one this phone uses; nothing is selected
  /// meanwhile.
  final List<String> choices;

  bool get needsChoice => choices.length >= 2;

  factory ControllerSelection.record(ControllerInfo record) =>
      ControllerSelection(controllerId: record.id, ip: record.ip.trim());

  factory ControllerSelection.address(String ip) =>
      ControllerSelection(ip: ip, transient: true);

  @override
  bool operator ==(Object other) =>
      other is ControllerSelection &&
      other.controllerId == controllerId &&
      other.ip == ip &&
      other.transient == transient &&
      listEquals(other.choices, choices);

  @override
  int get hashCode =>
      Object.hash(controllerId, ip, transient, Object.hashAll(choices));

  @override
  String toString() => transient
      ? 'ControllerSelection(transient)'
      : controllerId == null
          ? (needsChoice
              ? 'ControllerSelection(choose 1 of ${choices.length})'
              : 'ControllerSelection.none')
          : 'ControllerSelection($controllerId)';
}

/// What [resolveControllerSelection] decided.
@immutable
class ControllerResolution {
  const ControllerResolution(this.selection, {this.probeNeeded = false});
  final ControllerSelection selection;

  /// Several records and nothing says which one this phone uses: ask which
  /// of them answer before choosing (see [controllerReachabilityProbeProvider]).
  final bool probeNeeded;
}

/// THE selection rule, as a pure function of the CURRENT account's records.
///
/// [records] are in the controllers stream's order (newest first) and may
/// include records without an address; those are never selected.
///
///   1. A transient address is kept as it is — the resolver never pulls a
///      device that is being set up away — and becomes the record once a
///      record with that address exists.
///   2. A selected record that still exists stays selected, at its CURRENT
///      address. A record that is gone (deleted, or its address cleared)
///      drops out and the rules below choose again.
///   3. Without [autoSelect] (the app shell is not running) nothing else is
///      chosen.
///   4. The record this phone saved for this account, if it still exists.
///      With two or more records and the saved choice not read yet, wait.
///   5. No usable record: nothing.
///   6. Exactly one: that one, silently.
///   7. Several: the one this phone most recently connected to.
///   8. No history: ask which answer ([ControllerResolution.probeNeeded]);
///      one answers → that one; two or more → the customer chooses
///      ([ControllerSelection.choices]); none answers (away from home) → the
///      newest record, as before.
ControllerResolution resolveControllerSelection({
  required List<ControllerInfo> records,
  required ControllerSelection current,
  required bool autoSelect,
  String? savedId,
  bool savedLoaded = true,
  Map<String, DateTime> lastConnected = const {},
  Set<String>? answered,
}) {
  final usable = [
    for (final r in records)
      if (r.ip.trim().isNotEmpty) r,
  ];
  ControllerInfo? byId(String? id) {
    if (id == null) return null;
    for (final r in usable) {
      if (r.id == id) return r;
    }
    return null;
  }

  ControllerResolution pick(ControllerInfo r) =>
      ControllerResolution(ControllerSelection.record(r));

  // 1. A device being set up.
  if (current.transient && current.ip != null) {
    for (final r in usable) {
      if (r.ip.trim() == current.ip) return pick(r);
    }
    return ControllerResolution(current);
  }

  // 2. The selected record, at its current address.
  final selected = byId(current.controllerId);
  if (selected != null) return pick(selected);

  // 3.
  if (!autoSelect) return const ControllerResolution(ControllerSelection.none);

  // 4.
  if (!savedLoaded && usable.length >= 2) {
    return const ControllerResolution(ControllerSelection.none);
  }
  final saved = byId(savedId);
  if (saved != null) return pick(saved);

  // 5, 6.
  if (usable.isEmpty) return const ControllerResolution(ControllerSelection.none);
  if (usable.length == 1) return pick(usable.single);

  // 7.
  ControllerInfo? recent;
  DateTime? recentAt;
  for (final r in usable) {
    final at = lastConnected[r.id];
    if (at != null && (recentAt == null || at.isAfter(recentAt))) {
      recent = r;
      recentAt = at;
    }
  }
  if (recent != null) return pick(recent);

  // 8.
  if (answered == null) {
    return const ControllerResolution(ControllerSelection.none,
        probeNeeded: true);
  }
  final answering = [
    for (final r in usable)
      if (answered.contains(r.id)) r,
  ];
  if (answering.length == 1) return pick(answering.single);
  if (answering.length >= 2) {
    return ControllerResolution(ControllerSelection(
        choices: [for (final r in answering) r.id]));
  }
  return pick(usable.first);
}

/// Where the selection survives a restart: per account, on this phone only.
abstract class ControllerSelectionStore {
  Future<String?> readSelected(String uid);
  Future<void> writeSelected(String uid, String? controllerId);
  Future<Map<String, DateTime>> readConnected(String uid);
  Future<void> writeConnected(String uid, Map<String, DateTime> stamps);
}

/// SharedPreferences, keyed by account. Every failure reads as "nothing
/// saved": a missing preference must never stop the app choosing a
/// controller.
class SharedPrefsControllerSelectionStore implements ControllerSelectionStore {
  const SharedPrefsControllerSelectionStore();

  static String selectedKey(String uid) => 'controller_selection.v1.selected.$uid';
  static String connectedKey(String uid) =>
      'controller_selection.v1.connected.$uid';

  @override
  Future<String?> readSelected(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(selectedKey(uid));
    } catch (e) {
      debugPrint('ControllerSelection: read failed (non-fatal) — $e');
      return null;
    }
  }

  @override
  Future<void> writeSelected(String uid, String? controllerId) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (controllerId == null) {
        await p.remove(selectedKey(uid));
      } else {
        await p.setString(selectedKey(uid), controllerId);
      }
    } catch (e) {
      debugPrint('ControllerSelection: write failed (non-fatal) — $e');
    }
  }

  @override
  Future<Map<String, DateTime>> readConnected(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(connectedKey(uid));
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String && e.value is int)
            e.key as String:
                DateTime.fromMillisecondsSinceEpoch(e.value as int),
      };
    } catch (e) {
      debugPrint('ControllerSelection: read failed (non-fatal) — $e');
      return {};
    }
  }

  @override
  Future<void> writeConnected(String uid, Map<String, DateTime> stamps) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(connectedKey(uid), jsonEncode({
        for (final e in stamps.entries) e.key: e.value.millisecondsSinceEpoch,
      }));
    } catch (e) {
      debugPrint('ControllerSelection: write failed (non-fatal) — $e');
    }
  }
}

final controllerSelectionStoreProvider = Provider<ControllerSelectionStore>(
    (ref) => const SharedPrefsControllerSelectionStore());

/// Does a controller answer at [ip] on this network? One short `/json/info`
/// read, used only when an account has two or more records and nothing says
/// which one this phone uses. Away from home nothing answers, and the
/// resolver falls back to the newest record.
typedef ControllerReachabilityProbe = Future<bool> Function(String ip);

Future<bool> probeControllerAddress(String ip) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final req = await client
        .getUrl(Uri.parse('http://$ip/json/info'))
        .timeout(const Duration(seconds: 2));
    final res = await req.close().timeout(const Duration(seconds: 2));
    await res.drain<void>();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

final controllerReachabilityProbeProvider =
    Provider<ControllerReachabilityProbe>((ref) => probeControllerAddress);

/// The selection, re-resolved on every change to the signed-in account, its
/// controller records, or the records deleted from this phone.
///
/// Choosing among several records (rules 4 and on of
/// [resolveControllerSelection]) is armed by the app shell through
/// [enableAutoSelect], as auto-connect always was; outside the shell (the
/// installer wizard, tests) a selection is only ever made explicitly, and is
/// still followed and dropped by the same rules.
class ControllerSelectionNotifier extends Notifier<ControllerSelection> {
  String? _uid;
  List<ControllerInfo>? _records;
  Set<String> _deleted = const {};
  String? _saved;
  bool _savedLoaded = false;
  Map<String, DateTime> _connected = {};
  bool _autoSelect = false;
  String? _answeredFor;
  Set<String>? _answered;
  String? _probingFor;
  int _generation = 0;
  bool _disposed = false;

  @override
  ControllerSelection build() {
    ref.onDispose(() => _disposed = true);
    _uid = ref.read(effectiveUserUidProvider);
    ref.listen<String?>(effectiveUserUidProvider, _onAccount);
    ref.listen<AsyncValue<List<ControllerInfo>>>(controllersStreamProvider,
        (_, next) {
      // Only a delivered list: while the stream reloads for a new account it
      // still carries the PREVIOUS account's records.
      if (next is AsyncData<List<ControllerInfo>>) {
        _records = next.value;
        _resolve();
      }
    });
    ref.listen<Set<String>>(deletedControllerIdsProvider, (_, next) {
      _deleted = next;
      _resolve();
    });
    final current = ref.read(controllersStreamProvider);
    if (current is AsyncData<List<ControllerInfo>>) _records = current.value;
    _deleted = ref.read(deletedControllerIdsProvider);
    _load(_uid);
    return ControllerSelection.none;
  }

  /// Arms choosing among several records. Called by the app shell.
  void enableAutoSelect() {
    if (_disposed || _autoSelect) return;
    _autoSelect = true;
    _resolve();
  }

  /// The customer chose [controllerId] ("Use this controller", the Home
  /// router menu, the "Which controller" prompt).
  void use(String controllerId) {
    if (_disposed) return;
    for (final r in _usable()) {
      if (r.id == controllerId) {
        _set(ControllerSelection.record(r));
        return;
      }
    }
  }

  /// A setup flow points at [ip]: the account's record at that address, or a
  /// transient address the resolver leaves alone until it is released or
  /// becomes a record.
  void pointAt(String ip) {
    if (_disposed) return;
    final address = ip.trim();
    if (address.isEmpty) return;
    for (final r in _usable()) {
      if (r.ip.trim() == address) {
        _set(ControllerSelection.record(r));
        return;
      }
    }
    _set(ControllerSelection.address(address));
  }

  /// A setup flow is done with its transient address ([ip], or whichever).
  void release({String? ip}) {
    if (_disposed || !state.transient) return;
    if (ip != null && state.ip != ip.trim()) return;
    _set(ControllerSelection.none);
    _resolve();
  }

  /// Drops the selection; the shell then chooses again.
  void clear() {
    if (_disposed) return;
    _set(ControllerSelection.none);
    _resolve();
  }

  /// The selected record answered — remembered as the one this phone most
  /// recently connected to (rule 7).
  void markConnected() {
    final uid = _uid;
    final id = state.controllerId;
    if (_disposed || uid == null || id == null) return;
    _connected = {..._connected, id: DateTime.now()};
    if (_persists) {
      unawaited(ref.read(controllerSelectionStoreProvider)
          .writeConnected(uid, _connected));
    }
  }

  List<ControllerInfo> _usable() => [
        for (final r in _records ?? const <ControllerInfo>[])
          if (!_deleted.contains(r.id) && r.ip.trim().isNotEmpty) r,
      ];

  /// Saved on this phone only for the signed-in user's own account, never
  /// for a customer an installer is viewing.
  bool get _persists {
    final authUid = ref.read(authStateProvider).valueOrNull?.uid;
    return _uid != null && _uid == authUid;
  }

  void _onAccount(String? previous, String? next) {
    _generation++;
    _uid = next;
    _records = null;
    _saved = null;
    _savedLoaded = false;
    _connected = {};
    _answered = null;
    _answeredFor = null;
    _probingFor = null;
    // A previous account's selection never survives into the next one. A
    // first sign-in has no previous account; a device pointed at before auth
    // answered is kept.
    if (previous != null && previous != next) _set(ControllerSelection.none);
    _load(next);
  }

  Future<void> _load(String? uid) async {
    if (uid == null) return;
    final gen = _generation;
    final store = ref.read(controllerSelectionStoreProvider);
    final saved = await store.readSelected(uid);
    final connected = await store.readConnected(uid);
    if (_disposed || gen != _generation) return;
    _saved = saved;
    _connected = connected;
    _savedLoaded = true;
    _resolve();
  }

  static String _signature(List<ControllerInfo> records) =>
      [for (final r in records) '${r.id}@${r.ip.trim()}'].join('|');

  void _resolve() {
    if (_disposed) return;
    final records = _records;
    if (records == null) return;
    final usable = [
      for (final r in records)
        if (!_deleted.contains(r.id)) r,
    ];
    final sig = _signature(usable);
    final out = resolveControllerSelection(
      records: usable,
      current: state,
      autoSelect: _autoSelect,
      savedId: _saved,
      savedLoaded: _savedLoaded,
      lastConnected: _connected,
      answered: _answeredFor == sig ? _answered : null,
    );
    if (out.probeNeeded) unawaited(_probe(usable, sig));
    _set(out.selection);
  }

  Future<void> _probe(List<ControllerInfo> records, String sig) async {
    if (_probingFor == sig) return;
    _probingFor = sig;
    final gen = _generation;
    final probe = ref.read(controllerReachabilityProbeProvider);
    final usable = [
      for (final r in records)
        if (r.ip.trim().isNotEmpty) r,
    ];
    final results = await Future.wait([
      for (final r in usable)
        probe(r.ip.trim()).catchError((Object _) => false),
    ]);
    if (_disposed || gen != _generation) return;
    _probingFor = null;
    _answeredFor = sig;
    _answered = {
      for (var i = 0; i < usable.length; i++)
        if (results[i]) usable[i].id,
    };
    _resolve();
  }

  void _set(ControllerSelection next) {
    if (_disposed || next == state) return;
    state = next;
    final id = next.controllerId;
    final uid = _uid;
    if (id != null && uid != null && id != _saved && _persists) {
      _saved = id;
      unawaited(ref.read(controllerSelectionStoreProvider).writeSelected(uid, id));
    }
  }
}

final controllerSelectionProvider =
    NotifierProvider<ControllerSelectionNotifier, ControllerSelection>(
        ControllerSelectionNotifier.new);
