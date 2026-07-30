// Thin WLED HTTP client for the bench harness (dart:io, no package deps).
//
// DISCIPLINE ENFORCED AS CODE:
//  - EVERY POST sets `Content-Type: application/json` (a missing header cost us
//    a false stall this week — see the schedule saga). See [_post].
//  - cfg flash-saves can black out the web server for MINUTES; [patientVerify]
//    polls liveness and NEVER spurious-fails a mid-stall controller.

import 'dart:convert';
import 'dart:io';

class WledClient {
  final String base; // e.g. http://192.168.1.150
  final HttpClient _http = HttpClient();

  WledClient(this.base) {
    _http.connectionTimeout = const Duration(seconds: 5);
  }

  void close() => _http.close(force: true);

  Uri _u(String path) => Uri.parse('$base$path');

  Future<Map<String, dynamic>?> getJson(String path,
      {Duration timeout = const Duration(seconds: 8)}) async {
    try {
      final req = await _http.getUrl(_u(path)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      if (body.trim().isEmpty) return null;
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getState() => getJson('/json/state');
  Future<Map<String, dynamic>?> getInfo() => getJson('/json/info');
  Future<Map<String, dynamic>?> getCfg() => getJson('/json/cfg');
  Future<Map<String, dynamic>?> getPresets() => getJson('/presets.json');

  /// Liveness: a fast GET /json/info that returns true iff the controller
  /// answers a parseable body within [timeout].
  Future<bool> ping({Duration timeout = const Duration(seconds: 4)}) async {
    final info = await getJson('/json/info', timeout: timeout);
    return info != null;
  }

  /// POST with the MANDATORY Content-Type header. Returns true on a 2xx.
  /// A timeout/connection error returns false (caller decides: a cfg write that
  /// times out is likely the post-commit stall, not a real failure).
  Future<bool> _post(String path, Map<String, dynamic> payload,
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final req = await _http.postUrl(_u(path)).timeout(timeout);
      final bytes = utf8.encode(jsonEncode(payload));
      // DISCIPLINE: Content-Type on every POST.
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // WLED's tiny HTTP server rejects CHUNKED transfer-encoding (which dart:io
      // uses by default when contentLength is unset) — set it so a real
      // Content-Length header is sent, exactly like curl. Omitting this made
      // every POST silently fail (inaugural bench run, 2026-07-24).
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> postState(Map<String, dynamic> payload,
          {Duration timeout = const Duration(seconds: 10)}) =>
      _post('/json/state', payload, timeout: timeout);

  Future<bool> postCfg(Map<String, dynamic> payload,
          {Duration timeout = const Duration(seconds: 15)}) =>
      _post('/json/cfg', payload, timeout: timeout);

  /// Patient verification through the post-commit network stall: poll [alive]
  /// every [interval] up to [maxWait]; on the first live response run [confirm]
  /// (which reads back and returns true iff the write landed). Never re-POSTs.
  /// Returns (confirmed, stallSeconds). A mid-stall controller is WAITED on,
  /// never spurious-failed.
  /// [maxConfirmAttempts] bounds how many times we re-read a LIVE controller
  /// that keeps reporting the write did not land. Stall polls (controller not
  /// answering) do NOT count against it, so genuine multi-minute flash stalls
  /// are still waited out — but a responsive controller that simply did not
  /// persist the write fails in ~1 minute instead of pinning the suite for 5.
  Future<({bool confirmed, int stallSeconds})> patientVerify({
    required Future<bool> Function() confirm,
    Duration interval = const Duration(seconds: 20),
    Duration maxWait = const Duration(minutes: 5),
    int maxConfirmAttempts = 4,
    void Function(int elapsedSec)? onPoll,
  }) async {
    final started = DateTime.now();
    // Fast path: a healthy controller (0.15.1 has no stall regression) confirms
    // immediately — don't pay the poll interval before the first look.
    if (await ping(timeout: const Duration(seconds: 3))) {
      if (await confirm()) return (confirmed: true, stallSeconds: 0);
    }
    // AUDIT FIX (2026-07-30): this loop used to `return` on the FIRST live
    // confirm attempt, so despite maxWait=5min it made exactly TWO attempts
    // ~20s apart. Every "verified=false (20s)" in the historical logs is that
    // bug, not a controller that was given five minutes and failed. A cfg
    // flash-commit can land AFTER the first post-stall look, so keep retrying
    // the confirm until it succeeds or maxWait genuinely elapses.
    var waited = Duration.zero;
    var liveConfirmAttempts = 1; // the fast-path confirm above
    while (waited < maxWait && liveConfirmAttempts < maxConfirmAttempts) {
      await Future<void>.delayed(interval);
      waited += interval;
      final sec = DateTime.now().difference(started).inSeconds;
      onPoll?.call(sec);
      if (!await ping()) continue; // still stalled — does NOT burn an attempt
      liveConfirmAttempts++;
      if (await confirm()) return (confirmed: true, stallSeconds: sec);
      // Live but not yet confirmed — the write may still be committing.
    }
    return (
      confirmed: false,
      stallSeconds: DateTime.now().difference(started).inSeconds
    );
  }
}
