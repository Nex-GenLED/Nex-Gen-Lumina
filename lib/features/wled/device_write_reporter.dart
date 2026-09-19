import 'package:flutter/material.dart';

/// Surfaces failures from FIRE-AND-FORGET device writes — live previews, the
/// installer's walk cursor, the refine spotlight: writes issued from a
/// throttle timer whose result nobody was looking at.
///
/// Those call sites all had the same shape (design-studio-audit-2026-09-19
/// F7): `await writer.applyPerPixel(...)` with the returned bool dropped, so a
/// controller that stopped answering looked exactly like one that was
/// following along. This keeps the noise down for a stream of writes: it
/// speaks once when a streak of failures STARTS, and once when it ends.
class DeviceWriteReporter {
  DeviceWriteReporter({required this.what});

  /// What the writes are for, as the user would say it — e.g. "preview".
  final String what;

  bool _failing = false;

  /// True while the most recent write failed.
  bool get isFailing => _failing;

  /// Feed every write result through here. Returns [ok] unchanged.
  bool report(BuildContext context, bool ok) {
    if (ok == !_failing) return ok; // no change in state → stay quiet
    _failing = !ok;
    if (!context.mounted) return ok;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return ok;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok
            ? 'Reconnected — your lights are following the $what again.'
            : "Can't reach your lights — they are NOT showing this $what."),
        backgroundColor: ok ? Colors.green : Colors.red.shade800,
        duration: Duration(seconds: ok ? 2 : 5),
      ));
    return ok;
  }
}
